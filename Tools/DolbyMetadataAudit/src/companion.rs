//! Generated-development component producer. No stable archive/import format,
//! pathname identity admission, native writer command or publication operation.
use crate::matroska::{self, MOVIE_LIMIT, OriginalObserver, OriginalRpu};
use crate::{FILE_LIMIT, Failure, fingerprint_with_limit, hex, write_json};
use sha2::{Digest, Sha256};
use std::io::{self, Read, Seek, SeekFrom, Write};

pub struct Components<'a, W: Write> {
    pub track_payload: &'a mut W,
    pub configuration: &'a mut W,
    pub rpu: &'a mut W,
    pub rpu_index: &'a mut W,
    pub source_audit: &'a mut W,
    /// Some retains the entire input container, not just the selected video track.
    pub original_container: Option<&'a mut W>,
}
#[derive(Debug, PartialEq, Eq)]
pub struct ContentReceipt {
    pub bytes: u64,
    pub sha256: String,
}
pub struct CompanionReceipt {
    pub track_payload: ContentReceipt,
    pub track_payload_original_offset: u64,
    pub configuration: ContentReceipt,
    pub rpu: ContentReceipt,
    pub rpu_index: ContentReceipt,
    pub source_audit: ContentReceipt,
    pub original_container: Option<ContentReceipt>,
    pub input: ContentReceipt,
    pub packets: u64,
    pub records: u64,
    pub enhancement_nals: u64,
}

struct HashedWriter<'a, W: Write> {
    output: &'a mut W,
    hash: Sha256,
    bytes: u64,
    limit: u64,
}
impl<'a, W: Write> HashedWriter<'a, W> {
    fn new(output: &'a mut W, limit: u64) -> Self {
        Self {
            output,
            hash: Sha256::new(),
            bytes: 0,
            limit,
        }
    }
    fn finish(mut self) -> Result<ContentReceipt, Failure> {
        self.flush().map_err(|_| Failure::OutputIO)?;
        Ok(ContentReceipt {
            bytes: self.bytes,
            sha256: hex(self.hash.finalize()),
        })
    }
}
impl<W: Write> Write for HashedWriter<'_, W> {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        if bytes.len() as u64 > self.limit - self.bytes {
            return Err(io::Error::other("Component byte bound exceeded"));
        }
        let count = self.output.write(bytes)?;
        self.hash.update(&bytes[..count]);
        self.bytes += count as u64;
        Ok(count)
    }
    fn flush(&mut self) -> io::Result<()> {
        self.output.flush()
    }
}
struct Originals<'a, W: Write> {
    track: HashedWriter<'a, W>,
    track_offset: u64,
    configuration: HashedWriter<'a, W>,
    rpu: HashedWriter<'a, W>,
    index: HashedWriter<'a, W>,
}
impl<W: Write> OriginalObserver for Originals<'_, W> {
    fn retain_track_payload(&self) -> bool {
        true
    }
    fn track_payload(&mut self, bytes: &[u8], original_offset: u64) -> Result<(), Failure> {
        self.track_offset = original_offset;
        self.track.write_all(bytes).map_err(|_| Failure::OutputIO)
    }
    fn configuration(&mut self, bytes: &[u8]) -> Result<(), Failure> {
        self.configuration
            .write_all(bytes)
            .map_err(|_| Failure::OutputIO)
    }
    fn rpu(&mut self, record: OriginalRpu<'_>) -> Result<(), Failure> {
        let offset = self.rpu.bytes;
        // Existing bounded archive reader accepts the escaped payload without the
        // two-byte HEVC NAL header. Original escape bytes are never regenerated.
        self.rpu
            .write_all(&[0, 0, 0, 1])
            .map_err(|_| Failure::OutputIO)?;
        self.rpu
            .write_all(record.payload)
            .map_err(|_| Failure::OutputIO)?;
        write_json(
            &mut self.index,
            &serde_json::json!({
                "kind":"original-rpu-reference", "index":record.index,
                "packet_index":record.packet_index, "nal_index":record.nal_index,
                "pts_ns":record.pts_ns, "original_payload_offset":record.input_byte_offset,
                "archive_delimiter_offset":offset, "payload_bytes":record.payload.len(),
                "payload_sha256":hex(Sha256::digest(record.payload))
            }),
        )
    }
}
struct Tee<'a, R: Read, W: Write> {
    input: &'a mut R,
    retained: Option<HashedWriter<'a, W>>,
    output_failed: bool,
}
impl<R: Read, W: Write> Read for Tee<'_, R, W> {
    fn read(&mut self, bytes: &mut [u8]) -> io::Result<usize> {
        let count = self.input.read(bytes)?;
        if let Some(output) = &mut self.retained
            && let Err(error) = output.write_all(&bytes[..count])
        {
            self.output_failed = true;
            return Err(error);
        }
        Ok(count)
    }
}

