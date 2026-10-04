//! Deliberately bounded Matroska HEVC packet observations, not a playback demuxer.
//! Unknown-size Segment is allowed; unknown-size clusters and video lacing are
//! refused. No recovery scan, skipped corrupt bytes or implicit EOF on error.
use std::{
    collections::HashSet,
    io::{BufReader, Read, Write},
};

use crate::{COUNT_LIMIT, Failure, RECORD_LIMIT, hex, parse_metadata, write_json};
use sha2::{Digest, Sha256};

pub const MOVIE_LIMIT: u64 = 1024 * 1024 * 1024 * 1024;
pub const PACKET_LIMIT: usize = 16 * 1024 * 1024;
const CONFIG_LIMIT: usize = 1024 * 1024;
const ELEMENT_LIMIT: u64 = 128_000_000;
const BLOCK_LIMIT: u64 = 32_000_000;
const EBML: u32 = 0x1a45dfa3;
const SEGMENT: u32 = 0x18538067;
const INFO: u32 = 0x1549a966;
const TRACKS: u32 = 0x1654ae6b;
const CLUSTER: u32 = 0x1f43b675;

struct Reader<R: Read> {
    input: BufReader<R>,
    position: u64,
    length: u64,
    hash: Sha256,
    elements: u64,
}
struct Element {
    id: u32,
    end: u64,
    unknown: bool,
}
impl<R: Read> Reader<R> {
    fn exact(&mut self, out: &mut [u8]) -> Result<(), Failure> {
        if out.len() as u64 > self.length - self.position {
            return Err(Failure::Framing);
        }
        self.input.read_exact(out).map_err(|_| Failure::InputIO)?;
        self.hash.update(&*out);
        self.position += out.len() as u64;
        Ok(())
    }
    fn byte(&mut self) -> Result<u8, Failure> {
        let mut b = [0];
        self.exact(&mut b)?;
        Ok(b[0])
    }
    fn vint(&mut self, id: bool) -> Result<(u64, bool), Failure> {
        let first = self.byte()?;
        let width = first.leading_zeros() as usize + 1;
        if width > if id { 4 } else { 8 } {
            return Err(Failure::Framing);
        }
        let mut value = if id {
            first as u64
        } else {
            first as u64 & (0xffu64 >> width)
        };
        for _ in 1..width {
            value = (value << 8) | self.byte()? as u64;
        }
        if id && value == (1u64 << (7 * width + 1)) - 1 {
            return Err(Failure::Framing);
        }
        let unknown = !id && value == ((1u64 << (7 * width)) - 1);
        Ok((value, unknown))
    }
    fn element(
        &mut self,
        parent: u64,
        allow_unknown_segment: bool,
    ) -> Result<Option<Element>, Failure> {
        if self.position == parent {
            return Ok(None);
        }
        if self.position > parent || self.elements == ELEMENT_LIMIT {
            return Err(Failure::Bounds);
        }
        self.elements += 1;
        let (id, _) = self.vint(true)?;
        let (length, unknown) = self.vint(false)?;
        if self.position > parent || (unknown && !(allow_unknown_segment && id == SEGMENT as u64)) {
            return Err(Failure::UnsupportedContainer);
        }
        let end = if unknown {
            parent
        } else {
            let end = self.position.checked_add(length).ok_or(Failure::Bounds)?;
            if end > parent {
                return Err(Failure::Framing);
            }
            end
        };
        Ok(Some(Element {
            id: id as u32,
            end,
            unknown,
        }))
    }
    fn skip(&mut self, end: u64) -> Result<(), Failure> {
        if end < self.position || end > self.length {
            return Err(Failure::Framing);
        }
        let mut buffer = [0; 32 * 1024];
        while self.position < end {
            let n = (end - self.position).min(buffer.len() as u64) as usize;
            self.exact(&mut buffer[..n])?;
        }
        Ok(())
    }
    fn bytes(&mut self, end: u64, limit: usize) -> Result<Vec<u8>, Failure> {
        let length = end.checked_sub(self.position).ok_or(Failure::Framing)?;
        if length > limit as u64 {
            return Err(Failure::Bounds);
        }
        let mut bytes = vec![0; length as usize];
        self.exact(&mut bytes)?;
        Ok(bytes)
    }
    fn unsigned(&mut self, end: u64) -> Result<u64, Failure> {
        let data = self.bytes(end, 8)?;
        if data.is_empty() {
            return Err(Failure::Framing);
        }
        Ok(data.iter().fold(0, |value, b| (value << 8) | *b as u64))
    }
    fn finish(&mut self, e: &Element) -> Result<(), Failure> {
        self.skip(e.end)
    }
}

