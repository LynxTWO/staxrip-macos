use dolby_vision::rpu::generate::GenerateConfig;
use sha2::{Digest, Sha256};
use staxrip_dolby_metadata_audit::{
    Failure, audit_rpu,
    matroska::{PACKET_LIMIT, audit_matroska, audit_matroska_summary, complete_matroska},
};
use std::{
    fs,
    io::{self, Cursor, Read, Write},
    path::PathBuf,
    process::Command,
    sync::atomic::{AtomicU64, Ordering},
};

fn element(id: u32, data: &[u8]) -> Vec<u8> {
    let id = id.to_be_bytes();
    let start = id.iter().position(|b| *b != 0).unwrap();
    let mut result = id[start..].to_vec();
    let size = (data.len() as u64 | (1 << 56)).to_be_bytes();
    result.extend(size);
    result.extend(data);
    result
}
fn uint(id: u32, value: u64) -> Vec<u8> {
    element(id, &value.to_be_bytes())
}
fn rpu() -> Vec<u8> {
    rpu_with_left(1)
}
fn rpu_with_left(left: u64) -> Vec<u8> {
    let config: GenerateConfig = serde_json::from_value(serde_json::json!({
        "cm_version":"V29", "length":1, "profile":"8.1", "level6":null,
        "shots":[{"start":0,"duration":1}],
        // Odd offsets are valid luma coordinates, not a chroma crop instruction.
        "level5":{"active_area_left_offset":left,"active_area_right_offset":3,
            "active_area_top_offset":5,"active_area_bottom_offset":7}
    }))
    .unwrap();
    config
        .generate_rpu_list()
        .unwrap()
        .remove(0)
        .write_hevc_unspec62_nalu()
        .unwrap()
}
fn config(width: usize) -> Vec<u8> {
    // Wire-framing fixture only; these parameter sets are not decoded pictures.
    let mut bytes = vec![0; 23];
    bytes[0] = 1;
    bytes[21] = (width - 1) as u8;
    bytes[22] = 3;
    for kind in [32, 33, 34] {
        bytes.extend([kind, 0, 1, 0, 3, kind << 1, 1, 0xaa]);
    }
    bytes
}
fn packet(nals: &[Vec<u8>], width: usize) -> Vec<u8> {
    let mut bytes = Vec::new();
    for nal in nals {
        bytes.extend(&(nal.len() as u32).to_be_bytes()[4 - width..]);
        bytes.extend(nal);
    }
    bytes
}
fn track(number: u64, kind: u64, codec: &[u8], config: &[u8], extras: &[u8]) -> Vec<u8> {
    track_geometry(number, kind, codec, config, extras, [160, 96])
}
fn track_geometry(
    number: u64,
    kind: u64,
    codec: &[u8],
    config: &[u8],
    extras: &[u8],
    raster: [u64; 2],
) -> Vec<u8> {
    element(
        0xae,
        &[
            uint(0xd7, number),
            uint(0x73c5, number),
            uint(0x83, kind),
            element(0x86, codec),
            element(0x63a2, config),
            if kind == 1 {
                element(
                    0xe0,
                    &[
                        uint(0xb0, raster[0]),
                        uint(0xba, raster[1]),
                        uint(0x54bb, 1),
                        uint(0x54b2, 3),
                        uint(0x54b0, 16),
                        uint(0x54ba, 9),
                    ]
                    .concat(),
                )
            } else {
                element(
                    0xe1,
                    &[
                        element(0xb5, &48000f64.to_be_bytes()),
                        uint(0x9f, 2),
                        uint(0x6264, 16),
                    ]
                    .concat(),
                )
            },
            extras.to_vec(),
        ]
        .concat(),
    )
}
fn simple(number: u8, relative: i16, flags: u8, packet: &[u8]) -> Vec<u8> {
    element(
        0xa3,
        &[
            vec![0x80 | number],
            relative.to_be_bytes().to_vec(),
            vec![flags],
            packet.to_vec(),
        ]
        .concat(),
    )
}
fn block_group(relative: i16, packet: &[u8], extra: &[u8]) -> Vec<u8> {
    let block = element(
        0xa1,
        &[
            vec![0x81],
            relative.to_be_bytes().to_vec(),
            vec![0],
            packet.to_vec(),
        ]
        .concat(),
    );
    element(0xa0, &[uint(0x9b, 40), block, extra.to_vec()].concat()) // duration precedes packet
}
fn movie(config: &[u8], blocks: &[u8], track_extra: &[u8], unknown_segment: bool) -> Vec<u8> {
    movie_geometry(config, blocks, track_extra, unknown_segment, [160, 96])
}
fn movie_geometry(
    config: &[u8],
    blocks: &[u8],
    track_extra: &[u8],
    unknown_segment: bool,
    raster: [u64; 2],
) -> Vec<u8> {
    let header = element(
        0x1a45dfa3,
        &[
            element(0x4282, b"matroska"),
            uint(0x4287, 4),
            uint(0x4285, 2),
        ]
        .concat(),
    );
    let body = [
        element(
            0x1549a966,
            &[
                uint(0x2ad7b1, 1_000_000),
                element(0x4d80, b"generated"),
                element(0x5741, b"generated"),
            ]
            .concat(),
        ),
        element(
            0x1654ae6b,
            &[
                track_geometry(1, 1, b"V_MPEGH/ISO/HEVC", config, track_extra, raster),
                track(2, 2, b"A_PCM/INT/LIT", &[], &[]),
            ]
            .concat(),
        ),
        element(0x1f43b675, &[uint(0xe7, 10), blocks.to_vec()].concat()),
    ]
    .concat();
    let mut segment = element(0x18538067, &body);
    if unknown_segment {
        segment[4..12].copy_from_slice(&[1, 255, 255, 255, 255, 255, 255, 255]);
    }
    [header, segment].concat()
}
fn lines(out: &[u8]) -> Vec<serde_json::Value> {
    std::str::from_utf8(out)
        .unwrap()
        .lines()
        .map(|s| serde_json::from_str(s).unwrap())
        .collect()
}
fn digest(data: &[u8]) -> String {
    format!("{:x}", Sha256::digest(data))
}

