use std::io::{Read, Write};

use dolby_vision::rpu::dovi_rpu::DoviRpu;
use sha2::{Digest, Sha256};

pub mod matroska;

pub const RECORD_LIMIT: usize = 64 * 1024;
pub const JSON_LIMIT: usize = 2 * 1024 * 1024;
pub const FILE_LIMIT: u64 = 512 * 1024 * 1024;
pub const COUNT_LIMIT: u64 = 2_000_000;

#[derive(Debug, PartialEq, Eq)]
pub enum Failure {
    InputIO,
    OutputIO,
    Framing,
    InvalidRecord,
    Bounds,
    Empty,
    ChangedSource,
    UnsupportedContainer,
}

impl std::fmt::Display for Failure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{:?}", self)
    }
}
impl std::error::Error for Failure {}

#[derive(Debug, PartialEq, Eq)]
pub struct Receipt {
    pub records: u64,
    pub bytes: u64,
    pub sha256: String,
    pub peak_record_bytes: usize,
}

pub(crate) fn hex(bytes: impl AsRef<[u8]>) -> String {
    bytes.as_ref().iter().map(|b| format!("{b:02x}")).collect()
}

pub(crate) fn write_json(
    output: &mut impl Write,
    value: &serde_json::Value,
) -> Result<(), Failure> {
    let bytes = serde_json::to_vec(value).map_err(|_| Failure::InvalidRecord)?;
    if bytes.len() > JSON_LIMIT {
        return Err(Failure::Bounds);
    }
    output.write_all(&bytes).map_err(|_| Failure::OutputIO)?;
    output.write_all(b"\n").map_err(|_| Failure::OutputIO)
}

/// Complete records may precede an error. Only the caller's final receipt commits
/// a complete, source-stable audit. Record offsets refer to four-byte delimiters.
pub fn audit_rpu(input: &mut impl Read, output: &mut impl Write) -> Result<Receipt, Failure> {
    let mut scanner = Scanner {
        payload: Vec::new(),
        offset: 0,
        records: 0,
        peak: 0,
        output,
    };
    write_json(
        scanner.output,
        &serde_json::json!({"kind":"begin", "version":1, "input_type":"escaped-rpu-archive",
            "parser":"libdovi 3.3.2", "record_limit":RECORD_LIMIT,
            "json_limit":JSON_LIMIT, "file_limit":FILE_LIMIT, "count_limit":COUNT_LIMIT}),
    )?;
    let mut bytes = 0u64;
    let mut hash = Sha256::new();
    let mut chunk = [0u8; 32 * 1024];
    let mut delimiter = [0u8; 4];
    loop {
        let n = match input.read(&mut chunk) {
            Ok(n) => n,
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(_) => return Err(Failure::InputIO),
        };
        if n == 0 {
            break;
        }
        if n as u64 > FILE_LIMIT - bytes {
            return Err(Failure::Bounds);
        }
        hash.update(&chunk[..n]);
        for &byte in &chunk[..n] {
            if bytes < 4 {
                delimiter[bytes as usize] = byte;
                if bytes == 3 && delimiter != [0, 0, 0, 1] {
                    return Err(Failure::Framing);
                }
            } else {
                // The extra four bytes permit a delimiter after a full record.
                if scanner.payload.len() == RECORD_LIMIT + 4 {
                    return Err(Failure::Bounds);
                }
                scanner.payload.push(byte);
                if scanner.payload.ends_with(&[0, 0, 0, 1]) {
                    scanner.payload.truncate(scanner.payload.len() - 4);
                    scanner.emit()?;
                    scanner.offset = bytes - 3;
                }
            }
            bytes += 1;
        }
    }
    if bytes < 4 {
        return Err(Failure::Empty);
    }
    scanner.emit()?;
    Ok(Receipt {
        records: scanner.records,
        bytes,
        sha256: hex(hash.finalize()),
        peak_record_bytes: scanner.peak,
    })
}

struct Scanner<'a, W: Write> {
    payload: Vec<u8>,
    offset: u64,
    records: u64,
    peak: usize,
    output: &'a mut W,
}
impl<W: Write> Scanner<'_, W> {
    fn emit(&mut self) -> Result<(), Failure> {
        if self.payload.len() > RECORD_LIMIT || self.records == COUNT_LIMIT {
            return Err(Failure::Bounds);
        }
        // libdovi validates syntax and CRC. Also contain parser panics: arbitrary
        // corrupt bytes must fail the audit rather than produce completion.
        if self.payload.len() < 25 || !self.payload.starts_with(&[0x19, 8, 9]) {
            return Err(Failure::InvalidRecord);
        }
        let metadata = parse_metadata(&self.payload)?;
        write_json(
            self.output,
            &serde_json::json!({"kind":"rpu", "index":self.records,
                "input_byte_offset":self.offset, "encoded_bytes":self.payload.len(),
                "sha256":hex(Sha256::digest(&self.payload)), "metadata":metadata}),
        )?;
        self.records += 1;
        self.peak = self.peak.max(self.payload.len());
        self.payload.clear();
        Ok(())
    }
}

/// Explicit I/O errors and a hard byte bound also apply to the independent scan.
pub fn fingerprint(input: &mut impl Read) -> Result<(u64, String), Failure> {
    fingerprint_with_limit(input, FILE_LIMIT)
}

pub fn fingerprint_with_limit(input: &mut impl Read, limit: u64) -> Result<(u64, String), Failure> {
    let mut hash = Sha256::new();
    let mut bytes = 0u64;
    let mut chunk = [0u8; 32 * 1024];
    loop {
        let n = match input.read(&mut chunk) {
            Ok(n) => n,
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(_) => return Err(Failure::InputIO),
        };
        if n == 0 {
            return Ok((bytes, hex(hash.finalize())));
        }
        if n as u64 > limit - bytes {
            return Err(Failure::Bounds);
        }
        bytes += n as u64;
        hash.update(&chunk[..n]);
    }
}

pub(crate) fn parse_metadata(payload: &[u8]) -> Result<serde_json::Value, Failure> {
    if payload.len() < 25 || payload.len() > RECORD_LIMIT || !payload.starts_with(&[0x19, 8, 9]) {
        return Err(Failure::InvalidRecord);
    }
    let rpu = std::panic::catch_unwind(|| DoviRpu::parse_unspec62_nalu(payload))
        .map_err(|_| Failure::InvalidRecord)?
        .map_err(|_| Failure::InvalidRecord)?;
    serde_json::to_value(rpu).map_err(|_| Failure::InvalidRecord)
}

pub fn complete(output: &mut impl Write, receipt: &Receipt) -> Result<(), Failure> {
    write_json(
        output,
        &serde_json::json!({"kind":"complete", "version":1,
            "records":receipt.records, "input_bytes":receipt.bytes,
            "input_sha256":receipt.sha256, "peak_record_bytes":receipt.peak_record_bytes,
            "source_recheck":true}),
    )?;
    output.flush().map_err(|_| Failure::OutputIO)
}
