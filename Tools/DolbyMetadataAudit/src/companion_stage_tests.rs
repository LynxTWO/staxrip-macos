use super::*;
use std::{
    fs,
    os::unix::fs::{PermissionsExt, symlink},
    sync::{
        atomic::{AtomicU64, Ordering},
        mpsc,
    },
    time::Duration,
};

static NEXT: AtomicU64 = AtomicU64::new(0);
struct Temp(PathBuf);
impl Temp {
    fn new() -> Self {
        let p = std::env::temp_dir().join(format!(
            "staxrip-owned-stage-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&p).unwrap();
        Self(p)
    }
    fn source(&self) -> PathBuf {
        let path = self.0.join("generated-source.mkv");
        fs::write(&path, crate::companion_source::tests::fixture()).unwrap();
        path
    }
    fn stage(&self) -> PathBuf {
        make_stage(&self.0.join("stage"))
    }
}
impl Drop for Temp {
    fn drop(&mut self) {
        fs::remove_dir_all(&self.0).unwrap();
    }
}
fn make_stage(path: &Path) -> PathBuf {
    fs::create_dir(path).unwrap();
    fs::set_permissions(path, fs::Permissions::from_mode(0o700)).unwrap();
    path.to_path_buf()
}
fn cancel() -> Arc<Cancellation> {
    Arc::new(Cancellation::default())
}
fn hash(path: &Path) -> String {
    crate::hex(Sha256::digest(fs::read(path).unwrap()))
}

#[test]
fn owned_stage_packages_preserve_originals_and_match_disk_receipts() {
    let temp = Temp::new();
    let root = if let Some(path) = std::env::var_os("STAXRIP_GENERATED_STAGED_COMPANION_DIRECTORY")
    {
        let p = PathBuf::from(path);
        assert!(p.is_dir());
        assert_eq!(fs::read_dir(&p).unwrap().count(), 0);
        p
    } else {
        temp.0.clone()
    };
    let source = root.join("generated-source.mkv");
    let original = crate::companion_source::tests::fixture();
    fs::write(&source, &original).unwrap();
    for (mode, retention, count) in [
        ("metadata", Retention::MetadataOnly, 6),
        ("full", Retention::EntireContainer, 7),
    ] {
        let stage = make_stage(&root.join(mode));
        let r = produce(&source, &stage, retention, cancel()).unwrap();
        assert_eq!(r.members.len(), count);
        assert_eq!(fs::read_dir(&stage).unwrap().count(), count);
        assert_eq!(
            (
                r.source_bound.components.packets,
                r.source_bound.components.records
            ),
            (1, 2)
        );
        for member in &r.members {
            let p = stage.join(member.name);
            let m = fs::symlink_metadata(&p).unwrap();
            assert!(m.is_file());
            assert_eq!(m.mode() & 0o7777, 0o600);
            assert_eq!(m.nlink(), 1);
            assert_eq!(m.len(), member.content.bytes);
            assert_eq!(hash(&p), member.content.sha256);
        }
        let manifest: serde_json::Value =
            serde_json::from_slice(&fs::read(stage.join(NAMES[6])).unwrap()).unwrap();
        assert_eq!(manifest["source_path_identity_bound"], false);
        assert_eq!(manifest["decoded_frame_association"], "not-established");
        if count == 7 {
            assert_eq!(fs::read(stage.join(NAMES[5])).unwrap(), original);
        } else {
            assert!(!stage.join(NAMES[5]).exists());
        }
    }
    assert_eq!(fs::read(source).unwrap(), original);
}

#[test]
fn unsafe_or_nonempty_stages_refuse_without_overwriting() {
    for case in 0..10 {
        let temp = Temp::new();
        let source = temp.source();
        let stage = temp.stage();
        match case {
            0 => fs::write(stage.join("existing"), b"keep").unwrap(),
            1 => symlink(&source, stage.join(NAMES[0])).unwrap(),
            2 => fs::create_dir(stage.join("nested")).unwrap(),
            3 => fs::set_permissions(&stage, fs::Permissions::from_mode(0o755)).unwrap(),
            4 => fs::set_permissions(&stage, fs::Permissions::from_mode(0o1700)).unwrap(),
            5 => {
                fs::remove_dir(&stage).unwrap();
                symlink(&temp.0, &stage).unwrap();
            }
            6 => {
                fs::remove_dir(&stage).unwrap();
                fs::write(&stage, b"keep").unwrap();
            }
            7 => fs::remove_dir(&stage).unwrap(),
            8 => {
                for n in 0..9 {
                    fs::write(stage.join(format!("extra-{n}")), b"keep").unwrap();
                }
            }
            9 => {
                let p = CString::new(stage.join("pipe").as_os_str().as_bytes()).unwrap();
                assert_eq!(unsafe { libc::mkfifo(p.as_ptr(), 0o600) }, 0);
            }
            _ => unreachable!(),
        }
        assert!(
            produce(&source, &stage, Retention::MetadataOnly, cancel()).is_err(),
            "case {case}"
        );
        assert_eq!(
            fs::read(&source).unwrap(),
            crate::companion_source::tests::fixture()
        );
        if case == 0 {
            assert_eq!(fs::read(stage.join("existing")).unwrap(), b"keep");
            assert_eq!(fs::read_dir(&stage).unwrap().count(), 1);
        }
        if case == 6 {
            assert_eq!(fs::read(&stage).unwrap(), b"keep");
        }
    }
    let temp = Temp::new();
    let source = temp.source();
    let stage = temp.stage();
    let alias = temp.0.join("parent-alias");
    symlink(&temp.0, &alias).unwrap();
    assert!(
        produce(
            &source,
            &alias.join("stage"),
            Retention::MetadataOnly,
            cancel()
        )
        .is_err()
    );
    assert_eq!(fs::read_dir(&stage).unwrap().count(), 0);
}

#[test]
fn creation_collision_or_substitution_never_receives_source_writes() {
    for case in 0..6 {
        let temp = Temp::new();
        let source = temp.source();
        let stage = temp.stage();
        let stop = cancel();
        let result = produce_checked(
            &source,
            &stage,
            Retention::MetadataOnly,
            stop.clone(),
            |index, path| {
                if index != 0 {
                    return;
                }
                match case {
                    0 => fs::write(path.join(NAMES[1]), b"keep").unwrap(),
                    1 => {
                        fs::rename(path.join(NAMES[0]), temp.0.join("moved")).unwrap();
                        fs::write(path.join(NAMES[0]), b"").unwrap();
                    }
                    2 => fs::hard_link(path.join(NAMES[0]), temp.0.join("linked")).unwrap(),
                    3 => {
                        fs::set_permissions(path.join(NAMES[0]), fs::Permissions::from_mode(0o644))
                            .unwrap()
                    }
                    4 => {
                        fs::rename(path, temp.0.join("old-stage")).unwrap();
                        make_stage(path);
                    }
                    5 => stop.request(),
                    _ => unreachable!(),
                }
            },
            || {},
            |_| {},
        );
        assert!(result.is_err(), "case {case}");
        if case == 0 {
            assert_eq!(fs::read(stage.join(NAMES[1])).unwrap(), b"keep");
        }
        if case == 1 {
            assert_eq!(fs::metadata(temp.0.join("moved")).unwrap().len(), 0);
        }
        assert_eq!(
            fs::read(source).unwrap(),
            crate::companion_source::tests::fixture()
        );
        assert!(!stage.join(NAMES[6]).exists());
    }
}

#[test]
fn settled_files_membership_and_directory_identity_are_rechecked() {
    for case in 0..12 {
        let temp = Temp::new();
        let source = temp.source();
        let stage = temp.stage();
        let result = produce_checked(
            &source,
            &stage,
            Retention::EntireContainer,
            cancel(),
            |_, _| {},
            || {
                let p = stage.join(NAMES[2]);
                match case {
                    0 => fs::remove_file(&p).unwrap(),
                    1 => fs::write(stage.join("extra"), b"keep").unwrap(),
                    2 => {
                        let mut b = fs::read(&p).unwrap();
                        b[4] ^= 1;
                        fs::write(&p, b).unwrap();
                    }
                    3 => {
                        let b = fs::read(&p).unwrap();
                        fs::rename(&p, temp.0.join("old-component")).unwrap();
                        fs::write(&p, b).unwrap();
                        fs::set_permissions(&p, fs::Permissions::from_mode(0o600)).unwrap();
                    }
                    4 => fs::hard_link(&p, temp.0.join("linked")).unwrap(),
                    5 => {
                        fs::remove_file(&p).unwrap();
                        symlink(&source, &p).unwrap();
                    }
                    6 => {
                        fs::remove_file(&p).unwrap();
                        let n = CString::new(p.as_os_str().as_bytes()).unwrap();
                        assert_eq!(unsafe { libc::mkfifo(n.as_ptr(), 0o600) }, 0);
                    }
                    7 => fs::set_permissions(&p, fs::Permissions::from_mode(0o644)).unwrap(),
                    8 => fs::set_permissions(&stage, fs::Permissions::from_mode(0o755)).unwrap(),
                    9 => {
                        fs::rename(&stage, temp.0.join("old-stage")).unwrap();
                        make_stage(&stage);
                    }
                    10 => {
                        let b = fs::read(&source).unwrap();
                        fs::rename(&source, temp.0.join("old-source")).unwrap();
                        fs::write(&source, b).unwrap();
                    }
                    11 => fs::write(&source, b"changed generated source").unwrap(),
                    _ => unreachable!(),
                }
            },
            |_| {},
        );
        assert!(result.is_err(), "case {case}");
        // A written prototype manifest is never itself a successful staged receipt.
        assert!(stage.join(NAMES[6]).exists() || case == 9);
    }
}

#[test]
fn replacements_of_parent_or_already_read_components_refuse() {
    let temp = Temp::new();
    let source = temp.source();
    let stage = temp.stage();
    let alias = temp.0.with_extension("moved");
    let result = produce_checked(
        &source,
        &stage,
        Retention::MetadataOnly,
        cancel(),
        |_, _| {},
        || {
            fs::rename(&temp.0, &alias).unwrap();
            fs::create_dir(&temp.0).unwrap();
        },
        |_| {},
    );
    assert!(result.is_err());
    fs::remove_dir(&temp.0).unwrap();
    fs::rename(&alias, &temp.0).unwrap();
    let temp = Temp::new();
    let source = temp.source();
    let stage = temp.stage();
    let changed = std::cell::Cell::new(false);
    let result = produce_checked(
        &source,
        &stage,
        Retention::MetadataOnly,
        cancel(),
        |_, _| {},
        || {},
        |_| {
            if changed.replace(true) {
                return;
            }
            let p = stage.join(NAMES[0]);
            let bytes = fs::read(&p).unwrap();
            fs::rename(&p, temp.0.join("old-read-component")).unwrap();
            fs::write(&p, bytes).unwrap();
            fs::set_permissions(&p, fs::Permissions::from_mode(0o600)).unwrap();
        },
    );
    assert!(result.is_err());
}

#[test]
fn cancellation_is_checked_before_creation_during_reread_and_after_writes() {
    for case in 0..3 {
        let temp = Temp::new();
        let source = temp.source();
        let stage = temp.stage();
        let stop = cancel();
        if case == 0 {
            stop.request();
        }
        let result = produce_checked(
            &source,
            &stage,
            Retention::MetadataOnly,
            stop.clone(),
            |_, _| {},
            || {
                if case == 1 {
                    stop.request();
                }
            },
            |_| {
                if case == 2 {
                    stop.request();
                }
            },
        );
        assert!(
            matches!(result, Err(StageFailure::Cancelled)),
            "case {case}"
        );
        if case == 0 {
            assert_eq!(fs::read_dir(&stage).unwrap().count(), 0);
        }
        assert_eq!(
            fs::read(source).unwrap(),
            crate::companion_source::tests::fixture()
        );
    }
}

#[test]
fn owned_writer_worker_joins_before_caller_cleanup() {
    let temp = Temp::new();
    let source = temp.source();
    let stage = temp.stage();
    let stop = cancel();
    let child_stop = stop.clone();
    let (ready_tx, ready_rx) = mpsc::channel();
    let (release_tx, release_rx) = mpsc::channel();
    let child_stage = stage.clone();
    let worker = std::thread::spawn(move || {
        produce_checked(
            &source,
            &child_stage,
            Retention::MetadataOnly,
            child_stop,
            |_, _| {},
            || {
                ready_tx.send(()).unwrap();
                release_rx.recv_timeout(Duration::from_secs(5)).unwrap();
            },
            |_| {},
        )
    });
    ready_rx.recv_timeout(Duration::from_secs(5)).unwrap();
    stop.request();
    release_tx.send(()).unwrap();
    assert!(matches!(
        worker.join().unwrap(),
        Err(StageFailure::Cancelled)
    ));
    assert!(stage.join(NAMES[6]).exists());
    fs::remove_dir_all(stage).unwrap();
    assert!(temp.0.join("generated-source.mkv").exists());
}
