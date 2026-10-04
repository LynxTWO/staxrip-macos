use std::{
    fs::{Metadata, OpenOptions},
    io::{self, Seek, Write},
    os::unix::fs::{MetadataExt, OpenOptionsExt},
};

use staxrip_dolby_metadata_audit::{FILE_LIMIT, Failure, audit_rpu, complete, fingerprint};

mod heap;
#[cfg(not(test))]
#[global_allocator]
static HEAP: heap::BoundedHeap = heap::BoundedHeap;

fn identity(m: &Metadata) -> (u64, u64, u64, i64, i64, i64, i64) {
    (
        m.dev(),
        m.ino(),
        m.len(),
        m.mtime(),
        m.mtime_nsec(),
        m.ctime(),
        m.ctime_nsec(),
    )
}

fn run() -> Result<(), Failure> {
    // A deliberately failed corrupt-input allocation must not dump metadata.
    let no_core = libc::rlimit {
        rlim_cur: 0,
        rlim_max: 0,
    };
    if unsafe { libc::setrlimit(libc::RLIMIT_CORE, &no_core) } != 0 {
        return Err(Failure::Bounds);
    }
    let args: Vec<_> = std::env::args_os().collect();
    if args.len() != 3 || args[1] != "rpu-json" {
        eprintln!("Usage: staxrip-dolby-metadata-audit rpu-json <local RPU archive>");
        return Err(Failure::Framing);
    }
    let mut input = OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NONBLOCK | libc::O_CLOEXEC | libc::O_NOCTTY)
        .open(&args[2])
        .map_err(|_| Failure::InputIO)?;
    let before = input.metadata().map_err(|_| Failure::InputIO)?;
    if !before.is_file() || before.len() == 0 || before.len() > FILE_LIMIT {
        return Err(Failure::Bounds);
    }
    let stdout = io::stdout();
    let mut output = io::BufWriter::new(stdout.lock());
    let receipt = audit_rpu(&mut input, &mut output)?;
    input.rewind().map_err(|_| Failure::InputIO)?;
    let rechecked = fingerprint(&mut input)?;
    let after = input.metadata().map_err(|_| Failure::InputIO)?;
    let path = std::fs::metadata(&args[2]).map_err(|_| Failure::InputIO)?;
    if identity(&before) != identity(&after)
        || identity(&before) != identity(&path)
        || rechecked != (receipt.bytes, receipt.sha256.clone())
        || receipt.bytes != before.len()
    {
        return Err(Failure::ChangedSource);
    }
    // The heap ceiling is fixed for the entire helper, including libdovi.
    writeln!(
        output,
        "{{\"kind\":\"resources\",\"heap_limit\":{},\"peak_heap_bytes\":{}}}",
        heap::HEAP_LIMIT,
        heap::peak()
    )
    .map_err(|_| Failure::OutputIO)?;
    complete(&mut output, &receipt)
}

fn main() {
    // Library diagnostics must not print input bytes, names or paths on panic.
    std::panic::set_hook(Box::new(|_| {}));
    if let Err(error) = run() {
        let _ = writeln!(
            io::stderr(),
            "Dolby metadata audit failed: {error}. No complete receipt."
        );
        std::process::exit(1);
    }
}