/// Partial components can precede any error. Only a successful receipt plus caller
/// source-identity and staged-file verification can qualify later publication.
pub fn produce(
    input: &mut (impl Read + Seek),
    outputs: Components<'_, impl Write>,
) -> Result<CompanionReceipt, Failure> {
    let length = input.seek(SeekFrom::End(0)).map_err(|_| Failure::InputIO)?;
    if length == 0 || length > MOVIE_LIMIT {
        return Err(Failure::Bounds);
    }
    input.rewind().map_err(|_| Failure::InputIO)?;
    let mut original = Originals {
        track: HashedWriter::new(outputs.track_payload, 1024 * 1024),
        track_offset: 0,
        configuration: HashedWriter::new(outputs.configuration, 1024 * 1024),
        rpu: HashedWriter::new(outputs.rpu, FILE_LIMIT),
        index: HashedWriter::new(outputs.rpu_index, FILE_LIMIT),
    };
    let mut audit = HashedWriter::new(outputs.source_audit, 1024 * 1024 * 1024);
    let mut tee = Tee {
        input,
        retained: outputs
            .original_container
            .map(|w| HashedWriter::new(w, MOVIE_LIMIT)),
        output_failed: false,
    };
    let source = matroska::audit_with_originals(&mut tee, length, &mut audit, &mut original)
        .map_err(|error| {
            if tee.output_failed {
                Failure::OutputIO
            } else {
                error
            }
        })?;
    if source.records == 0 {
        return Err(Failure::Empty);
    }
    let retained = tee.retained.map(HashedWriter::finish).transpose()?;
    input.rewind().map_err(|_| Failure::InputIO)?;
    let rechecked = fingerprint_with_limit(input, MOVIE_LIMIT)?;
    if rechecked != (source.bytes, source.sha256.clone()) || source.bytes != length {
        return Err(Failure::ChangedSource);
    }
    if retained
        .as_ref()
        .is_some_and(|r| r.bytes != source.bytes || r.sha256 != source.sha256)
    {
        return Err(Failure::ChangedSource);
    }
    let configuration = original.configuration.finish()?;
    let track_payload = original.track.finish()?;
    let rpu = original.rpu.finish()?;
    let rpu_index = original.index.finish()?;
    // Content recheck only. Generic seekable input cannot establish pathname or
    // filesystem descriptor identity; the development manifest says so explicitly.
    matroska::complete_matroska(&mut audit, &source)?;
    Ok(CompanionReceipt {
        track_payload,
        track_payload_original_offset: original.track_offset,
        configuration,
        rpu,
        rpu_index,
        source_audit: audit.finish()?,
        original_container: retained,
        input: ContentReceipt {
            bytes: source.bytes,
            sha256: source.sha256,
        },
        packets: source.packets,
        records: source.records,
        enhancement_nals: source.enhancement_nals,
    })
}

/// Prototype manifest remains outside the native saved-session/import contract.
/// The enclosing manifest itself must also be verified as a staged component.
pub fn manifest(receipt: &CompanionReceipt, output: &mut impl Write) -> Result<(), Failure> {
    let component = |name, r: &ContentReceipt| serde_json::json!({"name":name,"bytes":r.bytes,"sha256":r.sha256});
    let mut members = vec![
        component("original-track-entry-payload.bin", &receipt.track_payload),
        component("hevc-configuration.bin", &receipt.configuration),
        component("original-rpu.bin", &receipt.rpu),
        component("rpu-index.jsonl", &receipt.rpu_index),
        component("source-audit.jsonl", &receipt.source_audit),
    ];
    if let Some(r) = &receipt.original_container {
        members.push(component("original-container.mkv", r));
    }
    write_json(
        output,
        &serde_json::json!({
            "kind":"development-original-companion", "version":0,
            "retention":if receipt.original_container.is_some() {"entire-original-container"} else {"rpu-and-original-track-metadata-only"},
            "source_bytes":receipt.input.bytes,"source_sha256":receipt.input.sha256,
            "track_payload_original_offset":receipt.track_payload_original_offset,
            "packets":receipt.packets,"records":receipt.records,"enhancement_nals":receipt.enhancement_nals,
            "association":"original-encoded-packet-order", "decoded_frame_association":"not-established",
            "source_content_recheck":true,"source_path_identity_bound":false,
            "metadata_rewritten":false,"components":members
        }),
    )?;
    output.flush().map_err(|_| Failure::OutputIO)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn component_byte_limit_and_partial_writes_are_real() {
        struct ShortWriter(Vec<u8>);
        impl Write for ShortWriter {
            fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
                let count = bytes.len().min(2);
                self.0.extend_from_slice(&bytes[..count]);
                Ok(count)
            }
            fn flush(&mut self) -> io::Result<()> {
                Ok(())
            }
        }
        let mut bytes = ShortWriter(Vec::new());
        let mut bounded = HashedWriter::new(&mut bytes, 3);
        bounded.write_all(&[1, 2, 3]).unwrap();
        assert!(bounded.write_all(&[4]).is_err());
        let receipt = bounded.finish().unwrap();
        assert_eq!(receipt.bytes, 3);
        assert_eq!(bytes.0, [1, 2, 3]);
        assert_eq!(receipt.sha256, hex(Sha256::digest(&bytes.0)));
    }
}
