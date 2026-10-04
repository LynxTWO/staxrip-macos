# Original companion component producer
Version: 0.1. Date: 2026-10-04. Scope: D-100 / R-059 / Slice 049.
Status: generated Rust/component, existing decoded-reference, ordinary app regression
and optimized bundle checks passed. Development-only, no native
archive execution/import or HDR conversion admission.

## Retention choices and consequences

The producer creates exact original selected-video TrackEntry payload, hvcC, escaped
RPU archive, RPU-to-packet index and source audit components. Metadata-only excludes
base/enhancement picture payloads and outside-track container information. A source
fingerprint is an integrity identifier, not replacement picture data. This option
cannot preserve a complete original master or make new compressed base pictures
interchangeable with matching original enhancement residuals.

Optional complete mode tees the entire original container during the audited read.
Its size/hash must equal the complete audited input and independent recheck. This
preserves matching original BL/EL/RPU/configuration and all container bytes without
claiming a qualified selected-track remux or enhancement reconstruction. It also
retains other streams, tags, attachments and embedded names if present. Source-sized
storage and privacy consequences must appear in native review before integration;
no such user-facing option is enabled here. Untouched original data is independent
of any later transformed component. Nothing labels an HDR-only output as Dolby Vision.

Supplementary Dolby configuration can occur outside hvcC. Rather than discard fields
which the bounded reader does not interpret, metadata-only also retains every byte of
the selected TrackEntry payload. The outer TrackEntry EBML header is excluded; its
original payload offset is recorded. Field meaning is not certified by retaining it.
Complete mode additionally preserves that outer header and all surrounding container
bytes. A future importer must validate structure/identity and deliberately choose
which fields to use; unknown original fields cannot be silently applied to a new track.

## Mechanism and trust boundary

An internal OriginalObserver receives validated configuration and each CRC/syntax-
checked raw escaped RPU. Native audit methods use NoOriginals and do not capture or
write archive bytes; the existing CLI still exposes only its three read-only commands.
Compact/full protocol schemas and output stay unchanged. Development production uses
a new library API; it opens no path, starts no process and performs no publication.
It accepts caller-owned seekable input and writers, so native permissions, regular-file
open flags, exclusive output creation and source descriptor/path identity are caller
obligations. The current product has no caller for this archive API.

The RPU archive uses the existing bounded reader's four-byte delimiter followed by
exact original escaped payload bytes, without the two-byte HEVC NAL header. The accepted
NAL header is already constrained by the reader; the index records original payload
byte offset, packet index, NAL ordinal, signed PTS, archive delimiter offset, payload
size/hash and record index. It neither sorts timestamps nor deduplicates identical RPUs.
Presentation order, decoder output and enhancement pairing are not inferred.

Archive-specific capture bounds each parsed TrackEntry payload at 1 MiB while selecting
the video track. This additionally bounds temporary capture on other tracks, and may
refuse an archive even when the ordinary read-only audit accepts a larger unknown field.
Native capture is disabled. Selected capture and hvcC remain bounded through the read;
packet/RPU/native parser bounds remain unchanged. Metadata/index components each have
512 MiB limits; source audit is at most 1 GiB; whole input/container is at most 1 TiB.
Writer receipts stream SHA-256 and actual accepted byte counts, handling short writes.
These are file/record bounds, not a new whole-process resource qualification.

After parsing, the producer requires at least one RPU, rehashes the entire source from
its beginning and compares length/hash with the audited read and optional complete
copy. All component writes/flushes must settle successfully before returning receipts.
Partial bytes may exist on failure and remain staged. The prototype version-zero
manifest binds component names/lengths/hashes, source identity by content and original
encoded association; it explicitly declares source_path_identity_bound=false and
decoded_frame_association=not-established. It is not a stable public archive/session
format, native import contract or future carriage guarantee.

