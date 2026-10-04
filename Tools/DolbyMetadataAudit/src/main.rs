use std::{
    fs::{Metadata, OpenOptions},
    io::{self, Seek, Write},
    os::unix::fs::{MetadataExt, OpenOptionsExt},
};

use staxrip_dolby_metadata_audit::{
    FILE_LIMIT, Failure, audit_rpu, complete, fingerprint_with_limit,
    matroska::{MOVIE_LIMIT, audit_matroska, complete_matroska},
};

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
    if args.len() != 3 || (args[1] != "rpu-json" && args[1] != "mkv-json") {
        eprintln!("Usage: staxrip-dolby-metadata-audit <rpu-json|mkv-json> <local input>");
        return Err(Failure::Framing);
    }
    let movie = args[1] == "mkv-json";
    let limit = if movie { MOVIE_LIMIT } else { FILE_LIMIT };
    let mut input = OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NONBLOCK | libc::O_CLOEXEC | libc::O_NOCTTY)
        .open(&args[2])
        .map_err(|_| Failure::InputIO)?;
    let before = input.metadata().map_err(|_| Failure::InputIO)?;
    if !before.is_file() || before.len() == 0 || before.len() > limit {
        return Err(Failure::Bounds);
    }
    let stdout = io::stdout();
    let mut output = io::BufWriter::new(stdout.lock());
    let archive_receipt;
    let movie_receipt;
    let (bytes, digest) = if movie {
        movie_receipt = Some(audit_matroska(&mut input, before.len(), &mut output)?);
        archive_receipt = None;
        let r = movie_receipt.as_ref().unwrap();
        (r.bytes, r.sha256.clone())
    } else {
        archive_receipt = Some(audit_rpu(&mut input, &mut output)?);
        movie_receipt = None;
        let r = archive_receipt.as_ref().unwrap();
        (r.bytes, r.sha256.clone())
    };
    input.rewind().map_err(|_| Failure::InputIO)?;
    let rechecked = fingerprint_with_limit(&mut input, limit)?;
    let after = input.metadata().map_err(|_| Failure::InputIO)?;
    let path = std::fs::metadata(&args[2]).map_err(|_| Failure::InputIO)?;
    if identity(&before) != identity(&after)
        || identity(&before) != identity(&path)
        || rechecked != (bytes, digest)
        || bytes != before.len()
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
    if let Some(r) = movie_receipt {
        complete_matroska(&mut output, &r)
    } else {
        complete(&mut output, archive_receipt.as_ref().unwrap())
    }
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
