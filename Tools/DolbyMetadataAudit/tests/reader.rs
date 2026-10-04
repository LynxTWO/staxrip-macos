use std::io::{self, Cursor, Read, Write};

use dolby_vision::rpu::generate::GenerateConfig;
use staxrip_dolby_metadata_audit::{Failure, RECORD_LIMIT, audit_rpu, complete, fingerprint};

fn fixture(profile: &str) -> Vec<u8> {
    let config: GenerateConfig = serde_json::from_value(serde_json::json!({
        "cm_version":"V29", "length":1, "profile":profile, "level6":null,
        "shots":[{"start":0,"duration":1}],
        "level5":{"active_area_left_offset":2, "active_area_right_offset":4,
            "active_area_top_offset":6, "active_area_bottom_offset":8}
    }))
    .unwrap();
    let rpu = config.generate_rpu_list().unwrap().remove(0);
    // The archive uses escaped RPU payloads, without the HEVC 7C01 NAL header.
    let hevc = rpu.write_hevc_unspec62_nalu().unwrap();
    [vec![0, 0, 0, 1], hevc[2..].to_vec()].concat()
}

fn lines(output: &[u8]) -> Vec<serde_json::Value> {
    String::from_utf8(output.to_vec())
        .unwrap()
        .lines()
        .map(|line| serde_json::from_str(line).unwrap())
        .collect()
}

struct Chunks<'a> {
    data: &'a [u8],
    size: usize,
}
impl Read for Chunks<'_> {
    fn read(&mut self, out: &mut [u8]) -> io::Result<usize> {
        let n = out.len().min(self.size).min(self.data.len());
        out[..n].copy_from_slice(&self.data[..n]);
        self.data = &self.data[n..];
        Ok(n)
    }
}

#[test]
fn every_record_full_metadata_wire_hash_and_delimiter_offset_survive_chunk_boundaries() {
    let p5 = fixture("5");
    let p81 = fixture("8.1");
    let p84 = fixture("8.4");
    let archive = [p5.clone(), p81.clone(), p81.clone(), p84].concat();
    let mut expected = Vec::new();
    let baseline = audit_rpu(&mut Cursor::new(&archive), &mut expected).unwrap();
    assert_eq!(baseline.records, 4); // An identical pair is retained, not deduplicated.
    assert_eq!(baseline.bytes, archive.len() as u64);
    assert_eq!(
        fingerprint(&mut Cursor::new(&archive)).unwrap(),
        (baseline.bytes, baseline.sha256.clone())
    );
    let records = lines(&expected);
    assert_eq!(records.len(), 5);
    assert_eq!(records[1]["metadata"]["dovi_profile"], 5);
    assert_eq!(records[2]["metadata"]["dovi_profile"], 8);
    assert_eq!(records[2]["metadata"], records[3]["metadata"]);
    assert_eq!(records[2]["sha256"], records[3]["sha256"]);
    assert_ne!(records[2]["index"], records[3]["index"]);
    assert_eq!(records[2]["input_byte_offset"], p5.len());
    assert_eq!(records[3]["input_byte_offset"], p5.len() + p81.len());
    assert!(records[2]["metadata"]["vdr_dm_data"].is_object());
    assert!(records[2]["metadata"]["rpu_data_mapping"].is_object());
    let dm = records[2]["metadata"]["vdr_dm_data"].to_string();
    assert!(
        dm.contains("active_area_top_offset\":6") && dm.contains("active_area_bottom_offset\":8")
    );
    for size in [1, 2, 3, 4, 7, 31, 32768] {
        let mut output = Vec::new();
        let actual = audit_rpu(
            &mut Chunks {
                data: &archive,
                size,
            },
            &mut output,
        )
        .unwrap();
        assert_eq!(actual, baseline);
        assert_eq!(output, expected);
    }
    assert!(!records.iter().any(|r| r["kind"] == "complete"));
    complete(&mut expected, &baseline).unwrap();
    assert_eq!(lines(&expected).last().unwrap()["kind"], "complete");
}

#[test]
fn corrupt_crc_framing_short_and_oversized_records_do_not_complete() {
    let good = fixture("8.1");
    let mut crc = good.clone();
    let index = crc.len() - 2;
    crc[index] ^= 1;
    let mut oversized = good.clone();
    oversized.resize(RECORD_LIMIT + 9, 0);
    let cases = [
        vec![],
        vec![0, 0, 1, 0x19],
        vec![0, 0, 0, 1],
        good[..good.len() - 1].to_vec(),
        crc,
        [good.clone(), vec![0, 0, 0, 1]].concat(),
        [good.clone(), vec![0, 0, 1]].concat(),
        oversized,
    ];
    for bytes in cases {
        let mut output = Vec::new();
        assert!(audit_rpu(&mut Cursor::new(bytes), &mut output).is_err());
        assert!(!lines(&output).iter().any(|r| r["kind"] == "complete"));
    }
    // Some malformed lengths could panic inside an upstream parser. The caller
    // must receive an invalid-record failure even then, never a successful EOF.
    let mut zeros = vec![0, 0, 0, 1, 0x19, 8, 9];
    zeros.resize(64, 0);
    assert_eq!(
        audit_rpu(&mut Cursor::new(zeros), &mut Vec::new()),
        Err(Failure::InvalidRecord)
    );
}