#[test]
fn packets_duplicates_signed_timestamps_full_metadata_and_declared_geometry_survive() {
    for width in [1, 2, 4] {
        let nal = rpu();
        let p = packet(
            &[
                vec![2, 1, 0xaa],
                nal.clone(),
                nal.clone(),
                vec![126, 1, 0xbb],
            ],
            width,
        );
        let input = movie(
            &config(width),
            &[
                simple(2, 0, 6, b"ignored audio lacing"),
                simple(1, -20, 0x88, &p),
                block_group(30, &p, &[]),
            ]
            .concat(),
            &[],
            true,
        );
        let mut out = Vec::new();
        let receipt =
            audit_matroska(&mut Cursor::new(&input), input.len() as u64, &mut out).unwrap();
        assert_eq!(
            (receipt.packets, receipt.records, receipt.enhancement_nals),
            (2, 4, 2)
        );
        assert_eq!(
            (receipt.bytes, receipt.sha256.clone()),
            (input.len() as u64, digest(&input))
        );
        let rows = lines(&out);
        assert_eq!(
            rows[0]["declared_crop_left_right_top_bottom"],
            serde_json::json!([0, 0, 1, 0])
        );
        assert_eq!(rows[0]["declared_pixel_width"], 160);
        assert_eq!(rows[0]["declared_display_unit"], 3);
        assert_eq!(
            rows[0]["declared_display_width_height"],
            serde_json::json!([16, 9])
        );
        assert_eq!(rows[1]["pts_ns"], -10_000_000); // Cluster 10 plus signed relative -20.
        assert_eq!(rows[1]["invisible"], true);
        assert_eq!(rows[1]["duration_ns"], serde_json::Value::Null);
        assert_eq!(rows[4]["pts_ns"], 40_000_000);
        assert_eq!(rows[4]["duration_ns"], 40_000_000);
        assert_eq!(rows[4]["keyframe"], serde_json::Value::Null);
        assert_eq!(rows[1]["sha256"], digest(&p));
        let mut archive = Vec::new();
        audit_rpu(
            &mut Cursor::new([vec![0, 0, 0, 1], nal[2..].to_vec()].concat()),
            &mut archive,
        )
        .unwrap();
        let expected = &lines(&archive)[1]["metadata"];
        for (ordinal, index) in [2, 3, 5, 6].into_iter().enumerate() {
            assert_eq!(rows[index]["index"], ordinal);
            assert_eq!(rows[index]["packet_index"], ordinal / 2);
            assert_eq!(rows[index]["nal_index"], ordinal % 2 + 1);
            assert_eq!(&rows[index]["metadata"], expected);
            assert_eq!(rows[index]["sha256"], digest(&nal[2..]));
            let offset = rows[index]["input_byte_offset"].as_u64().unwrap() as usize;
            assert_eq!(&input[offset..offset + nal.len() - 2], &nal[2..]);
        }
        assert!(!rows.iter().any(|r| r["kind"] == "complete"));
        complete_matroska(&mut out, &receipt).unwrap();
        assert_eq!(lines(&out).last().unwrap()["records"], 4);
    }
}

#[test]
fn container_packet_crc_and_unsupported_interpretations_never_complete() {
    let p = packet(&[rpu()], 4);
    let good = movie(&config(4), &simple(1, 0, 0x80, &p), &[], false);
    let mut cases: Vec<Vec<u8>> = (0..good.len())
        .map(|length| good[..length].to_vec())
        .collect();
    cases.extend([
        movie(&config(4), &simple(1, 0, 6, &p), &[], false),
        movie(&config(4), &simple(1, 0, 0x90, &p), &[], false),
        movie(&config(4), &simple(3, 0, 0x80, &p), &[], false),
        movie(
            &config(4),
            &simple(1, 0, 0x80, &p),
            &element(0x6d80, &[]),
            false,
        ),
        movie(&config(4), &simple(1, 0, 0x80, &p), &uint(0x56aa, 1), false),
        movie(
            &config(4),
            &block_group(0, &p, &element(0xa4, b"new config")),
            &[],
            false,
        ),
        movie(
            &config(4),
            &block_group(0, &p, &element(0x75a1, b"new payload")),
            &[],
            false,
        ),
        movie(
            &config(4),
            &simple(1, 0, 0x80, &[0, 0, 0, 1, 0]),
            &[],
            false,
        ),
        [good.clone(), vec![0]].concat(),
        [good.clone(), good.clone()].concat(),
    ]);
    let mut invalid_crc = rpu();
    let i = invalid_crc.len() - 4;
    invalid_crc[i] ^= 8;
    cases.push(movie(
        &config(4),
        &simple(1, 0, 0x80, &packet(&[invalid_crc], 4)),
        &[],
        false,
    ));
    let mut unknown_cluster = good.clone();
    let position = unknown_cluster
        .windows(4)
        .position(|v| v == [0x1f, 0x43, 0xb6, 0x75])
        .unwrap();
    unknown_cluster[position + 4..position + 12]
        .copy_from_slice(&[1, 255, 255, 255, 255, 255, 255, 255]);
    cases.push(unknown_cluster);
    for input in cases {
        let mut out = Vec::new();
        assert!(audit_matroska(&mut Cursor::new(&input), input.len() as u64, &mut out).is_err());
        assert!(!lines(&out).iter().any(|r| r["kind"] == "complete"));
    }
    let mut altered = config(4);
    altered[22] = 4; // claims a missing array
    let input = movie(&altered, &simple(1, 0, 0x80, &p), &[], false);
    assert!(
        audit_matroska(
            &mut Cursor::new(&input),
            input.len() as u64,
            &mut Vec::new()
        )
        .is_err()
    );
}

struct FaultReader<'a> {
    data: &'a [u8],
    fail_at: usize,
    read: usize,
    interrupt: bool,
}
impl Read for FaultReader<'_> {
    fn read(&mut self, out: &mut [u8]) -> io::Result<usize> {
        if self.interrupt {
            self.interrupt = false;
            return Err(io::ErrorKind::Interrupted.into());
        }
        if self.read == self.fail_at {
            return Err(io::ErrorKind::Other.into());
        }
        let n = out.len().min(self.data.len()).min(self.fail_at - self.read);
        out[..n].copy_from_slice(&self.data[..n]);
        self.data = &self.data[n..];
        self.read += n;
        Ok(n)
    }
}
struct BadOutput {
    flush_only: bool,
}
impl Write for BadOutput {
    fn write(&mut self, b: &[u8]) -> io::Result<usize> {
        if self.flush_only {
            Ok(b.len())
        } else {
            Err(io::ErrorKind::BrokenPipe.into())
        }
    }
    fn flush(&mut self) -> io::Result<()> {
        Err(io::ErrorKind::BrokenPipe.into())
    }
}
#[test]
fn valid_packet_prefix_read_failure_is_not_eof_and_output_errors_propagate() {
    let p = packet(&[rpu()], 4);
    let input = movie(
        &config(4),
        &[simple(1, 0, 0x80, &p), simple(1, 40, 0x80, &p)].concat(),
        &[],
        true,
    );
    let fail = input.len() - p.len() - 4;
    let mut out = Vec::new();
    let mut reader = FaultReader {
        data: &input,
        fail_at: fail,
        read: 0,
        interrupt: true,
    };
    assert_eq!(
        audit_matroska(&mut reader, input.len() as u64, &mut out).unwrap_err(),
        Failure::InputIO
    );
    assert!(lines(&out).iter().any(|v| v["kind"] == "rpu"));
    assert!(!lines(&out).iter().any(|v| v["kind"] == "complete"));
    let mut reader = FaultReader {
        data: &input,
        fail_at: usize::MAX,
        read: 0,
        interrupt: true,
    };
    let receipt = audit_matroska(&mut reader, input.len() as u64, &mut Vec::new()).unwrap();
    assert_eq!(receipt.packets, 2);
    assert_eq!(
        audit_matroska(
            &mut Cursor::new(&input),
            input.len() as u64,
            &mut BadOutput { flush_only: false }
        )
        .unwrap_err(),
        Failure::OutputIO
    );
    assert_eq!(
        complete_matroska(&mut BadOutput { flush_only: true }, &receipt).unwrap_err(),
        Failure::OutputIO
    );
}

