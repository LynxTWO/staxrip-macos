//! Unbundled development executable. The native reader remains read-only.
use staxrip_dolby_metadata_audit::{
    companion_source::{Cancellation, ProductionFailure},
    companion_stage::{self, Retention, StageFailure},
};
use std::{
    io::{self, Read, Write},
    path::Path,
    sync::Arc,
};
mod heap;
#[cfg(not(test))]
#[global_allocator]
static HEAP: heap::BoundedHeap = heap::BoundedHeap;
const LINE_LIMIT: usize = 16 * 1024;
fn emit(output: &mut impl Write, value: serde_json::Value) -> Result<(), ()> {
    let bytes = serde_json::to_vec(&value).map_err(|_| ())?;
    if bytes.len() + 1 > LINE_LIMIT {
        return Err(());
    }
    output.write_all(&bytes).map_err(|_| ())?;
    output.write_all(b"\n").map_err(|_| ())?;
    output.flush().map_err(|_| ())
}
fn run() -> Result<(), u8> {
    let no_core = libc::rlimit {
        rlim_cur: 0,
        rlim_max: 0,
    };
    if unsafe { libc::setrlimit(libc::RLIMIT_CORE, &no_core) } != 0 {
        return Err(1);
    }
    let args: Vec<_> = std::env::args_os().collect();
    if args.len() != 9 {
        return Err(1);
    }
    let mode = args[1].to_str().ok_or(1)?;
    let retention = match mode {
        "metadata" => Retention::MetadataOnly,
        "full" => Retention::EntireContainer,
        _ => return Err(1),
    };
    let operation = args[4].to_str().ok_or(1)?;
    if operation.len() != 32
        || !operation
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    {
        return Err(1);
    }
    let number = |index: usize| -> Result<u64, u8> {
        let s = args[index].to_str().ok_or(1)?;
        if s.is_empty() || s.len() > 20 || !s.bytes().all(|b| b.is_ascii_digit()) {
            return Err(1);
        }
        s.parse().map_err(|_| 1)
    };
    let expected = companion_stage::ExpectedFiles {
        source: (number(5)?, number(6)?),
        stage: (number(7)?, number(8)?),
    };
    let stdout = io::stdout();
    let mut output = stdout.lock();
    emit(
        &mut output,
        serde_json::json!({"kind":"ready","protocol":1,"operation":operation}),
    )
    .map_err(|_| 1)?;
    // Finite controller frame: exact start token then EOF, bounded even if hostile.
    // Waiting here performs no source reads or stage writes. Parent owns termination.
    let mut start = Vec::new();
    io::stdin()
        .lock()
        .take(41)
        .read_to_end(&mut start)
        .map_err(|_| 1)?;
    if start != format!("start {operation}\n").as_bytes() {
        return Err(1);
    }
    let staged = companion_stage::produce_expected(
        Path::new(&args[2]),
        Path::new(&args[3]),
        retention,
        Arc::new(Cancellation::default()),
        expected,
    )
    .map_err(|error| match error {
        StageFailure::Production(ProductionFailure::OutputFull) => 28,
        _ => 1,
    })?;
    let r = &staged.source_bound.components;
    let components:Vec<_>=staged.members.iter().map(|m|serde_json::json!({"name":m.name,"bytes":m.content.bytes,"sha256":m.content.sha256})).collect();
    emit(
        &mut output,
        serde_json::json!({"kind":"staged","protocol":1,"operation":operation,
        "retention":mode,"source_file_id":staged.source_bound.source_identity.file_id(),"stage_file_id":staged.stage_file_id,
        "source_bytes":r.input.bytes,"source_sha256":r.input.sha256,"packets":r.packets,"records":r.records,
        "enhancement_nals":r.enhancement_nals,"components":components,
        "heap_limit":heap::HEAP_LIMIT,"peak_heap_bytes":heap::peak(),"semantic_verification":false}),
    ).map_err(|_| 1)
}
fn main() {
    std::panic::set_hook(Box::new(|_| {}));
    if let Err(status) = run() {
        let _ = writeln!(
            io::stderr(),
            "Companion writer refused. No successful process receipt."
        );
        std::process::exit(i32::from(status));
    }
}
