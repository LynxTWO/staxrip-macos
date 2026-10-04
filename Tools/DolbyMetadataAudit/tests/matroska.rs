use dolby_vision::rpu::generate::GenerateConfig;
use sha2::{Digest, Sha256};
use staxrip_dolby_metadata_audit::{
    Failure, audit_rpu,
    matroska::{PACKET_LIMIT, audit_matroska, complete_matroska},
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
                        uint(0xb0, 160),
                        uint(0xba, 96),
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
                track(1, 1, b"V_MPEGH/ISO/HEVC", config, track_extra),
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
    for (index, entry) in probe["packets"].as_array().unwrap().iter().enumerate() {
        let mut bytes = probe_hex(entry["data"].as_str().unwrap());
        let rpu = rpu_with_left(index as u64 + 1);
        bytes.extend(packet(std::slice::from_ref(&rpu), 4));
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
            "packet=pts,size,data_hash",
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
            packets[index]["encoded_bytes"],
            entry["size"].as_str().unwrap().parse::<u64>().unwrap()
        );
    }
    assert_eq!(independent["packets"].as_array().unwrap().len(), 4);
    assert_eq!(rows.last().unwrap()["records"], 5);
    assert_eq!(fs::read(&mkv).unwrap(), input);
}
