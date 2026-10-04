use super::*;
use crate::companion::manifest;
use dolby_vision::rpu::generate::GenerateConfig;
use std::{
    io::Cursor,
    os::unix::fs::symlink,
    path::PathBuf,
    sync::{Arc, atomic::AtomicU64, mpsc},
    time::Duration,
};

static NEXT: AtomicU64 = AtomicU64::new(0);
struct Temp(PathBuf);
impl Temp {
    fn new() -> Self {
        let path = std::env::temp_dir().join(format!(
            "staxrip-source-bound-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        std::fs::create_dir(&path).unwrap();
        Self(path)
    }
}
impl Drop for Temp {
    fn drop(&mut self) {
        std::fs::remove_dir_all(&self.0).unwrap();
    }
}
const NAMES: [&str; 6] = [
    "original-track-entry-payload.bin",
    "hevc-configuration.bin",
    "original-rpu.bin",
    "rpu-index.jsonl",
    "source-audit.jsonl",
    "original-container.mkv",
];
fn owned(path: &Path, full: bool) -> OwnedComponents {
    let create = |index| {
        OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(path.join(NAMES[index]))
            .unwrap()
    };
    OwnedComponents {
        track_payload: create(0),
        configuration: create(1),
        rpu: create(2),
        rpu_index: create(3),
        source_audit: create(4),
        original_container: full.then(|| create(5)),
    }
}
fn descriptors(outputs: &OwnedComponents) -> Vec<(i32, u64, u64)> {
    [
        Some(&outputs.track_payload),
        Some(&outputs.configuration),
        Some(&outputs.rpu),
        Some(&outputs.rpu_index),
        Some(&outputs.source_audit),
        outputs.original_container.as_ref(),
    ]
    .into_iter()
    .flatten()
    .map(|file| {
        let m = file.metadata().unwrap();
        (file.as_raw_fd(), m.dev(), m.ino())
    })
    .collect()
}
fn settled(descriptors: Vec<(i32, u64, u64)>) {
    for (fd, device, inode) in descriptors {
        let mut metadata = std::mem::MaybeUninit::<libc::stat>::uninit();
        if unsafe { libc::fstat(fd, metadata.as_mut_ptr()) } == 0 {
            let m = unsafe { metadata.assume_init() };
            // Other parallel tests can reuse a closed fd number, but never this
            // exclusively created test file. Do not mistake reuse for a leak.
            assert_ne!((m.st_dev as u64, m.st_ino), (device, inode));
        }
    }
}
fn element(id: u32, bytes: &[u8]) -> Vec<u8> {
    let id = id.to_be_bytes();
    let first = id.iter().position(|b| *b != 0).unwrap();
    [
        id[first..].to_vec(),
        ((bytes.len() as u64) | (1 << 56)).to_be_bytes().to_vec(),
        bytes.to_vec(),
    ]
    .concat()
}
fn uint(id: u32, n: u64) -> Vec<u8> {
    element(id, &n.to_be_bytes())
}
pub(crate) fn fixture() -> Vec<u8> {
    let config: GenerateConfig = serde_json::from_value(serde_json::json!({
        "cm_version":"V29", "length":1,"profile":"8.1","level6":null,
        "shots":[{"start":0,"duration":1}],
        "level5":{"active_area_left_offset":1,"active_area_right_offset":3,
        "active_area_top_offset":5,"active_area_bottom_offset":7}
    }))
    .unwrap();
    let rpu = config
        .generate_rpu_list()
        .unwrap()
        .remove(0)
        .write_hevc_unspec62_nalu()
        .unwrap();
    let mut config = vec![0; 23];
    config[0] = 1;
    config[21] = 3;
    config[22] = 3;
    for kind in [32, 33, 34] {
        config.extend([kind, 0, 1, 0, 3, kind << 1, 1, 0xaa]);
    }
    let packet: Vec<_> = [vec![2, 1, 0xaa], vec![126, 1, 0xbb], rpu.clone(), rpu]
        .iter()
        .flat_map(|nal| [(nal.len() as u32).to_be_bytes().to_vec(), nal.clone()].concat())
        .collect();
    let track = element(
        0xae,
        &[
            uint(0xd7, 1),
            uint(0x73c5, 1),
            uint(0x83, 1),
            element(0x86, b"V_MPEGH/ISO/HEVC"),
            element(0x63a2, &config),
            element(0xe0, &[uint(0xb0, 160), uint(0xba, 96)].concat()),
            element(0x41e4, b"generated supplemental field"),
        ]
        .concat(),
    );
    let block = element(
        0xa3,
        &[vec![0x81], (-20i16).to_be_bytes().to_vec(), vec![0], packet].concat(),
    );
    let header = element(
        0x1a45dfa3,
        &[
            element(0x4282, b"matroska"),
            uint(0x4287, 4),
            uint(0x4285, 2),
        ]
        .concat(),
    );
    let segment = element(
        0x18538067,
        &[
            element(0x1549a966, &uint(0x2ad7b1, 1_000_000)),
            element(0x1654ae6b, &track),
            element(0x1f43b675, &[uint(0xe7, 10), block].concat()),
        ]
        .concat(),
    );
    [header, segment].concat()
}
fn input(folder: &Path) -> PathBuf {
    let path = folder.join("generated-source.mkv");
    OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&path)
        .unwrap()
        .write_all(&fixture())
        .unwrap();
    path
}

#[test]
fn source_bound_companion_packages_preserve_originals_and_settle_descriptors() {
    let temp = Temp::new();
    // Caller-owned generated fixture root, exported only by an opt-in test.
    let root = std::env::var_os("STAXRIP_GENERATED_BOUND_COMPANION_DIRECTORY")
        .map(PathBuf::from)
        .unwrap_or_else(|| temp.0.clone());
    let source = input(&root);
    let original = std::fs::read(&source).unwrap();
    let before = SourceIdentity::from_metadata(&std::fs::metadata(&source).unwrap());
    for full in [false, true] {
        let package = root.join(if full { "full" } else { "metadata" });
        std::fs::create_dir(&package).unwrap();
        let outputs = owned(&package, full);
        let fds = descriptors(&outputs);
        let receipt = produce(&source, outputs, Arc::new(Cancellation::default()))
            .unwrap_or_else(|e| panic!("{e}"));
        settled(fds);
        assert_eq!(receipt.source_identity, before);
        assert_eq!(
            (receipt.components.packets, receipt.components.records),
            (1, 2)
        );
        assert_eq!(receipt.components.enhancement_nals, 1);
        let mut manifest_file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(package.join("manifest.json"))
            .unwrap();
        manifest(&receipt.components, &mut manifest_file).unwrap();
        drop(manifest_file);
        let m: serde_json::Value =
            serde_json::from_slice(&std::fs::read(package.join("manifest.json")).unwrap()).unwrap();
        assert_eq!(m["source_path_identity_bound"], false); // Separate execution receipt, no prototype mutation.
        let index = std::fs::read_to_string(package.join("rpu-index.jsonl")).unwrap();
        for line in index.lines() {
            let row: serde_json::Value = serde_json::from_str(line).unwrap();
            assert_eq!(row["pts_ns"], -10_000_000);
        }
        if full {
            assert_eq!(std::fs::read(package.join(NAMES[5])).unwrap(), original);
        }
        for name in NAMES.iter().take(if full { 6 } else { 5 }) {
            assert!(
                OpenOptions::new()
                    .write(true)
                    .create_new(true)
                    .open(package.join(name))
                    .is_err()
            );
        }
    }
    assert_eq!(std::fs::read(&source).unwrap(), original);
    assert_eq!(
        SourceIdentity::from_metadata(&std::fs::metadata(&source).unwrap()),
        before
    );
}

#[test]
fn source_bound_invalid_sources_refuse_and_close_unpublished_components() {
    for case in [
        "missing",
        "symlink",
        "directory",
        "fifo",
        "empty",
        "oversize",
        "malformed",
    ] {
        let temp = Temp::new();
        let source = temp.0.join("source");
        match case {
            "missing" => {}
            "symlink" => {
                let original = input(&temp.0);
                symlink(original, &source).unwrap();
            }
            "directory" => std::fs::create_dir(&source).unwrap(),
            "fifo" => {
                use std::ffi::CString;
                use std::os::unix::ffi::OsStrExt;
                let name = CString::new(source.as_os_str().as_bytes()).unwrap();
                assert_eq!(unsafe { libc::mkfifo(name.as_ptr(), 0o600) }, 0);
            }
            "empty" => {
                File::create(&source).unwrap();
            }
            "oversize" => File::create(&source)
                .unwrap()
                .set_len(MOVIE_LIMIT + 1)
                .unwrap(),
            _ => std::fs::write(&source, b"not a Matroska input").unwrap(),
        }
        let outputs = owned(&temp.0, true);
        let fds = descriptors(&outputs);
        assert!(produce(&source, outputs, Arc::new(Cancellation::default())).is_err());
        settled(fds);
        for name in NAMES {
            let data = std::fs::read(temp.0.join(name)).unwrap();
            if case == "malformed" && name == NAMES[5] {
                // Full-mode streaming can stage input bytes before parser refusal.
                // They are not a successful source-bound result or a published archive.
                assert_eq!(data, b"not a Matroska input");
            } else {
                assert!(data.is_empty());
            }
        }
        assert!(!temp.0.join("manifest.json").exists());
    }
}

#[test]
fn source_bound_output_aliases_links_positions_modes_and_nonempty_refuse_before_write() {
    for case in [
        "source",
        "duplicate",
        "hardlink",
        "readonly",
        "readwrite",
        "directory",
        "nonempty",
        "position",
        "append",
    ] {
        let temp = Temp::new();
        let source = input(&temp.0);
        let original = std::fs::read(&source).unwrap();
        let mut outputs = owned(&temp.0, true);
        let path = temp.0.join(NAMES[1]);
        match case {
            "source" => {
                outputs.configuration = OpenOptions::new().write(true).open(&source).unwrap()
            }
            "duplicate" => outputs.configuration = outputs.rpu.try_clone().unwrap(),
            "hardlink" => std::fs::hard_link(&path, temp.0.join("linked")).unwrap(),
            "readonly" => outputs.configuration = File::open(&path).unwrap(),
            "readwrite" => {
                outputs.configuration = OpenOptions::new()
                    .read(true)
                    .write(true)
                    .open(&path)
                    .unwrap()
            }
            "directory" => outputs.configuration = File::open(&temp.0).unwrap(),
            "nonempty" => outputs.configuration.write_all(b"prior output").unwrap(),
            "position" => {
                outputs.configuration.seek(SeekFrom::Start(123)).unwrap();
            }
            _ => outputs.configuration = OpenOptions::new().append(true).open(&path).unwrap(),
        }
        let fds = descriptors(&outputs);
        assert!(matches!(
            produce(&source, outputs, Arc::new(Cancellation::default())),
            Err(ProductionFailure::UnsafeOutput)
        ));
        settled(fds);
        assert_eq!(std::fs::read(&source).unwrap(), original);
        for name in NAMES {
            let data = std::fs::read(temp.0.join(name)).unwrap();
            assert_eq!(
                data,
                if name == NAMES[1] && case == "nonempty" {
                    b"prior output".to_vec()
                } else {
                    vec![]
                }
            );
        }
    }
}

#[test]
fn source_bound_actual_replacement_mutation_and_final_cancel_never_return_receipt() {
    for case in ["replace", "mutate", "symlink", "remove", "cancel"] {
        let temp = Temp::new();
        let source = input(&temp.0);
        let original = std::fs::read(&source).unwrap();
        let outputs = owned(&temp.0, true);
        let fds = descriptors(&outputs);
        let cancel = Arc::new(Cancellation::default());
        let result = produce_then_check(&source, outputs, cancel.clone(), || match case {
            "replace" => {
                let other = temp.0.join("replacement");
                std::fs::write(&other, &original).unwrap();
                std::fs::rename(other, &source).unwrap();
            }
            "mutate" => {
                let mut data = original.clone();
                *data.last_mut().unwrap() ^= 1;
                std::fs::write(&source, data).unwrap();
            }
            "symlink" => {
                let other = temp.0.join("replacement");
                std::fs::rename(&source, &other).unwrap();
                symlink(other, &source).unwrap();
            }
            "remove" => std::fs::remove_file(&source).unwrap(),
            _ => cancel.request(),
        });
        assert!(
            matches!(result, Err(ProductionFailure::ChangedSource)) && case != "cancel"
                || matches!(result, Err(ProductionFailure::Cancelled)) && case == "cancel"
        );
        settled(fds);
        // A complete inner audit is not the authoritative source-bound result.
        assert!(
            std::fs::read_to_string(temp.0.join(NAMES[4]))
                .unwrap()
                .contains("\"kind\":\"complete\"")
        );
        assert!(!temp.0.join("manifest.json").exists());
    }
}

#[test]
fn source_bound_precancel_is_one_way_closes_owned_outputs_and_preserves_source() {
    let temp = Temp::new();
    let source = input(&temp.0);
    let original = std::fs::read(&source).unwrap();
    let outputs = owned(&temp.0, true);
    let fds = descriptors(&outputs);
    let cancel = Arc::new(Cancellation::default());
    cancel.request();
    cancel.request();
    assert!(cancel.requested());
    assert!(matches!(
        produce(&source, outputs, cancel),
        Err(ProductionFailure::Cancelled)
    ));
    settled(fds);
    assert_eq!(std::fs::read(&source).unwrap(), original);
    for name in NAMES {
        assert_eq!(std::fs::metadata(temp.0.join(name)).unwrap().len(), 0);
    }
}

#[test]
fn source_bound_owned_worker_is_joined_before_caller_removes_staging() {
    let temp = Temp::new();
    let source = input(&temp.0);
    let original = std::fs::read(&source).unwrap();
    let outputs = owned(&temp.0, true);
    let fds = descriptors(&outputs);
    let cancel = Arc::new(Cancellation::default());
    let (hit_send, hit_receive) = mpsc::sync_channel(1);
    let (release_send, release_receive) = mpsc::sync_channel(1);
    let request = cancel.clone();
    let worker_source = source.clone();
    let worker = std::thread::spawn(move || {
        produce_then_check(&worker_source, outputs, request, || {
            hit_send.send(()).unwrap();
            release_receive
                .recv_timeout(Duration::from_secs(5))
                .unwrap();
        })
    });
    let hit = hit_receive.recv_timeout(Duration::from_secs(5));
    cancel.request();
    let _ = release_send.send(());
    let result = worker.join().unwrap();
    assert!(hit.is_ok());
    assert!(matches!(result, Err(ProductionFailure::Cancelled)));
    settled(fds);
    assert_eq!(std::fs::read(&source).unwrap(), original);
    for name in NAMES {
        std::fs::remove_file(temp.0.join(name)).unwrap();
    }
}

#[test]
fn cancellation_is_checked_before_and_after_read_seek_write_flush_including_recheck() {
    struct Trigger {
        inner: Cursor<Vec<u8>>,
        cancel: Arc<Cancellation>,
        action: u8,
        calls: usize,
    }
    impl Read for Trigger {
        fn read(&mut self, b: &mut [u8]) -> io::Result<usize> {
            self.calls += 1;
            let n = self.inner.read(b)?;
            if self.action == 0 {
                self.cancel.request();
            }
            Ok(n)
        }
    }
    impl Seek for Trigger {
        fn seek(&mut self, p: SeekFrom) -> io::Result<u64> {
            self.calls += 1;
            let n = self.inner.seek(p)?;
            if self.action == 1 {
                self.cancel.request();
            }
            Ok(n)
        }
    }
    impl Write for Trigger {
        fn write(&mut self, b: &[u8]) -> io::Result<usize> {
            self.calls += 1;
            let n = self.inner.write(b)?;
            if self.action == 2 {
                self.cancel.request();
            }
            Ok(n)
        }
        fn flush(&mut self) -> io::Result<()> {
            self.calls += 1;
            if self.action == 3 {
                self.cancel.request();
            }
            Ok(())
        }
    }
    for action in 0..4 {
        for early in [false, true] {
            let cancel = Arc::new(Cancellation::default());
            let mut checked = Checked {
                inner: Trigger {
                    inner: Cursor::new(vec![1, 2, 3]),
                    cancel: cancel.clone(),
                    action,
                    calls: 0,
                },
                cancel: cancel.clone(),
                output_full: Arc::new(AtomicBool::new(false)),
            };
            if early {
                cancel.request();
            }
            let result = match action {
                0 => checked.read(&mut [0; 2]).map(|_| ()),
                1 => checked.seek(SeekFrom::Start(2)).map(|_| ()),
                2 => checked.write(b"ab").map(|_| ()),
                _ => checked.flush(),
            };
            assert!(result.is_err());
            assert_eq!(checked.inner.calls, if early { 0 } else { 1 });
            assert!(cancel.requested());
        }
    }
    let cancel = Arc::new(Cancellation::default());
    let mut input = Checked {
        inner: Cursor::new(vec![1; 8192]),
        cancel: cancel.clone(),
        output_full: Arc::new(AtomicBool::new(false)),
    };
    input.seek(SeekFrom::End(0)).unwrap();
    input.rewind().unwrap();
    cancel.request();
    assert!(crate::fingerprint_with_limit(&mut input, MOVIE_LIMIT).is_err());
}

#[test]
fn output_full_classification_requires_output_enospc_and_preserves_cancel_gate() {
    struct Fault(i32);
    impl Read for Fault {
        fn read(&mut self, _: &mut [u8]) -> io::Result<usize> {
            Err(io::Error::from_raw_os_error(self.0))
        }
    }
    impl Write for Fault {
        fn write(&mut self, _: &[u8]) -> io::Result<usize> {
            Err(io::Error::from_raw_os_error(self.0))
        }
        fn flush(&mut self) -> io::Result<()> {
            Err(io::Error::from_raw_os_error(self.0))
        }
    }
    for action in 0..3 {
        for code in [libc::ENOSPC, libc::EIO, libc::EACCES] {
            for cancelled in [false, true] {
                let full = Arc::new(AtomicBool::new(false));
                let cancel = Arc::new(Cancellation::default());
                if cancelled {
                    cancel.request();
                }
                let mut checked = Checked {
                    inner: Fault(code),
                    cancel,
                    output_full: full.clone(),
                };
                let result = match action {
                    0 => checked.read(&mut [0; 1]).map(|_| ()),
                    1 => checked.write(&[1]).map(|_| ()),
                    _ => checked.flush(),
                };
                assert!(result.is_err());
                assert_eq!(
                    full.load(Ordering::Acquire),
                    !cancelled && action != 0 && code == libc::ENOSPC
                );
            }
        }
    }
}