struct FailsAtEOF {
    data: Cursor<Vec<u8>>,
}
impl Read for FailsAtEOF {
    fn read(&mut self, out: &mut [u8]) -> io::Result<usize> {
        let n = self.data.read(out)?;
        if n == 0 {
            Err(io::Error::other("injected read failure"))
        } else {
            Ok(n)
        }
    }
}

#[test]
fn read_failure_after_a_valid_prefix_is_not_eof() {
    let archive = [fixture("8.1"), fixture("8.1")].concat();
    let mut output = Vec::new();
    assert_eq!(
        audit_rpu(
            &mut FailsAtEOF {
                data: Cursor::new(archive.clone())
            },
            &mut output
        ),
        Err(Failure::InputIO)
    );
    assert!(lines(&output).iter().any(|r| r["kind"] == "rpu"));
    assert!(!lines(&output).iter().any(|r| r["kind"] == "complete"));
    assert_eq!(
        fingerprint(&mut FailsAtEOF {
            data: Cursor::new(archive)
        }),
        Err(Failure::InputIO)
    );
}

struct Interrupted {
    data: Cursor<Vec<u8>>,
    once: bool,
}
impl Read for Interrupted {
    fn read(&mut self, out: &mut [u8]) -> io::Result<usize> {
        if !self.once {
            self.once = true;
            Err(io::Error::from(io::ErrorKind::Interrupted))
        } else {
            self.data.read(out)
        }
    }
}

#[test]
fn interrupted_reads_retry_but_failed_writes_and_flushes_propagate() {
    struct FailWriter;
    impl Write for FailWriter {
        fn write(&mut self, _: &[u8]) -> io::Result<usize> {
            Err(io::Error::other("injected output failure"))
        }
        fn flush(&mut self) -> io::Result<()> {
            Err(io::Error::other("injected flush failure"))
        }
    }
    struct FailFlush(Vec<u8>);
    impl Write for FailFlush {
        fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
            self.0.extend_from_slice(bytes);
            Ok(bytes.len())
        }
        fn flush(&mut self) -> io::Result<()> {
            Err(io::Error::other("injected flush failure"))
        }
    }
    let bytes = fixture("8.1");
    let result = audit_rpu(
        &mut Interrupted {
            data: Cursor::new(bytes.clone()),
            once: false,
        },
        &mut Vec::new(),
    )
    .unwrap();
    assert_eq!(result.records, 1);
    assert_eq!(
        fingerprint(&mut Interrupted {
            data: Cursor::new(bytes.clone()),
            once: false
        })
        .unwrap()
        .1,
        result.sha256
    );
    assert_eq!(
        audit_rpu(&mut Cursor::new(bytes), &mut FailWriter),
        Err(Failure::OutputIO)
    );
    assert_eq!(
        complete(&mut FailFlush(Vec::new()), &result),
        Err(Failure::OutputIO)
    );
    // Even a visible receipt cannot establish success when the child fails exit.
}

#[test]
fn cli_completes_actual_file_recheck_and_errors_never_expose_the_path() {
    use std::process::Command;
    let folder = std::env::temp_dir().join(format!("staxrip-rpu-reader-{}", std::process::id()));
    std::fs::create_dir(&folder).unwrap();
    let path = folder.join("private-generated-fixture.bin");
    let archive = [fixture("8.1"), fixture("8.1")].concat();
    std::fs::write(&path, &archive).unwrap();
    let executable = env!("CARGO_BIN_EXE_staxrip-dolby-metadata-audit");
    let result = Command::new(executable)
        .arg("rpu-json")
        .arg(&path)
        .output()
        .unwrap();
    assert!(result.status.success());
    let records = lines(&result.stdout);
    assert_eq!(records.last().unwrap()["records"], 2);
    assert_eq!(records.last().unwrap()["source_recheck"], true);
    assert_eq!(std::fs::read(&path).unwrap(), archive);
    let resources = records.iter().find(|r| r["kind"] == "resources").unwrap();
    assert!(
        resources["peak_heap_bytes"].as_u64().unwrap() < resources["heap_limit"].as_u64().unwrap()
    );
    std::fs::write(&path, b"not RPU metadata").unwrap();
    let failed = Command::new(executable)
        .arg("rpu-json")
        .arg(&path)
        .output()
        .unwrap();
    assert!(!failed.status.success());
    assert!(!String::from_utf8_lossy(&failed.stderr).contains("private-generated-fixture"));
    assert!(
        !lines(&failed.stdout)
            .iter()
            .any(|r| r["kind"] == "complete")
    );
    let directory = Command::new(executable)
        .arg("rpu-json")
        .arg(&folder)
        .output()
        .unwrap();
    assert!(!directory.status.success());
    // Reject sparse oversize files before scanning and special files without
    // waiting for a producer. Neither case can produce a complete receipt.
    let oversized = std::fs::OpenOptions::new().write(true).open(&path).unwrap();
    oversized
        .set_len(staxrip_dolby_metadata_audit::FILE_LIMIT + 1)
        .unwrap();
    let bounded = Command::new(executable)
        .arg("rpu-json")
        .arg(&path)
        .output()
        .unwrap();
    assert!(!bounded.status.success() && bounded.stdout.is_empty());
    let fifo = folder.join("generated-fifo");
    use std::os::unix::ffi::OsStrExt;
    let cpath = std::ffi::CString::new(fifo.as_os_str().as_bytes()).unwrap();
    assert_eq!(unsafe { libc::mkfifo(cpath.as_ptr(), 0o600) }, 0);
    let special = Command::new(executable)
        .arg("rpu-json")
        .arg(&fifo)
        .output()
        .unwrap();
    assert!(!special.status.success() && special.stdout.is_empty());
    std::fs::remove_file(fifo).unwrap();
    drop(oversized);
    std::fs::remove_file(path).unwrap();
    std::fs::remove_dir(folder).unwrap();
}

