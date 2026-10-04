# Companion writer development process evidence

Date: 2026-10-04. R-059 / Slice 049 / D-104. Generated development executable/process
qualification; the native bundled helper stays read-only and no archive action is added.

## Contract and trust boundaries

The future owner chooses retention and reviews metadata-only picture/information losses,
full-source storage and retained embedded metadata/names. A caller owns its stage and
active writer. Complete-looking files or a protocol row cannot replace successful
process settlement, disk and semantic admission. This unit exercises generated files
only; original media, recovery and previous outputs stay protected.

Cargo's optional development-companion-writer feature enables a separate executable;
default builds and the existing bundle's fixed copy still select only the reader.
No dependencies or reader commands/protocol changed. The new binary uses the same
64 MiB tracked Rust allocator and disables core dumps. That is a Rust allocation bound,
not whole-process memory or physical I/O qualification. Runtime diagnostics and panic
hook omit input names/paths/payloads. This executable is unbundled and not signed as a
native writer. Only macOS execution is exercised; Linux/other-platform use is unqualified.

The executable accepts only metadata/full, explicit source/stage paths, a 32 lowercase
hex operation correlation ID and bounded decimal source/stage device/inode IDs.
It emits a ready row before any source reads or stage writes, then requires exactly
start plus that operation ID and newline followed by EOF. Control input is limited to
41 bytes. The handshake is controller synchronization, not an owner approval screen
or authentication secret. It has no automatic fixture pause hook or ambient fallback.

D-103 pins the actual stage and compares its captured file ID before component creation.
D-102 compares the opened source file ID before source component writes. Thus replacing
a path after readiness cannot direct writes into a different stage or source version
without refusal. A source mismatch may leave empty exclusive stage components. File IDs
are narrower than immutable content/version identity; existing content and descriptor/
path rechecks still apply. No source path or import identity is stored in the manifest.

The writer emits a single staged JSON row after concrete writers and verification read
handles settle. It includes the correlated operation, retention, checked source/stage
IDs, source size/digest/counts, fixed-name actual component receipts, heap limit/peak
and semantic_verification false. Every emitted row is limited to 16 KiB. The caller
requires complete output and exit zero; writer refusal/abort cannot become completion
from a partially written manifest or prior row. Version-zero manifest remains unbound.
This is a temporary development process result, not a stable persisted archive format.

The explicit trusted Python caller opens/pins source/stage before launch, verifies
empty owned0700 stage membership, passes captured IDs directly without shell use,
strictly checks ready/staged schema, integer types/counts/limits, operation and retention,
requires EOF/exit zero, then rereads actual single-link0600 components against receipts.
It retains read descriptors through final membership/path/descriptor/source checks.
Disk hashing uses one MiB chunks with cancellation checks before/after physical reads.
Independent semantic validation remains separate, including source digest and original
track/configuration/packet/index/raw-RPU relationships and optional full-container bytes.
Hash and identity receipts alone do not establish those semantics.

Cancellation/deadline monitor terminates the caller-owned process group; all return/
exception paths serialize disarming/reaping with monitor signals, stop the monitor,
close stdin/stdout and wait for the direct child. A cancelled operation refuses even after valid child exit.
Cross-process interruption is termination, not delivery to the library's cooperative
Cancellation token. Partial files remain with the trusted caller; no cleanup/publication
is automatic. Caller may clean up only after the process/worker settles. The monitor's
120-second development process bound does not cover later physical disk/semantic reads,
and cannot preempt uninterruptible physical I/O. Orphan descendants are terminated by
group ownership where supported; only direct children can be portably joined here.

The executable path is explicitly supplied by the operator. It is never selected by
an archive or downloaded at runtime. Native fixed provenance/signature, security-scope
leases, process/resource policy and result-review integration remain unqualified. Source/
stage observations are not an ancestor sandbox, immutable snapshot, authenticity or
same-user adversarial race guarantee. No fsync/crash/volume/ENOSPC claim follows.

## Generated verification

Eleven Python process checks exercise real generated source/stage/executable files:

- Both modes return checked stage receipts and pass independent semantic verification
  while original/package bytes and unbound manifest flags remain unchanged.
- Invalid argument counts, IDs, retention and malformed/oversize/EOF start frames
  refuse without source reads/stage writes; diagnostics do not expose private paths.
- Initial unsafe/nonempty stages and symlink source refuse without child launch.
  Actual source/stage replacements after ready fail captured-ID checks before source
  component writes; old bytes/stages remain intact.
- Real writer waiting for start is cancelled, interrupted or expired; child is joined
  and pipes closed before caller cleanup. Pre-cancel launches no child.