static NEXT: AtomicU64 = AtomicU64::new(0);
struct Temp(PathBuf);
impl Temp {
    fn new() -> Self {
        let p = std::env::temp_dir().join(format!(
            "staxrip-packet-test-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&p).unwrap();
        Self(p)
    }
}
impl Drop for Temp {
    fn drop(&mut self) {
        fs::remove_dir_all(&self.0).unwrap();
    }
}

#[test]
fn real_cli_rechecks_file_bounds_and_never_exposes_names_or_payload() {
    let dir = Temp::new();
    let path = dir.0.join("generated.mkv");
    let p = packet(&[rpu()], 4);
    let input = movie(&config(4), &simple(1, 0, 0x80, &p), &[], false);
    fs::write(&path, &input).unwrap();
    let result = Command::new(env!("CARGO_BIN_EXE_staxrip-dolby-metadata-audit"))
        .args(["mkv-json"])
        .arg(&path)
        .output()
        .unwrap();
    assert!(result.status.success());
    let rows = lines(&result.stdout);
    let receipt = rows.last().unwrap();
    assert_eq!(receipt["version"], 2);
    assert_eq!(receipt["input_sha256"], digest(&input));
    assert_eq!(receipt["source_recheck"], true);
    assert_eq!(fs::read(&path).unwrap(), input);
    let mut over = vec![0; PACKET_LIMIT + 1];
    over[0] = 2;
    over[1] = 1;
    let input = movie(&config(4), &simple(1, 0, 0x80, &over), &[], false);
    fs::write(&path, &input).unwrap();
    let result = Command::new(env!("CARGO_BIN_EXE_staxrip-dolby-metadata-audit"))
        .args(["mkv-json"])
        .arg(&path)
        .output()
        .unwrap();
    assert!(!result.status.success());
    assert!(!String::from_utf8_lossy(&result.stderr).contains("generated.mkv"));
    assert!(
        !lines(&result.stdout)
            .iter()
            .any(|v| v["kind"] == "complete")
    );
}

#[test]
fn cli_rejects_a_changed_consumed_prefix_and_path_replacement() {
    use std::io::{BufRead, BufReader, Seek, SeekFrom};
    use std::process::Stdio;
    let dir = Temp::new();
    let path = dir.0.join("generated.mkv");
    let p = packet(&[rpu()], 4);
    let block = simple(1, 0, 0x80, &p);
    let input = movie(&config(4), &block.repeat(3000), &[], false);
    for replace_path in [false, true] {
        fs::write(&path, &input).unwrap();
        let mut child = Command::new(env!("CARGO_BIN_EXE_staxrip-dolby-metadata-audit"))
            .arg("mkv-json")
            .arg(&path)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap();
        let mut output = BufReader::new(child.stdout.take().unwrap());
        let mut first = String::new();
        output.read_line(&mut first).unwrap();
        assert_eq!(
            serde_json::from_str::<serde_json::Value>(&first).unwrap()["kind"],
            "begin"
        );
        // stdout backpressure holds the child after identity/initial bytes were captured.
        if replace_path {
            fs::rename(&path, dir.0.join("original.mkv")).unwrap();
            fs::write(&path, &input).unwrap();
        } else {
            let mut f = fs::OpenOptions::new().write(true).open(&path).unwrap();
            f.seek(SeekFrom::Start(0)).unwrap();
            f.write_all(&[7]).unwrap();
            f.sync_all().unwrap();
        }
        let mut rest = Vec::new();
        output.read_to_end(&mut rest).unwrap();
        let result = child.wait_with_output().unwrap();
        assert!(!result.status.success());
        assert!(String::from_utf8_lossy(&result.stderr).contains("ChangedSource"));
        assert!(!lines(&rest).iter().any(|r| r["kind"] == "complete"));
    }
}

#[test]
fn ambiguity_and_metadata_resource_limits_fail_before_completion() {
    let p = packet(&[rpu()], 4);
    let good = movie(&config(4), &simple(1, 0, 0x80, &p), &[], false);
    let mut variants = Vec::new();
    let tracks_at = good
        .windows(4)
        .position(|w| w == [0x16, 0x54, 0xae, 0x6b])
        .unwrap();
    let size_at = tracks_at + 4;
    let old_len =
        u64::from_be_bytes(good[size_at..size_at + 8].try_into().unwrap()) & ((1 << 56) - 1);
    let end = size_at + 8 + old_len as usize;
    let extra = track(3, 1, b"V_MPEGH/ISO/HEVC", &config(4), &[]);
    let mut ambiguous = [good[..end].to_vec(), extra.clone(), good[end..].to_vec()].concat();
    ambiguous[size_at..size_at + 8]
        .copy_from_slice(&((old_len + extra.len() as u64) | (1 << 56)).to_be_bytes());
    // Unknown Segment allows its larger bounded body, without changing the track counter assertion.
    let seg = ambiguous
        .windows(4)
        .position(|w| w == [0x18, 0x53, 0x80, 0x67])
        .unwrap();
    ambiguous[seg + 4..seg + 12].copy_from_slice(&[1, 255, 255, 255, 255, 255, 255, 255]);
    variants.push(ambiguous);
    variants.push(movie(
        &config(4),
        &simple(1, 0, 0x80, &p),
        &element(0x23314f, &1.5f64.to_be_bytes()),
        false,
    ));
    variants.push(movie(
        &config(4),
        &simple(1, 0, 0x80, &p),
        &element(0x537f, &[255]),
        false,
    ));
    variants.push(movie(
        &config(4),
        &simple(1, 0, 0x80, &p),
        &element(0xe2, &[]),
        false,
    ));
    let mut too_large = vec![0x19; 65537];
    too_large[..3].copy_from_slice(&[0x19, 8, 9]);
    let nal = [vec![124, 1], too_large].concat();
    variants.push(movie(
        &config(4),
        &simple(1, 0, 0x80, &packet(&[nal], 4)),
        &[],
        false,
    ));
    let mut missing_doc = good.clone();
    let at = missing_doc
        .windows(8)
        .position(|w| w == b"matroska")
        .unwrap();
    missing_doc[at] = b'x';
    variants.push(missing_doc);
    for input in variants {
        let mut output = Vec::new();
        assert!(audit_matroska(&mut Cursor::new(&input), input.len() as u64, &mut output).is_err());
        assert!(!lines(&output).iter().any(|r| r["kind"] == "complete"));
    }
}

fn probe_hex(value: &str) -> Vec<u8> {
    let mut result = Vec::new();
    for line in value.lines().filter(|line| !line.trim().is_empty()) {
        let (_, data) = line.split_once(':').unwrap();
        let column = data.trim_start().split("  ").next().unwrap();
        let bytes: String = column.chars().filter(|c| !c.is_whitespace()).collect();
        assert_eq!(bytes.len() % 2, 0);
        for i in (0..bytes.len()).step_by(2) {
            result.push(u8::from_str_radix(&bytes[i..i + 2], 16).unwrap());
        }
    }
    result
}
fn tool(name: &str, args: &[&str], source: &std::path::Path) -> serde_json::Value {
    let output = Command::new(name).args(args).arg(source).output().unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    serde_json::from_slice(&output.stdout).unwrap()
}
#[test]
fn actual_hevc_packets_and_rpu_association_match_independent_ffprobe() {
    let dir = Temp::new();
    let source = dir.0.join("generated.mp4");
    let mkv = dir.0.join("generated.mkv");
    let result = Command::new("ffmpeg")
        .args([
            "-v",
            "error",
            "-nostdin",
            "-f",
            "lavfi",
            "-i",
            "testsrc2=size=160x96:rate=25",
            "-frames:v",
            "4",
            "-an",
            "-c:v",
            "libx265",
            "-pix_fmt",
            "yuv420p10le",
            "-preset",
            "ultrafast",
            "-x265-params",
            "bframes=2:b-adapt=0:keyint=4:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc",
            "-video_track_timescale",
            "1000",
        ])
        .arg(&source)
        .output()
        .unwrap();
    assert!(
        result.status.success(),
        "{}",
        String::from_utf8_lossy(&result.stderr)
    );
    let probe = tool(
        "ffprobe",
        &[
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_packets",
            "-show_streams",
            "-show_data",
            "-of",
            "json",
        ],
        &source,
    );
    let config = probe_hex(probe["streams"][0]["extradata"].as_str().unwrap());
    assert_eq!(probe["streams"][0]["time_base"], "1/1000");
    let mut blocks = Vec::new();
    let mut expected = Vec::new();
    let mut expected_rpus = Vec::new();
    let mut reference_packets = Vec::new();
    for (index, entry) in probe["packets"].as_array().unwrap().iter().enumerate() {
        let mut bytes = probe_hex(entry["data"].as_str().unwrap());
        let rpu = rpu_with_left(index as u64 + 1);
        bytes.extend(packet(std::slice::from_ref(&rpu), 4));
        reference_packets.push((entry["pts"].as_i64().unwrap(), bytes.clone()));
        expected_rpus.push((index as u64, digest(&rpu[2..])));
        // Deliberately repeat a metadata record; never deduplicate by wire value.
        if index == 2 {
            bytes.extend(packet(std::slice::from_ref(&rpu), 4));
            expected_rpus.push((index as u64, digest(&rpu[2..])));
        }
        let pts = entry["pts"].as_i64().unwrap();
        blocks.extend(simple(
            1,
            (pts - 10) as i16,
            if index == 0 { 0x80 } else { 0 },
            &bytes,
        ));
        expected.push((pts * 1_000_000, digest(&bytes)));
    }
    assert_eq!(expected.len(), 4);
    assert!(expected.windows(2).any(|pair| pair[1].0 < pair[0].0));
    let input = movie(&config, &blocks, &[], false);
    fs::write(&mkv, &input).unwrap();
    let result = Command::new(env!("CARGO_BIN_EXE_staxrip-dolby-metadata-audit"))
        .arg("mkv-json")
        .arg(&mkv)
        .output()
        .unwrap();
    assert!(
        result.status.success(),
        "{}",
        String::from_utf8_lossy(&result.stderr)
    );
    let rows = lines(&result.stdout);
    let packets: Vec<_> = rows.iter().filter(|r| r["kind"] == "packet").collect();
    let rp: Vec<_> = rows.iter().filter(|r| r["kind"] == "rpu").collect();
    assert_eq!(rp.len(), 5);
    assert!(
        rp.windows(2)
            .any(|pair| pair[0]["metadata"] != pair[1]["metadata"])
    );
    for (row, expected) in rp.iter().zip(expected_rpus) {
        assert_eq!(row["packet_index"], expected.0);
        assert_eq!(row["sha256"], expected.1);
    }
    assert_eq!(
        rp.iter()
            .map(|r| r["packet_index"].as_u64().unwrap())
            .collect::<Vec<_>>(),
        vec![0, 1, 2, 2, 3]
    );
    let independent = tool(
        "ffprobe",
        &[
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_packets",
            "-show_entries",
            "packet=pts,size,pos,data_hash",
            "-show_data_hash",
            "sha256",
            "-of",
            "json",
        ],
        &mkv,
    );
    for (index, entry) in independent["packets"]
        .as_array()
        .unwrap()
        .iter()
        .enumerate()
    {
        assert_eq!(
            entry["pts"].as_i64().unwrap() * 1_000_000,
            expected[index].0
        );
        assert_eq!(entry["data_hash"], format!("SHA256:{}", expected[index].1));
        assert_eq!(packets[index]["pts_ns"], expected[index].0);
        assert_eq!(packets[index]["sha256"], expected[index].1);
        assert_eq!(
            packets[index]["block_input_byte_offset"],
            entry["pos"].as_str().unwrap().parse::<u64>().unwrap()
        );
        assert_eq!(
            packets[index]["encoded_bytes"],
            entry["size"].as_str().unwrap().parse::<u64>().unwrap()
        );
    }
    assert_eq!(independent["packets"].as_array().unwrap().len(), 4);
    assert_eq!(rows.last().unwrap()["records"], 5);
    let summary = Command::new(env!("CARGO_BIN_EXE_staxrip-dolby-metadata-audit"))
        .arg("mkv-summary")
        .arg(&mkv)
        .output()
        .unwrap();
    assert!(summary.status.success());
    let compact = lines(&summary.stdout);
    assert_eq!(compact.last().unwrap()["version"], 3);
    assert_eq!(
        compact.last().unwrap()["packet_sequence_sha256"],
        rows.last().unwrap()["packet_sequence_sha256"]
    );
    assert_eq!(
        compact
            .iter()
            .filter(|r| r["kind"] == "rpu-summary")
            .count(),
        5
    );

    assert_eq!(fs::read(&mkv).unwrap(), input);
    // Apply the producer to these real generated reordered HEVC packets too.
    // No new encode: exact retained container bytes bind the existing independent probe.
    {
        use staxrip_dolby_metadata_audit::companion::{Components, produce};
        let (
            mut track_payload,
            mut configuration,
            mut rpu,
            mut rpu_index,
            mut source_audit,
            mut retained,
        ) = (
            Vec::new(),
            Vec::new(),
            Vec::new(),
            Vec::new(),
            Vec::new(),
            Vec::new(),
        );
        let receipt = produce(
            &mut Cursor::new(&input),
            Components {
                track_payload: &mut track_payload,
                configuration: &mut configuration,
                rpu: &mut rpu,
                rpu_index: &mut rpu_index,
                source_audit: &mut source_audit,
                original_container: Some(&mut retained),
            },
        )
        .unwrap();
        assert_eq!(retained, input);
        assert_eq!(receipt.packets, 4);
        assert_eq!(receipt.records, 5);
        assert_eq!(receipt.original_container.as_ref().unwrap(), &receipt.input);
        let mut check = Vec::new();
        assert_eq!(
            audit_rpu(&mut Cursor::new(&rpu), &mut check)
                .unwrap()
                .records,
            5
        );
        let archived_packets: Vec<_> = lines(&source_audit)
            .into_iter()
            .filter(|r| r["kind"] == "packet")
            .collect();
        for (a, b) in archived_packets.iter().zip(&packets) {
            assert_eq!(a["sha256"], b["sha256"]);
            assert_eq!(a["pts_ns"], b["pts_ns"]);
        }
    }
    // Explicit development/test fixture export only. Never replace an existing file.
    if let Some(destination) = std::env::var_os("STAXRIP_GENERATED_DOLBY_FIXTURE") {
        let mut file = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(destination)
            .unwrap();
        file.write_all(&input).unwrap();
    }
    // Explicit development-reference fixtures; each file is exclusively created.
    if let Some(destination) = std::env::var_os("STAXRIP_GENERATED_DOLBY_REFERENCE_DIRECTORY") {
        let directory = PathBuf::from(destination);
        for case in [
            "single",
            "duplicate",
            "missing",
            "negative",
            "group",
            "wide-vint",
            "duplicate-pts",
        ] {
            let mut blocks = Vec::new();
            for (index, (pts, bytes)) in reference_packets.iter().enumerate() {
                let mut bytes = bytes.clone();
                if case == "duplicate" && index == 2 {
                    bytes.extend(packet(&[rpu_with_left(index as u64 + 1)], 4));
                }
                if case == "missing" && index == 2 {
                    // Remove just the generated final RPU, retaining the coded picture.
                    bytes.truncate(bytes.len() - rpu_with_left(index as u64 + 1).len() - 4);
                }
                let relative = if case == "duplicate-pts" {
                    -10
                } else {
                    (pts - 10 - if case == "negative" { 200 } else { 0 }) as i16
                };
                if case == "group" {
                    blocks.extend(block_group(relative, &bytes, &[]));
                } else if case == "wide-vint" {
                    blocks.extend(element(
                        0xa3,
                        &[
                            vec![0x40, 1],
                            relative.to_be_bytes().to_vec(),
                            vec![if index == 0 { 0x80 } else { 0 }],
                            bytes,
                        ]
                        .concat(),
                    ));
                } else {
                    blocks.extend(simple(
                        1,
                        relative,
                        if index == 0 { 0x80 } else { 0 },
                        &bytes,
                    ));
                }
            }
            let mut file = fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(directory.join(format!("{case}.mkv")))
                .unwrap();
            file.write_all(&movie(&config, &blocks, &[], false))
                .unwrap();
        }
        // Real SPS conformance window: dimensions need not equal coded block extent.
        let padded = dir.0.join("conformance.mp4");
        let result = Command::new("ffmpeg").args(["-v", "error", "-nostdin", "-f", "lavfi",
            "-i", "testsrc2=size=162x98:rate=25", "-frames:v", "4", "-an", "-c:v", "libx265",
            "-pix_fmt", "yuv420p10le", "-preset", "ultrafast", "-x265-params",
            "bframes=2:b-adapt=0:keyint=4:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc",
            "-video_track_timescale", "1000"]).arg(&padded).output().unwrap();
        assert!(result.status.success());
        let probe = tool(
            "ffprobe",
            &[
                "-v",
                "error",
                "-select_streams",
                "v:0",
                "-show_packets",
                "-show_streams",
                "-show_data",
                "-of",
                "json",
            ],
            &padded,
        );
        let padded_config = probe_hex(probe["streams"][0]["extradata"].as_str().unwrap());
        let mut blocks = Vec::new();
        for (index, entry) in probe["packets"].as_array().unwrap().iter().enumerate() {
            let mut bytes = probe_hex(entry["data"].as_str().unwrap());
            bytes.extend(packet(&[rpu_with_left(index as u64 + 1)], 4));
            blocks.extend(simple(
                1,
                (entry["pts"].as_i64().unwrap() - 10) as i16,
                if index == 0 { 0x80 } else { 0 },
                &bytes,
            ));
        }
        let mut file = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(directory.join("conformance.mkv"))
            .unwrap();
        file.write_all(&movie_geometry(
            &padded_config,
            &blocks,
            &[],
            false,
            [162, 98],
        ))
        .unwrap();
        // Random-access CRA starts can include encoded RASL pictures not output by a decoder.
        let random_access = dir.0.join("random-access.mp4");
        let result = Command::new("ffmpeg")
            .args([
                "-v",
                "error",
                "-nostdin",
                "-f",
                "lavfi",
                "-i",
                "testsrc2=size=160x96:rate=25",
                "-frames:v",
                "24",
                "-an",
                "-c:v",
                "libx265",
                "-pix_fmt",
                "yuv420p10le",
                "-preset",
                "ultrafast",
                "-x265-params",
                "bframes=2:b-adapt=0:keyint=12:min-keyint=12:scenecut=0:open-gop=1",
                "-video_track_timescale",
                "1000",
            ])
            .arg(&random_access)
            .output()
            .unwrap();
        assert!(result.status.success());
        let probe = tool(
            "ffprobe",
            &[
                "-v",
                "error",
                "-select_streams",
                "v:0",
                "-show_packets",
                "-show_streams",
                "-show_data",
                "-of",
                "json",
            ],
            &random_access,
        );
        let access_config = probe_hex(probe["streams"][0]["extradata"].as_str().unwrap());
        let mut all_blocks = Vec::new();
        let mut cra_blocks = Vec::new();
        let mut found_cra = false;
        for (index, entry) in probe["packets"].as_array().unwrap().iter().enumerate() {
            let mut bytes = probe_hex(entry["data"].as_str().unwrap());
            let mut position = 0;
            while position < bytes.len() {
                let size =
                    u32::from_be_bytes(bytes[position..position + 4].try_into().unwrap()) as usize;
                position += 4;
                found_cra |= bytes[position] >> 1 == 21;
                position += size;
            }
            bytes.extend(packet(&[rpu_with_left(index as u64 + 1)], 4));
            let block = simple(
                1,
                (entry["pts"].as_i64().unwrap() - 10) as i16,
                if entry["flags"].as_str().unwrap().contains('K') {
                    0x80
                } else {
                    0
                },
                &bytes,
            );
            all_blocks.extend(&block);
            if found_cra {
                cra_blocks.extend(&block);
            }
        }
        assert!(found_cra && !cra_blocks.is_empty());
        for (name, blocks) in [("whole-gop", all_blocks), ("cra-start", cra_blocks)] {
            let mut file = fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(directory.join(format!("{name}.mkv")))
                .unwrap();
            file.write_all(&movie(&access_config, &blocks, &[], false))
                .unwrap();
        }
    }
}

#[test]
fn compact_protocol_preserves_associations_and_canonical_sequence_proof() {
    let p = packet(&[vec![2, 1, 0xaa], rpu(), rpu()], 4);
    let input = movie(
        &config(4),
        &[simple(1, -20, 0x80, &p), simple(1, 30, 0, &p)].concat(),
        &[],
        false,
    );
    let mut full = Vec::new();
    let mut compact = Vec::new();
    audit_matroska(&mut Cursor::new(&input), input.len() as u64, &mut full).unwrap();
    let receipt =
        audit_matroska_summary(&mut Cursor::new(&input), input.len() as u64, &mut compact).unwrap();
    let rows = lines(&compact);
    assert_eq!(rows[0]["version"], 3);
    assert_eq!(rows[0]["input_type"], "matroska-hevc-summary");
    for (a, b) in rows.iter().zip(lines(&full)) {
        if a["kind"] == "packet" {
            assert_eq!(*a, b);
        }
        if a["kind"] == "rpu-summary" {
            for field in [
                "index",
                "packet_index",
                "nal_index",
                "pts_ns",
                "encoded_bytes",
                "sha256",
            ] {
                assert_eq!(a[field], b[field]);
            }
            assert!(a.get("metadata").is_none());
            assert_eq!(
                a["summary"]["mapping_profile"],
                b["metadata"]["dovi_profile"]
            );
            assert_eq!(
                a["summary"]["active_areas_left_right_top_bottom"],
                serde_json::json!([[1, 3, 5, 7]])
            );
            assert_eq!(a["summary"]["cmv29_present"], true);
        }
    }
    let mut expected = Sha256::new();
    for pts in [-10_000_000i64, 40_000_000] {
        expected.update(pts.to_le_bytes());
        expected.update((p.len() as i64).to_le_bytes());
        expected.update(Sha256::digest(&p));
    }
    assert_eq!(
        receipt.packet_sequence_sha256,
        format!("{:x}", expected.finalize())
    );
    complete_matroska(&mut compact, &receipt).unwrap();
    assert_eq!(lines(&compact).last().unwrap()["version"], 3);
    let mut corrupt = input.clone();
    let at = input
        .windows(rpu().len())
        .position(|window| window == rpu())
        .unwrap();
    corrupt[at + 12] ^= 1;
    assert!(
        audit_matroska_summary(
            &mut Cursor::new(&corrupt),
            corrupt.len() as u64,
            &mut Vec::new()
        )
        .is_err()
    );
}

#[test]
fn original_block_offset_does_not_guess_track_vint_width() {
    let p = packet(&[rpu()], 4);
    for prefix in [vec![0x81], vec![0x40, 0x01], vec![0x20, 0, 0x01]] {
        let block = element(
            0xa3,
            &[prefix.clone(), vec![0, 0, 0x80], p.clone()].concat(),
        );
        let input = movie(&config(4), &block, &[], false);
        let mut out = Vec::new();
        audit_matroska(&mut Cursor::new(&input), input.len() as u64, &mut out).unwrap();
        let row = &lines(&out)[1];
        let start = row["block_input_byte_offset"].as_u64().unwrap() as usize;
        let payload = row["input_byte_offset"].as_u64().unwrap() as usize;
        assert_eq!(&input[start..start + prefix.len()], prefix);
        assert_eq!(payload - start, prefix.len() + 3);
        assert_eq!(&input[payload..payload + p.len()], p);
    }
}

#[test]
fn original_companions_preserve_raw_bytes_encoded_order_and_distinct_retention() {
    use staxrip_dolby_metadata_audit::companion::{Components, manifest, produce};
    for width in [1, 2, 4] {
        for full in [false, true] {
            let a = rpu_with_left(1);
            let b = rpu_with_left(2);
            let c = rpu_with_left(3);
            let packets = [
                packet(
                    &[vec![2, 1, 0xaa], vec![126, 1, 0xbb], a.clone(), a.clone()],
                    width,
                ),
                packet(&[vec![2, 1, 0xcc], b.clone()], width),
                packet(&[vec![2, 1, 0xdd], c.clone()], width),
                packet(&[vec![2, 1, 0xee], a.clone()], width),
            ];
            let raw_config = config(width);
            // Unknown track metadata and a separate audio payload must survive the
            // complete-container mode, without pretending the reader understands them.
            let input = movie(
                &raw_config,
                &[
                    block_group(-20, &packets[0], &[]),
                    simple(2, 0, 0, b"generated other track bytes"),
                    simple(1, 30, 0x08, &packets[1]),
                    simple(1, -5, 0, &packets[2]),
                    simple(1, 30, 0, &packets[3]),
                ]
                .concat(),
                &element(0x41e4, b"generated unparsed track field"),
                true,
            );
            let mut track_payload = Vec::new();
            let (mut cfg, mut archive, mut index, mut audit, mut retained) =
                (Vec::new(), Vec::new(), Vec::new(), Vec::new(), Vec::new());
            let receipt = produce(
                &mut Cursor::new(&input),
                Components {
                    track_payload: &mut track_payload,
                    configuration: &mut cfg,
                    rpu: &mut archive,
                    rpu_index: &mut index,
                    source_audit: &mut audit,
                    original_container: full.then_some(&mut retained),
                },
            )
            .unwrap();
            assert_eq!(cfg, raw_config);
            let start = receipt.track_payload_original_offset as usize;
            assert_eq!(&input[start..start + track_payload.len()], track_payload);
            assert!(
                track_payload
                    .windows(b"generated unparsed track field".len())
                    .any(|w| w == b"generated unparsed track field")
            );
            assert_eq!(receipt.track_payload.sha256, digest(&track_payload));
            assert_eq!(receipt.track_payload.bytes, track_payload.len() as u64);
            let payloads = [&a[2..], &a[2..], &b[2..], &c[2..], &a[2..]];
            let expected: Vec<_> = payloads
                .iter()
                .flat_map(|p| [vec![0, 0, 0, 1], p.to_vec()].concat())
                .collect();
            assert_eq!(archive, expected);
            assert_eq!(receipt.packets, 4);
            assert_eq!(receipt.records, 5); // Never deduplicate or assume one per packet.
            assert_eq!(receipt.enhancement_nals, 1);
            let refs = lines(&index);
            let expected_packets = [0, 0, 1, 2, 3];
            let expected_pts = [-10_000_000, -10_000_000, 40_000_000, 5_000_000, 40_000_000];
            let mut offset = 0;
            for (i, row) in refs.iter().enumerate() {
                assert_eq!(row["index"], i);
                assert_eq!(row["packet_index"], expected_packets[i]);
                assert_eq!(row["nal_index"], [2, 3, 1, 1, 1][i]);
                assert_eq!(row["payload_bytes"], payloads[i].len());
                assert_eq!(row["pts_ns"], expected_pts[i]);
                assert_eq!(row["archive_delimiter_offset"], offset);
                let original_offset = row["original_payload_offset"].as_u64().unwrap() as usize;
                assert_eq!(
                    &input[original_offset..original_offset + payloads[i].len()],
                    payloads[i]
                );
                assert_eq!(
                    &archive[offset + 4..offset + 4 + payloads[i].len()],
                    payloads[i]
                );
                assert_eq!(row["payload_sha256"], digest(payloads[i]));
                offset += 4 + payloads[i].len();
            }
            let mut reread = Vec::new();
            assert_eq!(
                audit_rpu(&mut Cursor::new(&archive), &mut reread)
                    .unwrap()
                    .records,
                5
            );
            for (row, payload) in lines(&reread)[1..].iter().zip(payloads) {
                assert_eq!(row["sha256"], digest(payload));
            }
            let mut baseline = Vec::new();
            let r =
                audit_matroska_summary(&mut Cursor::new(&input), input.len() as u64, &mut baseline)
                    .unwrap();
            complete_matroska(&mut baseline, &r).unwrap();
            assert_eq!(audit, baseline); // Native/library protocol remains byte-identical.
            assert_eq!(receipt.input.sha256, digest(&input));
            for (r, bytes) in [
                (&receipt.configuration, &cfg),
                (&receipt.rpu, &archive),
                (&receipt.rpu_index, &index),
                (&receipt.source_audit, &audit),
            ] {
                assert_eq!(r.bytes, bytes.len() as u64);
                assert_eq!(r.sha256, digest(bytes));
            }
            if full {
                assert_eq!(retained, input);
                assert_eq!(receipt.original_container.as_ref().unwrap(), &receipt.input);
            } else {
                assert!(retained.is_empty() && receipt.original_container.is_none());
            }
            let mut manifest_bytes = Vec::new();
            manifest(&receipt, &mut manifest_bytes).unwrap();
            // Opt-in generated fixture export for the independent development verifier.
            // Exclusive writes; never accepts an owner media input or replaces files.
            if width == 4
                && let Some(root) =
                    std::env::var_os("STAXRIP_GENERATED_COMPANION_FIXTURE_DIRECTORY")
            {
                let root = PathBuf::from(root);
                if !full {
                    let mut source = fs::OpenOptions::new()
                        .write(true)
                        .create_new(true)
                        .open(root.join("generated-source.mkv"))
                        .unwrap();
                    source.write_all(&input).unwrap();
                }
                let folder = root.join(if full { "full" } else { "metadata" });
                fs::create_dir(&folder).unwrap();
                for (name, bytes) in [
                    ("original-track-entry-payload.bin", &track_payload),
                    ("hevc-configuration.bin", &cfg),
                    ("original-rpu.bin", &archive),
                    ("rpu-index.jsonl", &index),
                    ("source-audit.jsonl", &audit),
                    ("manifest.json", &manifest_bytes),
                ] {
                    let mut file = fs::OpenOptions::new()
                        .write(true)
                        .create_new(true)
                        .open(folder.join(name))
                        .unwrap();
                    file.write_all(bytes).unwrap();
                }
                if full {
                    let mut file = fs::OpenOptions::new()
                        .write(true)
                        .create_new(true)
                        .open(folder.join("original-container.mkv"))
                        .unwrap();
                    file.write_all(&retained).unwrap();
                }
            }
            let m = &lines(&manifest_bytes)[0];
            assert_eq!(
                m["components"].as_array().unwrap().len(),
                if full { 6 } else { 5 }
            );
            assert_eq!(m["source_path_identity_bound"], false);
            assert_eq!(m["decoded_frame_association"], "not-established");
            assert_eq!(m["metadata_rewritten"], false);
            assert_eq!(
                m["retention"],
                if full {
                    "entire-original-container"
                } else {
                    "rpu-and-original-track-metadata-only"
                }
            );
        }
    }
}

#[test]
fn original_companion_errors_never_return_a_complete_receipt() {
    use staxrip_dolby_metadata_audit::companion::{Components, produce};
    let good = movie(
        &config(4),
        &simple(1, 0, 0, &packet(&[rpu()], 4)),
        &[],
        false,
    );
    let mut corrupt = good.clone();
    let at = good.windows(rpu().len()).position(|w| w == rpu()).unwrap();
    corrupt[at + 12] ^= 1;
    for input in [
        Vec::new(),
        good[..good.len() - 1].to_vec(),
        corrupt,
        movie(
            &config(4),
            &simple(1, 0, 0, &packet(&[vec![2, 1, 0xaa]], 4)),
            &[],
            false,
        ),
    ] {
        let mut track_payload = Vec::new();
        let (mut cfg, mut archive, mut index, mut audit, mut full) =
            (Vec::new(), Vec::new(), Vec::new(), Vec::new(), Vec::new());
        assert!(
            produce(
                &mut Cursor::new(input),
                Components {
                    track_payload: &mut track_payload,
                    configuration: &mut cfg,
                    rpu: &mut archive,
                    rpu_index: &mut index,
                    source_audit: &mut audit,
                    original_container: Some(&mut full)
                }
            )
            .is_err()
        );
        assert!(!lines(&audit).iter().any(|r| r["kind"] == "complete"));
    }
}

#[test]
fn original_companion_writer_failures_and_flushes_refuse_each_component() {
    use staxrip_dolby_metadata_audit::companion::{Components, manifest, produce};
    struct Writer {
        bytes: Vec<u8>,
        fail_write: bool,
        fail_flush: bool,
    }
    impl Write for Writer {
        fn write(&mut self, b: &[u8]) -> io::Result<usize> {
            if self.fail_write {
                return Err(io::Error::other("generated output refusal"));
            }
            let n = b.len().min(7);
            self.bytes.extend_from_slice(&b[..n]);
            Ok(n)
        }
        fn flush(&mut self) -> io::Result<()> {
            if self.fail_flush {
                Err(io::Error::other("generated flush refusal"))
            } else {
                Ok(())
            }
        }
    }
    let input = movie(
        &config(4),
        &simple(1, 0, 0, &packet(&[rpu()], 4)),
        &[],
        false,
    );
    for component in 0..6 {
        for flush in [false, true] {
            let mut writers: Vec<_> = (0..6)
                .map(|i| Writer {
                    bytes: Vec::new(),
                    fail_write: i == component && !flush,
                    fail_flush: i == component && flush,
                })
                .collect();
            let [track_payload, cfg, rpu, index, audit, full] = writers.as_mut_slice() else {
                unreachable!()
            };
            let result = produce(
                &mut Cursor::new(&input),
                Components {
                    track_payload,
                    configuration: cfg,
                    rpu,
                    rpu_index: index,
                    source_audit: audit,
                    original_container: Some(full),
                },
            );
            assert!(
                matches!(result, Err(Failure::OutputIO)),
                "component {component}, flush {flush}"
            );
        }
    }
    let mut writers: Vec<_> = (0..6)
        .map(|_| Writer {
            bytes: Vec::new(),
            fail_write: false,
            fail_flush: false,
        })
        .collect();
    let [track_payload, cfg, rpu, index, audit, full] = writers.as_mut_slice() else {
        unreachable!()
    };
    let receipt = produce(
        &mut Cursor::new(&input),
        Components {
            track_payload,
            configuration: cfg,
            rpu,
            rpu_index: index,
            source_audit: audit,
            original_container: Some(full),
        },
    )
    .unwrap();
    assert_eq!(full.bytes, input); // Actual repeated short writes completed.
    for flush in [false, true] {
        let mut output = Writer {
            bytes: Vec::new(),
            fail_write: !flush,
            fail_flush: flush,
        };
        assert!(matches!(
            manifest(&receipt, &mut output),
            Err(Failure::OutputIO)
        ));
    }
}

#[test]
fn original_companion_source_recheck_refuses_rewritten_input() {
    use staxrip_dolby_metadata_audit::companion::{Components, produce};
    use std::io::{Seek, SeekFrom};
    struct Mutating {
        input: Cursor<Vec<u8>>,
        rewinds: u8,
        fail_read: bool,
    }
    impl Read for Mutating {
        fn read(&mut self, b: &mut [u8]) -> io::Result<usize> {
            if self.fail_read && self.input.position() > 20 {
                return Err(io::Error::other("generated input refusal"));
            }
            let n = b.len().min(17);
            self.input.read(&mut b[..n])
        }
    }
    impl Seek for Mutating {
        fn seek(&mut self, pos: SeekFrom) -> io::Result<u64> {
            if pos == SeekFrom::Start(0) {
                self.rewinds += 1;
                if self.rewinds == 2 {
                    self.input.get_mut()[20] ^= 1;
                }
            }
            self.input.seek(pos)
        }
    }
    let input = movie(
        &config(4),
        &simple(1, 0, 0, &packet(&[rpu()], 4)),
        &[],
        false,
    );
    for fail_read in [false, true] {
        let mut source = Mutating {
            input: Cursor::new(input.clone()),
            rewinds: 0,
            fail_read,
        };
        let mut track_payload = Vec::new();
        let (mut cfg, mut rpu, mut index, mut audit, mut full) =
            (Vec::new(), Vec::new(), Vec::new(), Vec::new(), Vec::new());
        let result = produce(
            &mut source,
            Components {
                track_payload: &mut track_payload,
                configuration: &mut cfg,
                rpu: &mut rpu,
                rpu_index: &mut index,
                source_audit: &mut audit,
                original_container: Some(&mut full),
            },
        );
        assert!(
            matches!(result, Err(Failure::ChangedSource)) && !fail_read
                || matches!(result, Err(Failure::InputIO)) && fail_read
        );
        assert!(!lines(&audit).iter().any(|r| r["kind"] == "complete"));
    }
}

#[test]
fn original_companion_actual_files_bind_manifest_and_refuse_replacing_outputs() {
    use staxrip_dolby_metadata_audit::companion::{Components, manifest, produce};
    use std::os::unix::fs::MetadataExt;
    let folder = Temp::new();
    let source_path = folder.0.join("generated-source.mkv");
    let input = movie(
        &config(4),
        &simple(
            1,
            0,
            0,
            &packet(&[vec![2, 1, 0xaa], vec![126, 1, 0xbb], rpu()], 4),
        ),
        &element(0x41e4, b"supplementary generated configuration"),
        false,
    );
    fs::write(&source_path, &input).unwrap();
    let before = fs::metadata(&source_path).unwrap();
    let names = [
        "original-track-entry-payload.bin",
        "hevc-configuration.bin",
        "original-rpu.bin",
        "rpu-index.jsonl",
        "source-audit.jsonl",
        "original-container.mkv",
    ];
    let mut writers: Vec<_> = names
        .iter()
        .map(|n| {
            fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(folder.0.join(n))
                .unwrap()
        })
        .collect();
    let [
        track_payload,
        configuration,
        rpu,
        rpu_index,
        source_audit,
        original_container,
    ] = writers.as_mut_slice()
    else {
        unreachable!()
    };
    let mut source = fs::OpenOptions::new()
        .read(true)
        .open(&source_path)
        .unwrap();
    let receipt = produce(
        &mut source,
        Components {
            track_payload,
            configuration,
            rpu,
            rpu_index,
            source_audit,
            original_container: Some(original_container),
        },
    )
    .unwrap();
    drop(writers);
    let mut manifest_file = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(folder.0.join("manifest.json"))
        .unwrap();
    manifest(&receipt, &mut manifest_file).unwrap();
    drop(manifest_file);
    let m = lines(&fs::read(folder.0.join("manifest.json")).unwrap()).remove(0);
    for component in m["components"].as_array().unwrap() {
        let path = folder.0.join(component["name"].as_str().unwrap());
        let bytes = fs::read(&path).unwrap();
        assert_eq!(component["bytes"], bytes.len());
        assert_eq!(component["sha256"], digest(&bytes));
        assert!(
            fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&path)
                .is_err()
        );
        assert_eq!(fs::read(&path).unwrap(), bytes);
    }
    let reread = fs::read(folder.0.join("original-container.mkv")).unwrap();
    assert_eq!(reread, input);
    assert_eq!(fs::read(&source_path).unwrap(), input);
    let after = fs::metadata(&source_path).unwrap();
    assert_eq!(
        (
            before.dev(),
            before.ino(),
            before.len(),
            before.mtime(),
            before.mtime_nsec(),
            before.ctime(),
            before.ctime_nsec()
        ),
        (
            after.dev(),
            after.ino(),
            after.len(),
            after.mtime(),
            after.mtime_nsec(),
            after.ctime(),
            after.ctime_nsec()
        )
    );
}

#[test]
fn original_track_capture_bound_refuses_without_changing_read_only_audit() {
    use staxrip_dolby_metadata_audit::companion::{Components, produce};
    let input = movie(
        &config(4),
        &simple(1, 0, 0, &packet(&[rpu()], 4)),
        &element(0x41e4, &vec![42; 1024 * 1024]),
        false,
    );
    let baseline = audit_matroska_summary(
        &mut Cursor::new(&input),
        input.len() as u64,
        &mut Vec::new(),
    )
    .unwrap();
    assert_eq!(baseline.records, 1);
    let (mut track_payload, mut configuration, mut rpu, mut rpu_index, mut source_audit) =
        (Vec::new(), Vec::new(), Vec::new(), Vec::new(), Vec::new());
    let result = produce(
        &mut Cursor::new(&input),
        Components {
            track_payload: &mut track_payload,
            configuration: &mut configuration,
            rpu: &mut rpu,
            rpu_index: &mut rpu_index,
            source_audit: &mut source_audit,
            original_container: None,
        },
    );
    assert!(matches!(result, Err(Failure::Bounds)));
    assert!(source_audit.is_empty());
}