#[test]
fn cli_rejects_source_mutation_after_records_were_emitted() {
    use std::io::{BufRead, BufReader, Seek, SeekFrom};
    use std::process::{Command, Stdio};
    let folder = std::env::temp_dir().join(format!("staxrip-rpu-mutation-{}", std::process::id()));
    std::fs::create_dir(&folder).unwrap();
    let path = folder.join("generated.bin");
    let archive = fixture("8.1").repeat(400);
    std::fs::write(&path, &archive).unwrap();
    let mut child = Command::new(env!("CARGO_BIN_EXE_staxrip-dolby-metadata-audit"))
        .arg("rpu-json")
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
    // Receiving begin establishes that the child already captured file identity
    // and read the first chunk. Change that consumed byte while draining output.
    let mut changed = std::fs::OpenOptions::new().write(true).open(&path).unwrap();
    changed.seek(SeekFrom::Start(0)).unwrap();
    changed.write_all(&[7]).unwrap();
    changed.sync_all().unwrap();
    let mut rest = Vec::new();
    output.read_to_end(&mut rest).unwrap();
    let result = child.wait_with_output().unwrap();
    assert!(!result.status.success());
    assert!(String::from_utf8_lossy(&result.stderr).contains("ChangedSource"));
    assert!(!lines(&rest).iter().any(|r| r["kind"] == "complete"));
    drop(changed);
    std::fs::remove_file(path).unwrap();
    std::fs::remove_dir(folder).unwrap();
}

#[test]
fn cli_refuses_an_upstream_allocation_larger_than_the_heap_ceiling() {
    use bitvec_helpers::bitstream_io_writer::BitstreamIoWriter;
    use std::process::Command;
    let config: GenerateConfig = serde_json::from_value(serde_json::json!({
        "length":1, "shots":[{"start":0,"duration":1}], "level6":null
    }))
    .unwrap();
    let rpu = config.generate_rpu_list().unwrap().remove(0);
    let mut writer = BitstreamIoWriter::with_capacity(256);
    writer.write_const::<8, 0x19>().unwrap();
    rpu.header.write_header(&mut writer).unwrap();
    for _ in 0..3 {
        writer.write_ue(0).unwrap();
    }
    // Upstream allocates a u16 vector of num_pivots+2 before reading its values.
    writer.write_ue(40_000_000).unwrap();
    while !writer.byte_aligned() {
        writer.write_bit(false).unwrap();
    }
    let mut payload = writer.into_inner();
    payload.resize(128, 0);
    payload.push(0x80);
    let mut archive = vec![0, 0, 0, 1];
    let mut zeros = 0;
    for byte in payload {
        if zeros == 2 && byte <= 3 {
            archive.push(3);
            zeros = 0;
        }
        archive.push(byte);
        zeros = if byte == 0 { zeros + 1 } else { 0 };
    }
    let path = std::env::temp_dir().join(format!("staxrip-rpu-heap-{}.bin", std::process::id()));
    std::fs::OpenOptions::new()
        .create_new(true)
        .write(true)
        .open(&path)
        .unwrap()
        .write_all(&archive)
        .unwrap();
    let result = Command::new(env!("CARGO_BIN_EXE_staxrip-dolby-metadata-audit"))
        .arg("rpu-json")
        .arg(&path)
        .output()
        .unwrap();
    assert!(!result.status.success());
    assert!(
        String::from_utf8_lossy(&result.stderr)
            .contains("memory allocation of 80000004 bytes failed")
    );
    assert!(
        !lines(&result.stdout)
            .iter()
            .any(|r| r["kind"] == "complete")
    );
    std::fs::remove_file(path).unwrap();
}