#[derive(Default)]
struct Track {
    number: u64,
    kind: u64,
    codec: Vec<u8>,
    config: Vec<u8>,
    width: u64,
    height: u64,
    crop: [u64; 4],
    display: [Option<u64>; 2],
    display_unit: u64,
    delay: u64,
    default_duration: Option<u64>,
    unsupported: bool,
}
fn once(seen: &mut HashSet<u32>, id: u32) -> Result<(), Failure> {
    if !seen.insert(id) {
        return Err(Failure::Framing);
    }
    Ok(())
}
fn video<R: Read>(r: &mut Reader<R>, end: u64, track: &mut Track) -> Result<(), Failure> {
    let mut seen = HashSet::new();
    while let Some(e) = r.element(end, false)? {
        match e.id {
            0xb0 | 0xba | 0x54aa | 0x54bb | 0x54cc | 0x54dd | 0x54b0 | 0x54ba | 0x54b2 => {
                once(&mut seen, e.id)?;
                let value = r.unsigned(e.end)?;
                match e.id {
                    0xb0 => track.width = value,
                    0xba => track.height = value,
                    0x54cc => track.crop[0] = value,
                    0x54dd => track.crop[1] = value,
                    0x54bb => track.crop[2] = value,
                    0x54aa => track.crop[3] = value,
                    0x54b0 => track.display[0] = Some(value),
                    0x54ba => track.display[1] = Some(value),
                    _ => track.display_unit = value,
                }
            }
            _ => {}
        }
        r.finish(&e)?;
    }
    Ok(())
}
fn tracks<R: Read>(r: &mut Reader<R>, end: u64) -> Result<(Track, HashSet<u64>), Failure> {
    let mut chosen = None;
    let mut numbers = HashSet::new();
    while let Some(e) = r.element(end, false)? {
        if e.id == 0xae {
            if numbers.len() == 256 {
                return Err(Failure::Bounds);
            }
            let mut t = Track::default();
            let mut seen = HashSet::new();
            while let Some(field) = r.element(e.end, false)? {
                match field.id {
                    0xd7 | 0x83 | 0x86 | 0x63a2 | 0xe0 | 0x56aa | 0x23e383 | 0x23314f | 0x6d80
                    | 0x537f | 0xe2 => {
                        once(&mut seen, field.id)?;
                        match field.id {
                            0xd7 => t.number = r.unsigned(field.end)?,
                            0x83 => t.kind = r.unsigned(field.end)?,
                            0x86 => t.codec = r.bytes(field.end, 64)?,
                            0x63a2 => t.config = r.bytes(field.end, CONFIG_LIMIT)?,
                            0xe0 => video(r, field.end, &mut t)?,
                            0x56aa => t.delay = r.unsigned(field.end)?,
                            0x23e383 => t.default_duration = Some(r.unsigned(field.end)?),
                            // ContentEncodings may compress/encrypt either packets or configuration.
                            0x6d80 => t.unsupported = true,
                            0xe2 => t.unsupported = true, // TrackOperation joins/combinations need another reader.
                            0x537f => {
                                let raw = r.bytes(field.end, 8)?;
                                if raw.is_empty() {
                                    return Err(Failure::Framing);
                                }
                                if raw.iter().any(|b| *b != 0) {
                                    t.unsupported = true;
                                }
                            }
                            0x23314f => {
                                let raw = r.bytes(field.end, 8)?;
                                let value = match raw.len() {
                                    4 => f32::from_be_bytes(raw.try_into().unwrap()) as f64,
                                    8 => f64::from_be_bytes(raw.try_into().unwrap()),
                                    _ => return Err(Failure::Framing),
                                };
                                if value != 1.0 {
                                    t.unsupported = true;
                                }
                            }
                            _ => unreachable!(),
                        }
                    }
                    _ => {}
                }
                r.finish(&field)?;
            }
            if t.number == 0 || t.kind == 0 || !numbers.insert(t.number) {
                return Err(Failure::Framing);
            }
            if t.kind == 1 {
                if chosen.is_some() {
                    return Err(Failure::UnsupportedContainer);
                }
                chosen = Some(t);
            }
        }
        r.finish(&e)?;
    }
    let t = chosen.ok_or(Failure::UnsupportedContainer)?;
    if t.codec != b"V_MPEGH/ISO/HEVC"
        || t.unsupported
        || t.delay != 0
        || t.default_duration == Some(0)
    {
        return Err(Failure::UnsupportedContainer);
    }
    if !(2..=16384).contains(&t.width)
        || !(2..=16384).contains(&t.height)
        || t.crop[0]
            .checked_add(t.crop[1])
            .is_none_or(|v| v >= t.width)
        || t.crop[2]
            .checked_add(t.crop[3])
            .is_none_or(|v| v >= t.height)
        || t.display.iter().flatten().any(|v| *v == 0 || *v > 65536)
        || t.display_unit > 4
    {
        return Err(Failure::Bounds);
    }
    Ok((t, numbers))
}