- Cancellation after valid process exit and during an actual parent disk read refuses
  receipt admission even when a manifest/package is already present.
- Malformed, duplicate, oversized, stale/unknown/forged component/identity/heap receipts,
  nonzero exit and trailing output refuse and settle children. Generated surrogate
  processes wrap the actual writer to alter output; no surrogate can select file paths
  from a manifest. No admission rule/deadline is relaxed to make these cases pass.
- A generated exited direct child leaves a descendant holding stdout; deadline kills
  the owned group, joins the direct child and closes pipes. A transient orphan zombie
  awaiting the OS reaper is distinguished from a live sleeper; orphan join is not claimed.

One additional Rust actual-file test checks expected source/stage IDs before writes.
Existing generated core cancellation/read/seek/write/flush and source/stage fault tests
remain active. This process unit directly observes ready-wait cancellation and late
result refusal; it does not claim termination while a physical full-container write is
blocked. That and native worker/controller/resource policies remain integration gates.
Wire fixture has one packet/two duplicate RPUs and opaque enhancement bytes, not decoded
pictures or EL residual reconstruction. Original retention semantics stay separate from
compatible conversion, edited-picture statistics and enhancement reconstruction.

All-feature Rust passed 40 tests with zero failures/ignored; format and warnings-as-errors
Clippy passed. Python writer suite passed 11 checks in 2.338 s; independent companion
suite passed 19 checks in 14.369 s; existing decoder-reference suite passed 15 checks
in 1.216 s, without resource warnings. Default fixture exports/build also exercised
unchanged read-only helper behavior. Reader CI now includes the optional writer test/
lint targets and its process suite, without changing ordinary app scheduling/limits.

Ordinary app regression passed 331 tests/78 suites in 204.552 s with default scheduling/
assertions and existing opt-in skips. Optimized build and strict ad-hoc app/helper
signatures passed; actual minimum declarations remain 14.0/11.0. The development writer
is absent from the native bundle. No older-OS runtime/hardened/notarization proof follows.
Final owner/privacy/planning settlement is recorded below.

Review found that a monitor could remain armed during direct-child wait/reaping. The
caller now serializes polling/reaping and monitor disarm with cancellation signals,
then joins the monitor before final cleanup. A generated child closes stdout but remains
alive; EOF is insufficient for success and the process still expires and settles.
The expanded final process suite passed without weakening admission or timing assertions.

| Claim | Kind / confidence | Evidence and scope |
| --- | --- | --- |
| Writer refuses wrong captured file IDs before source writes | configured_behavior / verified; observed_behavior / verified for generated cases | Expected-ID Rust test and actual post-ready replacement checks; IDs are not immutable content identities |
| Caller refuses cancelled, malformed or nonzero process results | observed_behavior / verified for generated cases | Eleven process tests, direct-child/pipe closure assertions and disk-read cancellation; physical copy interruption remains unknown |
| Writer is absent from default native bundle | source_fact / verified; observed_behavior / verified | Required Cargo feature, unchanged fixed packaging copy and final bundle check; does not qualify future packaging |
| Native archive completion is ready | unknown | No native caller/lease/resource policy, semantic/publication integration, review, stable importer or distribution qualification |
No new native UI behavior, heard VoiceOver or owner walkthrough claim follows.

## Remaining acceptance

Next bounded prerequisite: join writer execution with independent semantic settlement
and exclusive result-set publication in generated development/native ownership scope.
Keep result review truthful about metadata-only BL/EL/outside-track loss and complete
source-sized original retention including embedded metadata/names. Stable archive/import,
persisted producer execution binding, active physical-copy cancellation, storage/crash,
native signing/resource/lease policy and decoded association remain separate gates.
D-097 complete-source 120,552 association proof is retained without repetition; decoder
candidate remains unbundled. Interrupted Developer ID signing stays retained; no retry.
No owner queue/archive/full-film encode, listening, merge or release occurs.

PR 78 reader passed in 1m51s. Its automatic app run failed the unchanged AV1 matrix
120-second deadline, settling in 132.370 s; 331 tests finished in 543.636 s with one issue,
preview packaging skipped. Private log retained and PR updated. No rerun, historical
observer or assertion/deadline change; prior failure causes remain unknown. D-090 remains
completed rather than reopening its timing investigation through this process unit.

Final source descriptor/current recovery bytes are unchanged. Privacy scan of 17
changed/nonignored-untracked repository files for three exact owner path/name/stem
identifiers has zero matches and a positive private sentinel. Ignored binaries/private
receipts/owner media are excluded; this is scoped absence, not general certification.
Planning audit has no findings.