Generic seekable input can change pathname while keeping its open contents stable;
this API does not detect that. Native integration must establish descriptor/path
identity and cancellation/owned cleanup separately before handing settled components
to ResultSetStaging. Streamed receipts alone do not independently verify disk outputs;
D-099 must reread the actual staged components and the manifest before publication.
No archive is admitted by bypassing either the semantic or publication boundary.

## Generated evidence

Seven additional Rust test functions qualify the new component/track seams alongside
existing reader tests. Both modes across NAL length widths 1/2/4 retain exact source
RPU escape bytes and hvcC; selected TrackEntry capture preserves an unparsed supplementary
field byte-for-byte. Four packets include negative, reordered and duplicate PTS and
five RPUs, with a duplicate in one packet. Every index/offset/hash/NAL ordinal agrees
with original input and archive slices. An invisible packet remains an encoded
observation, not a decoder-output claim. Opaque enhancement NAL bytes and separate
other-track bytes survive the complete container; no valid EL residual decoder claim.

The archived RPUs pass the existing independent archive reader with matching original
payload hashes. Original compact audit plus completion output is byte-identical to
the no-op observer's output on the same supported source. The existing actual generated
B-frame HEVC test also exercises this producer: exact retained container bytes and
four packet hashes/timestamps agree with its independent FFprobe observations, while
five RPUs including the deliberate duplicate remain intact.

An actual generated file input and six exclusively created component files bind every
manifest length/hash to disk contents. Existing output creation refuses replacement;
source descriptor/content remain unchanged. Empty/truncated/corrupt/no-RPU sources,
rewritten recheck input and input I/O failure refuse without a receipt. Six component
write/flush failures and manifest write/flush failure refuse. Repeated short writes
complete accurately; a small actual writer byte ceiling refuses the next byte.
Archive-only track capture refuses a larger unknown field, while ordinary native audit
still accepts it. No assertions/deadlines/default scheduling are changed.

Initial Clippy rejected a nested conditional; the new code uses the supported Rust
1.88 let-chain form and final warnings-as-errors lint passes. Existing 15 generated
software-decoder reference tests pass separately; no new complete private-source run.

Final Rust run passed 24 tests across library/main/container/archive suites, zero
failures/skips; format and warnings-as-errors Clippy passed. Fifteen existing generated
decoder-reference tests passed in 2.238 s. Rebuilt release helper preceded ordinary
app regression: all 331 tests/78 suites passed in 202.819 s with unchanged default
assertions/scheduling and existing opt-in skips. Optimized build.command passed;
outer app and existing bundled helper signatures verify. Actual Mach-O minimum is
macOS 14.0 for the app and 11.0 for the Rust helper. An initial private check incorrectly
expected both to equal 14; the actual helper declaration is lower, with no product
build/assertion change. These declarations are within the app's 14 boundary but are
not execution qualification on older macOS hardware. Signing is ad-hoc development,
not notarization. No UI/controller/session schema, new dependency or native writer
command changed; no new owner-source walkthrough or heard VoiceOver claim.

Privacy scan examines ten changed/nonignored-untracked repository files for exact
owner source path/name/stem: three patterns, zero matching files, positive sentinel.
Private receipts/ignored binaries/media are excluded; this is scoped identifier absence.
Original source descriptor and current recovery bytes remain unchanged. Planning audit
has no findings. PR 74's automatic app run failed Fresh analysis at 5.300514 s versus
five; all 331 tests settled in 436.882 s with one issue and preview packaging skipped.
Keep that failure separately from local qualification; no new observer or rerun.

## Remaining work

Native caller/source identity binding, cancellable producer ownership, settled cleanup,
semantic component reread and integration with exclusive result-set publication remain
open. So do result review/storage estimates, archive-specific ENOSPC/other-volume/crash
recovery, bounded migration to a stable import format, future carriage/player support,
physical picture edits/statistics and signed distribution. No owner archive or encode,
queue/session edit, audio listening, new native option, merge or release. PR 74's
existing automatic cancellation failure remains retained without retry or observation.