fn nal_type(nal: &[u8]) -> Result<u8, Failure> {
    if nal.len() < 2 || nal[0] & 0x80 != 0 || nal[1] & 7 == 0 {
        return Err(Failure::Framing);
    }
    Ok((nal[0] >> 1) & 0x3f)
}
fn configuration(data: &[u8]) -> Result<usize, Failure> {
    if data.len() < 23 || data[0] != 1 {
        return Err(Failure::UnsupportedContainer);
    }
    let width = (data[21] & 3) as usize + 1;
    let mut pos = 23;
    for _ in 0..data[22] {
        if pos + 3 > data.len() {
            return Err(Failure::Framing);
        }
        let expected = data[pos] & 0x3f;
        let count = u16::from_be_bytes([data[pos + 1], data[pos + 2]]) as usize;
        pos += 3;
        for _ in 0..count {
            if pos + 2 > data.len() {
                return Err(Failure::Framing);
            }
            let length = u16::from_be_bytes([data[pos], data[pos + 1]]) as usize;
            pos += 2;
            if length > data.len() - pos || nal_type(&data[pos..pos + length])? != expected {
                return Err(Failure::Framing);
            }
            if expected == 62 || expected == 63 {
                return Err(Failure::UnsupportedContainer);
            }
            pos += length;
        }
    }
    if pos != data.len() {
        return Err(Failure::Framing);
    }
    Ok(width)
}

struct Block {
    data: Vec<u8>,
    offset: u64,
    ticks: i128,
    invisible: bool,
    keyframe: Option<bool>,
    discardable: Option<bool>,
}
fn block<R: Read>(
    r: &mut Reader<R>,
    e: &Element,
    cluster: u64,
    track: &Track,
    numbers: &HashSet<u64>,
    blocks: &mut u64,
) -> Result<Option<Block>, Failure> {
    if *blocks == BLOCK_LIMIT {
        return Err(Failure::Bounds);
    }
    *blocks += 1;
    let (number, unknown) = r.vint(false)?;
    if unknown || !numbers.contains(&number) || e.end.saturating_sub(r.position) < 3 {
        return Err(Failure::Framing);
    }
    let mut relative = [0; 2];
    r.exact(&mut relative)?;
    let flags = r.byte()?;
    if number != track.number {
        r.finish(e)?;
        return Ok(None);
    }
    if flags & 6 != 0 {
        return Err(Failure::UnsupportedContainer);
    }
    let reserved = if e.id == 0xa3 { 0x70 } else { 0xf1 };
    if flags & reserved != 0 {
        return Err(Failure::Framing);
    }
    let offset = r.position;
    let data = r.bytes(e.end, PACKET_LIMIT)?;
    if data.is_empty() {
        return Err(Failure::Framing);
    }
    Ok(Some(Block {
        data,
        offset,
        ticks: cluster as i128 + i16::from_be_bytes(relative) as i128,
        invisible: flags & 8 != 0,
        keyframe: (e.id == 0xa3).then_some(flags & 0x80 != 0),
        discardable: (e.id == 0xa3).then_some(flags & 1 != 0),
    }))
}

