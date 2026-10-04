# Bounded Dolby metadata development reader

This is a read-only development prerequisite for Slice 049. It is **not bundled,
discovered or executed by StaxRip**, and does not enable any Dolby Vision
conversion or picture edit. Build with Cargo on macOS or another Unix platform;
local qualification used macOS and Rust 1.98.1. The declared 1.88 minimum reflects
the pinned dependency's let-chain syntax; that minimum compiler is not qualified.

```
cargo test --locked --manifest-path Tools/DolbyMetadataAudit/Cargo.toml
cargo build --release --locked --manifest-path Tools/DolbyMetadataAudit/Cargo.toml
```

The resulting `staxrip-dolby-metadata-audit` accepts `rpu-json` followed by one
local RPU archive path. Output is newline-delimited JSON on stdout. It contains
complete parsed metadata and must be treated as private source material. Errors
contain categories, without input names, paths or bytes. No files are written by
the helper. A caller owns capture, cancellation, cleanup and publication.

Input is a four-byte-start-code RPU archive with escaped payloads and without
HEVC NAL headers, as extracted by dovi_tool. This is not a movie/container parser.
Each RPU is validated using MIT libdovi 3.3.2, pinned to
82384bc7652c6f88cb63f7f11e0315b624003fc3; Cargo.lock pins transitive resolutions.
One record is retained at a time. Repeated records remain separate and retain
their indices, delimiter offsets, encoded lengths, SHA-256 and full metadata.
They are never silently deduplicated. Profiles and active-area offsets are
reported metadata, not measurements of the decoded picture.

Protocol 1 begins with a `begin` record. Each `rpu` record has an index, input byte
offset, encoded payload size/hash and `metadata`. A `resources` record describes
the tracked Rust heap, followed by `complete` with count, whole-archive byte
length/hash, record peak and successful source recheck. **Require successful exit
as well as the complete receipt.** Flush or pipe failure can fail exit even if a
receipt became visible. A partial stream never establishes a completed audit.
Input errors are distinguished from EOF. The source is scanned again, and size,
device/inode, modification/change timestamps and path identity are rechecked.
These are observations at boundaries, not an immutable-input snapshot.

Limits: 512 MiB input archive, 64 KiB escaped RPU, two million RPUs, 2 MiB emitted
JSON record, 64 MiB tracked Rust allocations for the entire helper. Allocation
refusal can abort the helper; it cannot produce a successful completion. The heap
limit includes Rust library/serialization allocations, not code pages, allocator
overhead, OS memory or stack. Core dumps are disabled for this process. Regular
files only; nonblocking open also prevents waiting for a FIFO producer.

Generated tests cover profiles 5/8.1/8.4, active-area retention, repeated metadata,
seven chunk sizes, CRC corruption, malformed/truncated/oversize records, explicit
read/write/flush failures, interrupted-read retry, actual file mutation,
oversize sparse files, FIFO refusal and an actual malicious upstream allocation.
The malicious count asks for an 80,000,004-byte pivot vector; the child fails
without a complete receipt. Initial test construction incorrectly assumed u64
pivots; the dependency uses u16, and the fixture was corrected rather than the
memory limit or assertion weakened.

This only establishes the complete **archive** read. An archive truncated exactly
between valid RPUs is indistinguishable from a legitimately shorter archive
without an independent expected sequence. Extraction completeness, one RPU per
displayed picture, previous-RPU references, frame/timestamp association, EL/BL
correspondence, AV1 framing and semantic transformations require separate checks.
The parser is shared with dovi_tool; matching its prior JSON is not independent
Dolby-standard or rendering validation. Native integration and packaging remain
unfinished.

Dependency license declarations are inventoried in DEPENDENCY-LICENSES.json. The
libdovi MIT notice is in LICENSE-libdovi. No GPL reconstruction code is used.
This is source/development tooling; collect the complete transitive license text
set with binary packaging. Follow-up inspection found 69 supplied texts across
all 37 dependency packages, including crc-catalog's nested LICENSES directory;
they are captured privately and their names/hashes are inventoried. No app/distribution dependency change is claimed here.
