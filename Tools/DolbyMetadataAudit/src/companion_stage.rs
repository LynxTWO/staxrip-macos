//! Development writer into a trusted caller's precreated empty private stage.
//! No stage creation/deletion, native command, semantic importer or publication.
use crate::companion::ContentReceipt;
use crate::companion_source::{
    Cancellation, OwnedComponents, ProductionFailure, SourceBoundReceipt,
};
use crate::{Failure, companion, companion_source};
use sha2::{Digest, Sha256};
use std::{
    collections::HashSet,
    ffi::{CStr, CString},
    fs::{File, Metadata, OpenOptions},
    io::{Read, Write},
    os::{
        fd::{AsRawFd, FromRawFd},
        unix::{
            ffi::OsStrExt,
            fs::{MetadataExt, OpenOptionsExt},
        },
    },
    path::{Path, PathBuf},
    sync::Arc,
};

const NAMES: [&str; 7] = [
    "original-track-entry-payload.bin",
    "hevc-configuration.bin",
    "original-rpu.bin",
    "rpu-index.jsonl",
    "source-audit.jsonl",
    "original-container.mkv",
    "manifest.json",
];
#[derive(Clone, Copy)]
pub enum Retention {
    MetadataOnly,
    EntireContainer,
}
#[derive(Debug, PartialEq, Eq)]
pub enum StageFailure {
    Cancelled,
    UnsafeStage,
    ChangedStage,
    UnsafeComponent,
    IO,
    Integrity,
    Production(ProductionFailure),
}
impl std::fmt::Display for StageFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{self:?}")
    }
}
impl std::error::Error for StageFailure {}
impl From<ProductionFailure> for StageFailure {
    fn from(value: ProductionFailure) -> Self {
        Self::Production(value)
    }
}
pub struct StagedComponent {
    pub name: &'static str,
    pub content: ContentReceipt,
}
pub struct StagedReceipt {
    pub source_bound: SourceBoundReceipt,
    pub members: Vec<StagedComponent>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct Object {
    dev: u64,
    ino: u64,
    mode: u32,
    uid: u32,
}
impl Object {
    fn of(m: &Metadata) -> Self {
        Self {
            dev: m.dev(),
            ino: m.ino(),
            mode: m.mode(),
            uid: m.uid(),
        }
    }
}
#[derive(PartialEq, Eq)]
struct Snapshot {
    object: Object,
    bytes: u64,
    links: u64,
    modified: (i64, i64),
    changed: (i64, i64),
}
impl Snapshot {
    fn of(m: &Metadata) -> Self {
        Self {
            object: Object::of(m),
            bytes: m.len(),
            links: m.nlink(),
            modified: (m.mtime(), m.mtime_nsec()),
            changed: (m.ctime(), m.ctime_nsec()),
        }
    }
}
fn check_cancel(cancel: &Cancellation) -> Result<(), StageFailure> {
    if cancel.requested() {
        Err(StageFailure::Cancelled)
    } else {
        Ok(())
    }
}
fn cstring(value: &std::ffi::OsStr) -> Result<CString, StageFailure> {
    CString::new(value.as_bytes()).map_err(|_| StageFailure::UnsafeStage)
}
fn open_at(
    directory: &File,
    name: &CStr,
    flags: i32,
    mode: libc::mode_t,
) -> Result<File, StageFailure> {
    let fd = unsafe {
        libc::openat(
            directory.as_raw_fd(),
            name.as_ptr(),
            flags,
            mode as libc::c_uint,
        )
    };
    if fd < 0 {
        return Err(StageFailure::IO);
    }
    Ok(unsafe { File::from_raw_fd(fd) })
}
fn metadata_at(directory: &File, name: &CStr) -> Result<Metadata, StageFailure> {
    // Open the current path without following links. For directory checks the
    // caller supplies O_DIRECTORY separately; special components remain bounded.
    open_at(
        directory,
        name,
        libc::O_RDONLY | libc::O_NOFOLLOW | libc::O_NONBLOCK | libc::O_CLOEXEC,
        0,
    )?
    .metadata()
    .map_err(|_| StageFailure::IO)
}
struct Stage {
    parent: File,
    directory: File,
    parent_path: PathBuf,
    name: CString,
    parent_identity: Object,
    identity: Object,
}
impl Stage {
    fn open(path: &Path) -> Result<Self, StageFailure> {
        let name = cstring(path.file_name().ok_or(StageFailure::UnsafeStage)?)?;
        let parent_path = path
            .parent()
            .filter(|p| !p.as_os_str().is_empty())
            .unwrap_or(Path::new("."))
            .to_path_buf();
        let parent = OpenOptions::new()
            .read(true)
            .custom_flags(libc::O_DIRECTORY | libc::O_NOFOLLOW | libc::O_CLOEXEC)
            .open(&parent_path)
            .map_err(|_| StageFailure::UnsafeStage)?;
        let directory = open_at(
            &parent,
            &name,
            libc::O_RDONLY | libc::O_DIRECTORY | libc::O_NOFOLLOW | libc::O_CLOEXEC,
            0,
        )?;
        let p = parent.metadata().map_err(|_| StageFailure::IO)?;
        let d = directory.metadata().map_err(|_| StageFailure::IO)?;
        if !p.is_dir()
            || !d.is_dir()
            || d.uid() != unsafe { libc::geteuid() }
            || d.mode() & 0o7777 != 0o700
        {
            return Err(StageFailure::UnsafeStage);
        }
        let stage = Self {
            parent,
            directory,
            parent_path,
            name,
            parent_identity: Object::of(&p),
            identity: Object::of(&d),
        };
        stage.check_identity()?;
        if !stage.names()?.is_empty() {
            return Err(StageFailure::UnsafeStage);
        }
        Ok(stage)
    }
    fn check_identity(&self) -> Result<(), StageFailure> {
        let descriptor = self
            .directory
            .metadata()
            .map_err(|_| StageFailure::ChangedStage)?;
        let current =
            metadata_at(&self.parent, &self.name).map_err(|_| StageFailure::ChangedStage)?;
        let parent = self
            .parent
            .metadata()
            .map_err(|_| StageFailure::ChangedStage)?;
        let path =
            std::fs::symlink_metadata(&self.parent_path).map_err(|_| StageFailure::ChangedStage)?;
        if Object::of(&descriptor) != self.identity
            || Object::of(&current) != self.identity
            || Object::of(&parent) != self.parent_identity
            || Object::of(&path) != self.parent_identity
        {
            return Err(StageFailure::ChangedStage);
        }
        Ok(())
    }
    fn names(&self) -> Result<HashSet<Vec<u8>>, StageFailure> {
        let fd = unsafe {
            libc::openat(
                self.directory.as_raw_fd(),
                c".".as_ptr(),
                libc::O_RDONLY | libc::O_DIRECTORY | libc::O_CLOEXEC,
            )
        };
        if fd < 0 {
            return Err(StageFailure::IO);
        }
        let dir = unsafe { libc::fdopendir(fd) };
        if dir.is_null() {
            unsafe { libc::close(fd) };
            return Err(StageFailure::IO);
        }
        struct Enumeration(*mut libc::DIR);
        impl Drop for Enumeration {
            fn drop(&mut self) {
                unsafe { libc::closedir(self.0) };
            }
        }
        let owned = Enumeration(dir);
        let mut names = HashSet::new();
        loop {
            // A null readdir with errno zero means EOF, never an I/O failure.
            #[cfg(target_os = "macos")]
            unsafe {
                *libc::__error() = 0;
            }
            #[cfg(target_os = "linux")]
            unsafe {
                *libc::__errno_location() = 0;
            }
            let entry = unsafe { libc::readdir(owned.0) };
            if entry.is_null() {
                if std::io::Error::last_os_error().raw_os_error() != Some(0) {
                    return Err(StageFailure::IO);
                }
                return Ok(names);
            }
            let bytes = unsafe { CStr::from_ptr((*entry).d_name.as_ptr()) }.to_bytes();
            if bytes == b"." || bytes == b".." {
                continue;
            }
            if names.len() == 8 || !names.insert(bytes.to_vec()) {
                return Err(StageFailure::UnsafeStage);
            }
        }
    }
    fn create(&self, name: &'static str) -> Result<(File, Object), StageFailure> {
        self.check_identity()?;
        let file = open_at(
            &self.directory,
            &CString::new(name).unwrap(),
            libc::O_WRONLY
                | libc::O_CREAT
                | libc::O_EXCL
                | libc::O_NOFOLLOW
                | libc::O_NONBLOCK
                | libc::O_CLOEXEC,
            0o600,
        )?;
        let m = file.metadata().map_err(|_| StageFailure::IO)?;
        if !m.is_file()
            || m.len() != 0
            || m.nlink() != 1
            || m.uid() != self.identity.uid
            || m.mode() & 0o7777 != 0o600
        {
            return Err(StageFailure::UnsafeComponent);
        }
        Ok((file, Object::of(&m)))
    }
    fn verify(
        &self,
        members: &[StagedComponent],
        created: &[Object],
        cancel: &Cancellation,
        progress: impl Fn(u64),
    ) -> Result<(), StageFailure> {
        check_cancel(cancel)?;
        self.check_identity()?;
        let expected: HashSet<Vec<u8>> =
            members.iter().map(|m| m.name.as_bytes().to_vec()).collect();
        if self.names()? != expected {
            return Err(StageFailure::UnsafeStage);
        }
        let initial_directory =
            Snapshot::of(&self.directory.metadata().map_err(|_| StageFailure::IO)?);
        if members.len() != created.len() || expected.len() != members.len() {
            return Err(StageFailure::Integrity);
        }
        let mut files = Vec::new();
        let mut total = 0u64;
        let mut buffer = vec![0u8; 1024 * 1024];
        for (member, object) in members.iter().zip(created) {
            check_cancel(cancel)?;
            let mut file = open_at(
                &self.directory,
                &CString::new(member.name).unwrap(),
                libc::O_RDONLY | libc::O_NOFOLLOW | libc::O_NONBLOCK | libc::O_CLOEXEC,
                0,
            )?;
            let m = file.metadata().map_err(|_| StageFailure::IO)?;
            if !m.is_file()
                || Object::of(&m) != *object
                || m.nlink() != 1
                || m.len() != member.content.bytes
            {
                return Err(StageFailure::UnsafeComponent);
            }
            let initial = Snapshot::of(&m);
            let mut h = Sha256::new();
            let mut bytes = 0u64;
            while bytes < member.content.bytes {
                check_cancel(cancel)?;
                let request = (member.content.bytes - bytes).min(buffer.len() as u64) as usize;
                let count = match file.read(&mut buffer[..request]) {
                    Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
                    other => other.map_err(|_| StageFailure::IO)?,
                };
                if count == 0 {
                    return Err(StageFailure::Integrity);
                }
                h.update(&buffer[..count]);
                bytes += count as u64;
                total += count as u64;
                progress(total);
            }
            if crate::hex(h.finalize()) != member.content.sha256 {
                return Err(StageFailure::Integrity);
            }
            files.push((file, member.name, initial));
        }
        check_cancel(cancel)?;
        self.check_identity()?;
        if self.names()? != expected
            || Snapshot::of(&self.directory.metadata().map_err(|_| StageFailure::IO)?)
                != initial_directory
        {
            return Err(StageFailure::ChangedStage);
        }
        for (file, name, before) in files {
            if Snapshot::of(&file.metadata().map_err(|_| StageFailure::IO)?) != before
                || Snapshot::of(&metadata_at(&self.directory, &CString::new(name).unwrap())?)
                    != before
            {
                return Err(StageFailure::UnsafeComponent);
            }
        }
        check_cancel(cancel)
    }
}

/// Caller supplies an empty private stage it owns. Fixed exclusive names only.
/// Returned hashes bind disk contents, not independent HDR semantics or publication.
pub fn produce(
    source: &Path,
    stage: &Path,
    retention: Retention,
    cancel: Arc<Cancellation>,
) -> Result<StagedReceipt, StageFailure> {
    produce_checked(source, stage, retention, cancel, |_, _| {}, || {}, |_| {})
}
fn produce_checked(
    source: &Path,
    path: &Path,
    retention: Retention,
    cancel: Arc<Cancellation>,
    after_create: impl Fn(usize, &Path),
    after_write: impl FnOnce(),
    progress: impl Fn(u64),
) -> Result<StagedReceipt, StageFailure> {
    check_cancel(&cancel)?;
    let stage = Stage::open(path)?;
    let mut identities = Vec::new();
    let mut create = |index| {
        check_cancel(&cancel)?;
        let (file, identity) = stage.create(NAMES[index])?;
        identities.push(identity);
        after_create(index, path);
        check_cancel(&cancel)?;
        Ok::<_, StageFailure>(file)
    };
    let outputs = OwnedComponents {
        track_payload: create(0)?,
        configuration: create(1)?,
        rpu: create(2)?,
        rpu_index: create(3)?,
        source_audit: create(4)?,
        original_container: if matches!(retention, Retention::EntireContainer) {
            Some(create(5)?)
        } else {
            None
        },
    };
    stage.check_identity()?;
    let component_names = &NAMES[..identities.len()];
    if stage.names()?
        != component_names
            .iter()
            .map(|s| s.as_bytes().to_vec())
            .collect()
    {
        return Err(StageFailure::UnsafeStage);
    }
    for (name, identity) in component_names.iter().zip(&identities) {
        let m = metadata_at(&stage.directory, &CString::new(*name).unwrap())?;
        if !m.is_file() || Object::of(&m) != *identity || m.nlink() != 1 || m.len() != 0 {
            return Err(StageFailure::UnsafeComponent);
        }
    }
    let source_bound = companion_source::produce(source, outputs, cancel.clone())?;
    check_cancel(&cancel)?;
    stage.check_identity()?;
    let mut bytes = Vec::new();
    companion::manifest(&source_bound.components, &mut bytes)
        .map_err(|_| StageFailure::Production(ProductionFailure::Audit(Failure::OutputIO)))?;
    if bytes.is_empty() || bytes.len() > 1024 * 1024 {
        return Err(StageFailure::Integrity);
    }
    let (mut manifest, identity) = stage.create(NAMES[6])?;
    identities.push(identity);
    check_cancel(&cancel)?;
    manifest.write_all(&bytes).map_err(|_| StageFailure::IO)?;
    manifest.flush().map_err(|_| StageFailure::IO)?;
    drop(manifest);
    check_cancel(&cancel)?;
    let r = &source_bound.components;
    let copy = |name, r: &ContentReceipt| StagedComponent {
        name,
        content: ContentReceipt {
            bytes: r.bytes,
            sha256: r.sha256.clone(),
        },
    };
    let mut members = vec![
        copy(NAMES[0], &r.track_payload),
        copy(NAMES[1], &r.configuration),
        copy(NAMES[2], &r.rpu),
        copy(NAMES[3], &r.rpu_index),
        copy(NAMES[4], &r.source_audit),
    ];
    if let Some(original) = &r.original_container {
        members.push(copy(NAMES[5], original));
    }
    members.push(copy(
        NAMES[6],
        &ContentReceipt {
            bytes: bytes.len() as u64,
            sha256: crate::hex(Sha256::digest(&bytes)),
        },
    ));
    after_write();
    stage.verify(&members, &identities, &cancel, progress)?;
    companion_source::check_source_path(source, &source_bound.source_identity)?;
    check_cancel(&cancel)?;
    Ok(StagedReceipt {
        source_bound,
        members,
    })
}

#[cfg(test)]
#[path = "companion_stage_tests.rs"]
mod tests;