#[derive(Debug)]
pub struct ContainerReceipt {
    pub packets: u64,
    pub records: u64,
    pub enhancement_nals: u64,
    pub bytes: u64,
    pub sha256: String,
    pub peak_record_bytes: usize,
}
struct Census {
    packets: u64,
    records: u64,
    enhancement: u64,
    peak: usize,
}
impl Census {
    fn emit(
        &mut self,
        b: Block,
        duration: Option<u64>,
        scale: u64,
        length_width: usize,
        output: &mut impl Write,
    ) -> Result<(), Failure> {
        if self.packets == COUNT_LIMIT {
            return Err(Failure::Bounds);
        }
        let pts = i64::try_from(b.ticks.checked_mul(scale as i128).ok_or(Failure::Bounds)?)
            .map_err(|_| Failure::Bounds)?;
        let duration = duration
            .map(|v| v.checked_mul(scale).ok_or(Failure::Bounds))
            .transpose()?;
        write_json(
            output,
            &serde_json::json!({"kind":"packet", "index":self.packets,
            "input_byte_offset":b.offset, "pts_ns":pts, "duration_ns":duration,
            "invisible":b.invisible, "keyframe":b.keyframe, "discardable":b.discardable,
            "encoded_bytes":b.data.len(), "sha256":hex(Sha256::digest(&b.data))}),
        )?;
        let mut pos = 0;
        let mut ordinal = 0;
        while pos < b.data.len() {
            if b.data.len() - pos < length_width {
                return Err(Failure::Framing);
            }
            let size = b.data[pos..pos + length_width]
                .iter()
                .fold(0usize, |v, b| (v << 8) | *b as usize);
            pos += length_width;
            if size > b.data.len() - pos {
                return Err(Failure::Framing);
            }
            let nal = &b.data[pos..pos + size];
            match nal_type(nal)? {
                62 => {
                    if nal[0] & 1 != 0 || nal[1] >> 3 != 0 {
                        return Err(Failure::UnsupportedContainer);
                    }
                    let payload = &nal[2..];
                    if payload.len() > RECORD_LIMIT || self.records == COUNT_LIMIT {
                        return Err(Failure::Bounds);
                    }
                    let metadata = parse_metadata(payload)?;
                    write_json(
                        output,
                        &serde_json::json!({"kind":"rpu", "index":self.records,
                        "packet_index":self.packets, "nal_index":ordinal, "pts_ns":pts,
                        "input_byte_offset":b.offset + pos as u64 + 2, "encoded_bytes":payload.len(),
                        "sha256":hex(Sha256::digest(payload)), "metadata":metadata}),
                    )?;
                    self.records += 1;
                    self.peak = self.peak.max(payload.len());
                }
                63 => self.enhancement = self.enhancement.checked_add(1).ok_or(Failure::Bounds)?,
                _ => {}
            }
            pos += size;
            ordinal += 1;
        }
        self.packets += 1;
        Ok(())
    }
}

