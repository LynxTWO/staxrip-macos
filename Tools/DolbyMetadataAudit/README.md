# Bounded Dolby metadata reader

This read-only helper is bundled at a fixed app-owned path for the native complete
Matroska HEVC inspection page in Slice 049. It enables no Dolby Vision conversion,
copy admission or picture edit. Build with Cargo on macOS or another Unix platform;
local qualification used macOS and Rust 1.98.1. Generated packet-reference tests also require FFmpeg/FFprobe (locally 9.0.2). The declared 1.88 minimum reflects
the pinned dependency's let-chain syntax; that minimum compiler is not qualified.

Development library modules also contain prototype companion production. They are
not native CLI commands, stable import APIs or enabled app archive features. The
new `companion_source::produce` opens an original source read-only with no-follow
flags, consumes caller-created staged File handles, checks source identity around
the existing content recheck, and supports one-way cooperative cancellation. All
owned files close when the call returns. Partial components can remain on refusal;
the caller owns cleanup after settlement. Concrete files exclude a buffered writer
flushing later on drop. Reject unsafe/nonempty/linked/aliased/positioned output
descriptors before writing. Trusted callers must still create outputs exclusively
and establish their path ownership; descriptor checks do not prove creation history.

The separate source-bound execution receipt is not a changed prototype manifest.
The manifest still declares its original source-path flag false and decoded mapping
unestablished. Cancellation checks I/O and receipt boundaries; it cannot preempt
blocked physical I/O or parser CPU. A request arriving after the last receipt check
does not revoke settled work. None of this publishes files, proves an immutable
source, qualifies decoded/EL association or admits a native archive workflow. See
`Docs/Planning/SOURCE-BOUND-COMPANION-EVIDENCE.md` at the repository root for scope.

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
HEVC NAL headers, as extracted by dovi_tool. That command is not a movie/container parser.
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
Dolby-standard or rendering validation. Native inspection adds an independent
encoded-packet proof and final source fingerprint, described below.

Dependency license declarations are inventoried in DEPENDENCY-LICENSES.json. The
libdovi MIT notice is in LICENSE-libdovi. No GPL reconstruction code is used.
All 69 supplied texts from the 37 dependency packages, including crc-catalog's
nested LICENSES directory, are retained under LICENSES. The app builder verifies
every inventoried hash before copying the helper and notices into its bundle.
The active Homebrew Rust toolchain library catalog and license texts are also
included, since the linked standard library is not a Cargo.lock dependency.
A separate build inventory retains compiler version and notice hashes.
The helper is signed before the enclosing app. Local ad-hoc development packaging
is not notarized or production distribution qualification.


## Complete Matroska HEVC packet observations

`mkv-json <local input>` adds a deliberately bounded container-reading prerequisite.
The native app uses the compact mode described below; full source-derived JSON
is development evidence and should remain private. Neither mode enables copy,
conversion or crop/resize. No additional dependency is used. The evaluated
matroska-demuxer 0.8.1 crate was not admitted: next_frame can treat an I/O error as
EOF, and unsigned timestamps cannot represent a negative total block timestamp.

This scanner consumes the complete file sequentially, hashes even skipped bytes,
and refuses invalid element/packet boundaries and explicit I/O errors. It supports
one unambiguous HEVC video track, finite clusters, a finite or EOF-bounded unknown-size
Segment, unlaced selected-video SimpleBlock and BlockGroup packets, and bounded
length-prefixed hvcC/NAL framing. Info/Tracks must precede clusters. It rejects
selected-video content encoding, codec delay, non-unit track timestamp scale,
nonzero track offset, TrackOperation, codec-state changes and additional block
payloads; unknown-size clusters, concatenated documents, multiple video tracks and
other codecs/containers need another qualified reader. Audio/subtitle blocks are
consumed but not decoded or certified. This is not a full Matroska/EBML-CRC,
parameter-set, slice, POC, bitstream-conformance or picture validator.

Protocol 2 begins with reported track/configuration and geometry facts. Pixel raster,
container crop and display dimensions/unit are explicitly declarations. DisplayUnit
can mean pixels, physical units, a ratio or unknown; do not treat every DisplayWidth
as an output pixel count. Each `packet` preserves its ordinal, source payload offset,
signed nanosecond PTS, explicit duration (null when absent), flags, size and SHA-256.
The additive `block_input_byte_offset` identifies the Block payload's start, including
its variable-width track VINT; `input_byte_offset` remains the encoded-video payload
start. FFmpeg packet position refers to the former. Never subtract a presumed fixed
four-byte prefix: generated one/two/three-byte track VINTs establish the distinction.
Each `rpu` retains the original packet and NAL ordinals, source offset, matching PTS,
full validated metadata and escaped-payload digest. Duplicates are retained. Type 63
NALs are counted as encoded enhancement declarations, not decoded pictures/residuals.

Packets arrive in decoding order. An extracted dovi_tool archive is reordered by
picture order count into display order; equating their ordinals can attach metadata
to the wrong picture. The reader does not sort or claim decoded-frame association.
In a particular complete private source, every packet matched the independent
FFprobe manifest, and all RPUs matched the prior archive after checked unique-PTS
presentation ordering. This is source-specific evidence, not a general POC mapper.

