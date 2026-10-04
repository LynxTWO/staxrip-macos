//! Source-bound development producer. No native writer command or publication.
//! The caller creates exclusive staged files and validates their paths/semantics
//! after settlement. Boundary checks do not create an immutable source snapshot.
use crate::Failure;
use crate::companion::{self, CompanionReceipt, Components};
use crate::matroska::MOVIE_LIMIT;
use std::{
    collections::HashSet,
    fs::{File, Metadata, OpenOptions},
    io::{self, Read, Seek, SeekFrom, Write},
    os::fd::AsRawFd,
    os::unix::fs::{MetadataExt, OpenOptionsExt},
    path::Path,
    sync::atomic::{AtomicBool, Ordering},
};

/// One-way request. This does not interrupt blocked filesystem I/O or parser CPU.
#[derive(Default)]
pub struct Cancellation(AtomicBool);
impl Cancellation {
    pub fn request(&self) {
        self.0.store(true, Ordering::Release);
    }
    pub fn requested(&self) -> bool {
        self.0.load(Ordering::Acquire)
    }
    fn check(&self) -> Result<(), ProductionFailure> {
        if self.requested() {
            Err(ProductionFailure::Cancelled)
        } else {
            Ok(())
        }
    }
    fn io_check(&self) -> io::Result<()> {
        self.check().map_err(io::Error::other)
    }
}

/// Consumed handles, not caller-borrowed buffered writers. Dropped on every return.
/// Caller must have created these files exclusively inside its own staging area.
pub struct OwnedComponents {
    pub track_payload: File,
    pub configuration: File,
    pub rpu: File,
    pub rpu_index: File,
    pub source_audit: File,
    pub original_container: Option<File>,
}

#[derive(Debug, PartialEq, Eq)]
pub enum ProductionFailure {
    Cancelled,
    UnsafeSource,
    UnsafeOutput,
    /// Actual component write/flush ENOSPC, never inferred from capacity.
    OutputFull,
    ChangedSource,
    Audit(Failure),
}
impl std::fmt::Display for ProductionFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{self:?}")
    }
}
impl std::error::Error for ProductionFailure {}

/// In-memory equality token only. No source path or persisted import identity.
#[derive(Debug, PartialEq, Eq)]
pub struct SourceIdentity {
    device: u64,
    inode: u64,
    mode: u32,
    links: u64,
    bytes: u64,
    modified: (i64, i64),
    changed: (i64, i64),
}
impl SourceIdentity {
    /// Development process correlation only; not persisted archive provenance.
    pub fn file_id(&self) -> (u64, u64) {
        (self.device, self.inode)
    }
    fn from_metadata(m: &Metadata) -> Self {
        Self {
            device: m.dev(),
            inode: m.ino(),
            mode: m.mode(),
            links: m.nlink(),
            bytes: m.len(),
            modified: (m.mtime(), m.mtime_nsec()),
            changed: (m.ctime(), m.ctime_nsec()),
        }
    }
}
pub struct SourceBoundReceipt {
    pub components: CompanionReceipt,
    pub source_identity: SourceIdentity,
}

struct Checked<T> {
    inner: T,
    cancel: std::sync::Arc<Cancellation>,
    output_full: std::sync::Arc<AtomicBool>,
}
impl<T: Read> Read for Checked<T> {
    fn read(&mut self, bytes: &mut [u8]) -> io::Result<usize> {
        self.cancel.io_check()?;
        let count = self.inner.read(bytes)?;
        self.cancel.io_check()?;
        Ok(count)
    }
}
impl<T: Seek> Seek for Checked<T> {
    fn seek(&mut self, position: SeekFrom) -> io::Result<u64> {
        self.cancel.io_check()?;
        let offset = self.inner.seek(position)?;
        self.cancel.io_check()?;
        Ok(offset)
    }
}
impl<T: Write> Write for Checked<T> {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        self.cancel.io_check()?;
        let result = self.inner.write(bytes);
        if let Err(error) = &result
            && error.raw_os_error() == Some(libc::ENOSPC)
        {
            self.output_full.store(true, Ordering::Release);
        }
        let count = result?;
        self.cancel.io_check()?;
        Ok(count)
    }
    fn flush(&mut self) -> io::Result<()> {
        self.cancel.io_check()?;
        let result = self.inner.flush();
        if let Err(error) = &result
            && error.raw_os_error() == Some(libc::ENOSPC)
        {
            self.output_full.store(true, Ordering::Release);
        }
        result?;
        self.cancel.io_check()
    }
}

fn source_metadata(input: &File) -> Result<Metadata, ProductionFailure> {
    input
        .metadata()
        .map_err(|_| ProductionFailure::Audit(Failure::InputIO))
}
pub(crate) fn check_source_path(
    path: &Path,
    before: &SourceIdentity,
) -> Result<(), ProductionFailure> {
    let path_metadata =
        std::fs::symlink_metadata(path).map_err(|_| ProductionFailure::ChangedSource)?;
    if !path_metadata.is_file() || SourceIdentity::from_metadata(&path_metadata) != *before {
        return Err(ProductionFailure::ChangedSource);
    }
    Ok(())
}