struct PacketContext<'a> {
    track: &'a Track,
    numbers: &'a HashSet<u64>,
    scale: u64,
    length_width: usize,
}
fn cluster<R: Read>(
    r: &mut Reader<R>,
    end: u64,
    context: &PacketContext<'_>,
    counts: &mut Census,
    blocks: &mut u64,
    output: &mut impl Write,
) -> Result<(), Failure> {
    let PacketContext {
        track: t,
        numbers,
        scale,
        length_width,
    } = context;
    let mut timestamp = None;
    while let Some(e) = r.element(end, false)? {
        match e.id {
            0xe7 => {
                if timestamp.is_some() {
                    return Err(Failure::Framing);
                }
                timestamp = Some(r.unsigned(e.end)?);
            }
            0xa3 => {
                let time = timestamp.ok_or(Failure::Framing)?;
                if let Some(b) = block(r, &e, time, t, numbers, blocks)? {
                    counts.emit(b, None, *scale, *length_width, output)?;
                }
            }
            0xa0 => {
                let time = timestamp.ok_or(Failure::Framing)?;
                let mut packet = None;
                let mut has_block = false;
                let mut duration = None;
                let mut unsupported = false;
                while let Some(field) = r.element(e.end, false)? {
                    match field.id {
                        0xa1 => {
                            if has_block {
                                return Err(Failure::Framing);
                            }
                            has_block = true;
                            packet = block(r, &field, time, t, numbers, blocks)?;
                        }
                        0x9b => {
                            if duration.is_some() {
                                return Err(Failure::Framing);
                            }
                            duration = Some(r.unsigned(field.end)?);
                            if duration == Some(0) {
                                return Err(Failure::Framing);
                            }
                        }
                        // A selected-video payload/configuration change needs its own qualified reader.
                        0xa4 | 0x75a1 | 0x75a2 => unsupported = true,
                        0xa3 | 0xa0 | CLUSTER => return Err(Failure::Framing),
                        _ => {}
                    }
                    r.finish(&field)?;
                }
                if !has_block {
                    return Err(Failure::Framing);
                }
                if let Some(b) = packet {
                    if unsupported {
                        return Err(Failure::UnsupportedContainer);
                    }
                    counts.emit(b, duration, *scale, *length_width, output)?;
                }
            }
            0xa1 | INFO | TRACKS | CLUSTER => return Err(Failure::Framing),
            _ => {}
        }
        r.finish(&e)?;
    }
    if timestamp.is_none() {
        return Err(Failure::Framing);
    }
    Ok(())
}