Limits: 1 TiB movie, 16 MiB selected packet, 1 MiB per track configuration, 256 tracks,
128 million parsed elements, 32 million encountered blocks, two million selected
packets and RPUs, existing 64 KiB RPU / 2 MiB JSON / 64 MiB tracked-heap ceilings.
The final receipt requires EOF, an independent whole-file hash scan and stable
file/path identity just as archive mode does. Require both complete and exit zero.
Output remains private; no helper-created files, media writes, processing admission
or archive publication. See Docs/Planning/BOUNDED-MATROSKA-DOLBY-EVIDENCE.md.


## Native compact inspection (protocol 3)

`mkv-summary <local input>` uses exactly the same container/framing, syntax/CRC,
resource, I/O and source-recheck boundaries. Every packet remains observable.
Each `rpu-summary` retains packet/NAL ordinal, PTS, payload digest and encoded
length, with mapping family, enhancement classification, declared scene refresh,
Level 5 active areas and content-mapping-version presence. Full metadata is omitted
from this protocol, not from its validation. The complete receipt includes an
order-sensitive SHA-256 over concatenated records of signed i64 little-endian
PTS nanoseconds, signed i64 little-endian encoded byte count and 32 packet digest
bytes. Durations are not in this proof; missing packet durations are not inferred.

The native caller retains one bounded 64 KiB protocol line and aggregate counts,
not a full-film metadata or packet array. It requires protocol 3, consistent ordinals,
bounds, counts, resource settlement, final receipt and exit zero. It independently
streams FFprobe packet payload hashes and exact integer nanosecond timestamps,
checks the selected stream configuration against the helper's hvcC digest, and
rehashes the source afterward. Reordering or disagreement refuses completion.
It owns a security-scoped lease and joins child processes/readers on cancellation;
replacement requests wait for the old worker and cannot publish its late result.

Build the release helper before `swift test`, or use the CI workflow. Native
integration tests invoke the generated Rust fixture test with the explicit
STAXRIP_GENERATED_DOLBY_FIXTURE export path; that test uses create_new and never
replaces an existing file. This test-only export is not a runtime helper command.
`build.command` / `package.command` invoke scripts/build-dolby-helper.command,
requiring Cargo plus Python 3.11 or newer at build time. The notice inventory must
match every locked dependency package before packaging. The running app installs nothing.
The native reference check requires the existing locally installed FFprobe.

The page distinguishes encoded-packet association from decoded-picture/POC
association, counts enhancement NAL units rather than enhancement frames, and
shows container crop/display units separately from Level 5 luma offsets. Odd
luma offsets are valid declarations, not proof of chroma-aligned cropping.
Re-encoding, edited geometry, measured brightness, calibrated rendering and
AV1/other-container readers remain separate acceptance work.

Tools/DolbyFrameReference is a separate, unbundled development reference for decoded
base-frame/raw-RPU association. Its direct wire and complete coverage checks do not
change this helper's protocol version, native packaging or conversion admission.


## Development original-companion staging library

The optional macOS/Linux `companion_stage::produce` library entry point requires a
trusted caller's existing empty, owned 0700 stage. It creates only fixed 0600 component
names exclusively with descriptor-relative no-follow opens, records their identities
and passes concrete files to the cancellable source-bound core. After settlement it
writes the unchanged version-zero prototype manifest exclusively, rereads actual disk
membership/content and requires final stage/parent/component/source identity observations.
It returns an in-memory staged receipt. It never creates/removes/publishes a stage or
accepts manifest-directed output paths; partial files remain the caller's responsibility.

This library has no runtime writer command or native app caller. Semantic verification,
worker/process/resource integration, stable archive/import and storage/crash qualification
remain separate. The caller must join its worker before cleanup. Cooperative cancellation
cannot interrupt physical filesystem I/O or parser CPU. Immediate parent/path observations
are not an ancestor sandbox, immutable snapshot or same-user adversarial guarantee.
Metadata-only omits BL/EL pictures and outside-track information; complete mode copies the
whole source-sized original container including embedded names/metadata. MacOS generated
checks are recorded in Docs/Planning/OWNED-COMPANION-STAGE-EVIDENCE.md; Linux is untested.


## Separate unbundled development writer

The `development-companion-writer` feature builds the separate
`staxrip-dolby-companion-writer` executable. Default builds and the native bundle still
include only the existing read-only reader. Build it deliberately for generated work:

```sh
cargo build --release --locked --features development-companion-writer \
  --manifest-path Tools/DolbyMetadataAudit/Cargo.toml
python3 Tools/DolbyCompanionCheck/test_writer.py -v
```

The development Python caller supplies metadata/full retention, source/stage paths,
an operation correlation ID and captured source/stage device/inode IDs as arguments
without a shell. The writer emits one bounded ready row, waits for the exact bounded
start frame followed by EOF, then uses the source/stage IDs before writing. Completion
contains actual source/stage IDs, source digest/counts, fixed component receipts and
tracked heap observations, all without source paths or RPU payloads. Require exact
protocol plus exit zero; a row alone is insufficient. This is a temporary development
process protocol, not a stable archive/import or persisted execution binding.

The parent must own cancellation, wait/close child and pipes before cleanup, verify
actual disk/source boundaries and separately establish semantics/publication. The
Python development caller implements those narrower process/disk checks; it accepts
only an explicitly trusted executable. Cancellation terminates the process group;
physical I/O preemption and native lifecycle/resource/signing are not qualified.
No automatic cleanup/publication, native writer command or new dependency is added.
See Docs/Planning/COMPANION-WRITER-PROCESS-EVIDENCE.md.