fn check_outputs(
    outputs: &OwnedComponents,
    source: &SourceIdentity,
) -> Result<(), ProductionFailure> {
    let files = [
        Some(&outputs.track_payload),
        Some(&outputs.configuration),
        Some(&outputs.rpu),
        Some(&outputs.rpu_index),
        Some(&outputs.source_audit),
        outputs.original_container.as_ref(),
    ];
    let mut identities = HashSet::new();
    for file in files.into_iter().flatten() {
        let m = file
            .metadata()
            .map_err(|_| ProductionFailure::UnsafeOutput)?;
        // File is supplied by the trusted caller, never by a manifest. Reject
        // descriptor aliases before any write, including cloned output handles.
        let flags = unsafe { libc::fcntl(file.as_raw_fd(), libc::F_GETFL) };
        let position = unsafe { libc::lseek(file.as_raw_fd(), 0, libc::SEEK_CUR) };
        if !m.is_file()
            || m.len() != 0
            || m.nlink() != 1
            || flags < 0
            || flags & libc::O_ACCMODE != libc::O_WRONLY
            || flags & libc::O_APPEND != 0
            || position != 0
            || (m.dev(), m.ino()) == (source.device, source.inode)
            || !identities.insert((m.dev(), m.ino()))
        {
            return Err(ProductionFailure::UnsafeOutput);
        }
    }
    Ok(())
}

/// All owned source/component File handles close before this synchronous call
/// returns. Partial files can remain on failure; only the caller owns cleanup.
/// No receipt proves output pathname binding, semantic reread or publication.
pub fn produce(
    source: &Path,
    outputs: OwnedComponents,
    cancellation: std::sync::Arc<Cancellation>,
) -> Result<SourceBoundReceipt, ProductionFailure> {
    produce_then_check(source, outputs, cancellation, || {})
}

/// Match the controlling caller's source device/inode before any component write.
pub(crate) fn produce_expected(
    source: &Path,
    outputs: OwnedComponents,
    cancellation: std::sync::Arc<Cancellation>,
    expected: (u64, u64),
) -> Result<SourceBoundReceipt, ProductionFailure> {
    produce_expected_then_check(source, outputs, cancellation, Some(expected), || {})
}

// Internal fault-injection boundary used by generated tests. Ordinary callers
// cannot select a callback, skip source checks or force a receipt.
fn produce_then_check(
    source: &Path,
    outputs: OwnedComponents,
    cancellation: std::sync::Arc<Cancellation>,
    after_components: impl FnOnce(),
) -> Result<SourceBoundReceipt, ProductionFailure> {
    produce_expected_then_check(source, outputs, cancellation, None, after_components)
}
fn produce_expected_then_check(
    source: &Path,
    outputs: OwnedComponents,
    cancellation: std::sync::Arc<Cancellation>,
    expected: Option<(u64, u64)>,
    after_components: impl FnOnce(),
) -> Result<SourceBoundReceipt, ProductionFailure> {
    cancellation.check()?;
    let input = OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NOFOLLOW | libc::O_NONBLOCK | libc::O_CLOEXEC | libc::O_NOCTTY)
        .open(source)
        .map_err(|_| ProductionFailure::UnsafeSource)?;
    let metadata = source_metadata(&input)?;
    if !metadata.is_file() || metadata.len() == 0 || metadata.len() > MOVIE_LIMIT {
        return Err(ProductionFailure::UnsafeSource);
    }
    let before = SourceIdentity::from_metadata(&metadata);
    if expected.is_some_and(|id| id != before.file_id()) {
        return Err(ProductionFailure::ChangedSource);
    }
    check_source_path(source, &before)?;
    check_outputs(&outputs, &before)?;
    cancellation.check()?;
    let output_full = std::sync::Arc::new(AtomicBool::new(false));
    let guarded = |inner| Checked {
        inner,
        cancel: cancellation.clone(),
        output_full: output_full.clone(),
    };
    let mut input = guarded(input);
    let mut track = guarded(outputs.track_payload);
    let mut config = guarded(outputs.configuration);
    let mut rpu = guarded(outputs.rpu);
    let mut index = guarded(outputs.rpu_index);
    let mut audit = guarded(outputs.source_audit);
    let mut original = outputs.original_container.map(guarded);
    let components = companion::produce(
        &mut input,
        Components {
            track_payload: &mut track,
            configuration: &mut config,
            rpu: &mut rpu,
            rpu_index: &mut index,
            source_audit: &mut audit,
            original_container: original.as_mut(),
        },
    )
    .map_err(|failure| {
        if cancellation.requested() {
            ProductionFailure::Cancelled
        } else if output_full.load(Ordering::Acquire) {
            ProductionFailure::OutputFull
        } else {
            ProductionFailure::Audit(failure)
        }
    })?;
    after_components();
    cancellation.check()?;
    if SourceIdentity::from_metadata(&source_metadata(&input.inner)?) != before {
        return Err(ProductionFailure::ChangedSource);
    }
    check_source_path(source, &before)?;
    cancellation.check()?;
    Ok(SourceBoundReceipt {
        components,
        source_identity: before,
    })
}

#[cfg(test)]
#[path = "companion_source_tests.rs"]
pub(crate) mod tests;