pub fn audit_matroska(
    input: &mut impl Read,
    length: u64,
    output: &mut impl Write,
) -> Result<ContainerReceipt, Failure> {
    if length == 0 || length > MOVIE_LIMIT {
        return Err(Failure::Bounds);
    }
    let mut r = Reader {
        input: BufReader::with_capacity(64 * 1024, input),
        position: 0,
        length,
        hash: Sha256::new(),
        elements: 0,
    };
    let header = r.element(length, false)?.ok_or(Failure::Empty)?;
    if header.id != EBML {
        return Err(Failure::UnsupportedContainer);
    }
    let mut doc_type = false;
    let mut seen = HashSet::new();
    while let Some(e) = r.element(header.end, false)? {
        match e.id {
            0x4282 | 0x4285 | 0x42f7 | 0x42f2 | 0x42f3 => {
                once(&mut seen, e.id)?;
                if e.id == 0x4282 {
                    let bytes = r.bytes(e.end, 64)?;
                    let length = bytes.iter().rposition(|b| *b != 0).map_or(0, |i| i + 1);
                    doc_type = &bytes[..length] == b"matroska";
                } else {
                    let value = r.unsigned(e.end)?;
                    if (e.id == 0x4285 && !(1..=4).contains(&value))
                        || (e.id == 0x42f7 && value != 1)
                        || (e.id == 0x42f2 && value != 4)
                        || (e.id == 0x42f3 && value != 8)
                    {
                        return Err(Failure::UnsupportedContainer);
                    }
                }
            }
            _ => {}
        }
        r.finish(&e)?;
    }
    if !doc_type {
        return Err(Failure::UnsupportedContainer);
    }
    let segment = r.element(length, true)?.ok_or(Failure::Empty)?;
    if segment.id != SEGMENT {
        return Err(Failure::UnsupportedContainer);
    }
    let mut track = None;
    let mut numbers = HashSet::new();
    let mut scale = None;
    let mut counts = Census {
        packets: 0,
        records: 0,
        enhancement: 0,
        peak: 0,
    };
    let mut blocks = 0;
    let mut began = false;
    while let Some(e) = r.element(segment.end, false)? {
        match e.id {
            INFO => {
                if scale.is_some() || began {
                    return Err(Failure::Framing);
                }
                let mut value = 1_000_000;
                let mut seen_scale = false;
                while let Some(field) = r.element(e.end, false)? {
                    if field.id == 0x2ad7b1 {
                        if seen_scale {
                            return Err(Failure::Framing);
                        }
                        seen_scale = true;
                        value = r.unsigned(field.end)?;
                        if value == 0 {
                            return Err(Failure::Framing);
                        }
                    }
                    r.finish(&field)?;
                }
                scale = Some(value);
            }
            TRACKS => {
                if track.is_some() || began {
                    return Err(Failure::Framing);
                }
                let result = tracks(&mut r, e.end)?;
                track = Some(result.0);
                numbers = result.1;
            }
            CLUSTER => {
                let t = track.as_ref().ok_or(Failure::Framing)?;
                let scale = scale.ok_or(Failure::Framing)?;
                let length_width = configuration(&t.config)?;
                if !began {
                    write_json(
                        output,
                        &serde_json::json!({"kind":"begin", "version":2,
                        "input_type":"matroska-hevc-packets", "parser":"libdovi 3.3.2",
                        "track_number":t.number, "timestamp_scale_ns":scale,
                        "declared_pixel_width":t.width, "declared_pixel_height":t.height,
                        "declared_crop_left_right_top_bottom":t.crop,
                        "declared_display_width_height":t.display,
                        "declared_display_unit":t.display_unit,
                        "default_duration_ns":t.default_duration, "nal_length_bytes":length_width,
                        "configuration_bytes":t.config.len(), "configuration_sha256":hex(Sha256::digest(&t.config)),
                        "segment_unknown_size":segment.unknown, "packet_limit":PACKET_LIMIT,
                        "file_limit":MOVIE_LIMIT, "count_limit":COUNT_LIMIT}),
                    )?;
                    began = true;
                }
                let context = PacketContext {
                    track: t,
                    numbers: &numbers,
                    scale,
                    length_width,
                };
                cluster(&mut r, e.end, &context, &mut counts, &mut blocks, output)?;
            }
            EBML | SEGMENT | 0xa3 | 0xa1 | 0xa0 => return Err(Failure::Framing),
            _ => {}
        }
        r.finish(&e)?;
    }
    // No concatenated documents or second segment; bounded global trailing elements only.
    while let Some(e) = r.element(length, false)? {
        if ![0xec, 0xbf].contains(&e.id) {
            return Err(Failure::UnsupportedContainer);
        }
        r.finish(&e)?;
    }
    if !began || counts.packets == 0 {
        return Err(Failure::Empty);
    }
    let mut extra = [0];
    let final_read = loop {
        match r.input.read(&mut extra) {
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            result => break result.map_err(|_| Failure::InputIO)?,
        }
    };
    if final_read != 0 {
        return Err(Failure::ChangedSource);
    }
    Ok(ContainerReceipt {
        packets: counts.packets,
        records: counts.records,
        enhancement_nals: counts.enhancement,
        bytes: r.position,
        sha256: hex(r.hash.finalize()),
        peak_record_bytes: counts.peak,
    })
}

pub fn complete_matroska(output: &mut impl Write, r: &ContainerReceipt) -> Result<(), Failure> {
    write_json(
        output,
        &serde_json::json!({"kind":"complete", "version":2, "packets":r.packets,
        "records":r.records, "enhancement_nals":r.enhancement_nals,
        "input_bytes":r.bytes, "input_sha256":r.sha256,
        "peak_record_bytes":r.peak_record_bytes, "source_recheck":true}),
    )?;
    output.flush().map_err(|_| Failure::OutputIO)
}
