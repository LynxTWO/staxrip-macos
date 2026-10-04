# Source-bound cancellable companion producer core
Version: 0.1. Date: 2026-10-04. Scope: D-102 / R-059 / Slice 049.
Status: generated source/ownership/cancellation, semantic checks, ordinary app
regression and development bundle/signature checks passed.
No native archive command, stable importer or HDR conversion is admitted.

## Contract and source map

The future owner chooses original metadata-only or complete retention and reviews
storage/privacy consequences. This prerequisite establishes a producer boundary that
owns its active file handles and refuses success when the source changes or a
cancellation request is observed. Actual execution here uses disposable generated
files only. A successful returned SourceBoundReceipt is authoritative; component
presence or an inner audit's complete row is not a source-bound completion.

The new development library entry point is companion_source::produce. It consumes
OwnedComponents containing concrete File handles and an Arc<Cancellation>. It opens
the original path read-only with no-follow/nonblocking/close-on-exec flags and checks
regular-file size plus descriptor/path identity before work. Empty, distinct, single-
link, regular write-only output descriptors at position zero are required. Source
aliases, duplicate/cloned output handles, append/read-write/read-only/nonregular,
nonempty or positioned descriptors refuse before component writes.

Checked wrappers poll the one-way cancellation request before and after read/seek/
write/flush calls. They preserve explicit I/O failure rather than treating it as EOF;
cancelled reads use a non-Interrupted error, avoiding the parser's interrupted-read
retry loop. The existing component producer performs its streamed complete input
audit and content recheck. Descriptor/path identity is checked again before the final
receipt. The separate execution receipt contains an in-memory source identity token,
not a persisted source path or a new import schema. The prototype manifest's original
path flag remains false and decoded mapping remains unestablished.

Owned concrete File handles close at synchronous return, including refusal/unwinding;
there is no retained producer task, subprocess or buffered writer that can flush later.
The caller must join its worker before deleting staging. A request arriving after the
last receipt check does not revoke already completed work. Cancellation is cooperative:
it cannot preempt blocked physical filesystem I/O or parser CPU and has no native
wall-clock guarantee. Incomplete components may remain; this function never deletes
files, publishes a directory or writes a manifest on failure.

## Trust and coverage limits

Caller-created staged File handles are trusted input. Descriptor checks cannot prove
exclusive creation history or bind output pathnames. The caller must exclusively
create files inside an operation-owned stage, settle this producer, independently
validate disk component semantics/path identity, then use D-099 publication. A malicious
caller can clone descriptors before handing them over; ownership cannot undo that or
restore a source the caller already truncated. No such caller is added to the app.

Source checks are before/after observations, not an immutable snapshot, ancestor-path
sandbox, cryptographic authenticity or same-user adversarial mutation guarantee.
No crash/power-loss durability or archive-specific ENOSPC/other-volume behavior is
qualified. Existing component byte/count limits and raw duplicate-preserving encoded
associations remain unchanged. Metadata-only omits BL/EL pictures and outside-track
data; complete mode retains the entire source-sized original container and embedded
names/metadata. No decoded association, enhancement reconstruction, future carriage,
picture-edit statistics or playback evidence follows.

The native helper still accepts only its three read-only audit commands. No CLI
arguments/protocol, app/session/controller/UI, dependency, native process/resource
policy or decoder bundling changed. A private no-op callback boundary enables
deterministic generated final-source/cancel fault injection; ordinary callers cannot
select a callback, bypass checks or force a receipt. This is unrelated to D-090's
completed historical timing investigation.

## Generated evidence

Seven Rust functions test actual source/component files and cancellation wrappers:

- Both retention modes retain original bytes, negative PTS, two identical RPUs in one
  encoded packet, supplementary original track data and opaque enhancement bytes.
  Source descriptor/content remain unchanged; owned component descriptors are closed
  at return. A reused descriptor number from another parallel test is distinguished
  by file identity rather than falsely treated as an operation leak.
- Missing/symlink/FIFO/directory/empty/oversize sources refuse before component writes.
  Malformed input may stage raw bytes in complete mode before parser refusal; those
  partial bytes remain unpublished and no manifest/source-bound receipt exists.
- Source aliases, cloned output handles, hardlinks, read-only/read-write/directory,
  nonempty, positioned and append descriptors refuse while prior bytes stay intact.
  Exclusive generated output creation also refuses an existing component path.
- Actual path replacement with identical bytes, in-place mutation, symlink replacement,
  removal and a final cancellation request refuse a source-bound receipt even after
  the inner content audit completed. Component files settle before the return.
- Pre-cancellation is one-way, closes owned outputs and writes nothing. A generated
  owned worker pauses at the final boundary, receives cancellation, returns refusal
  and is joined before the caller removes staging. Its controlled channel waits are
  bounded; no historical native observer or assertion/deadline changed.
- Controlled actual read/seek/write/flush operations request cancellation internally.
  The wrapper refuses after those operations as well as before them; partial writes
  remain possible but cannot become receipts. A cancelled fingerprint recheck fails.

The opt-in generated fixture export creates both actual source-bound packages without
overwriting any file. The independent Python verifier accepts both against their
original source, preserving package/source bytes and unmodified manifest flags. This
adds one integration check to its existing seventeen forgery/path/process checks.
The wire fixture has one packet/two RPUs; it is not decodable-picture/EL residual proof.
Existing generated actual HEVC reference coverage remains separate and unchanged.

The initial invalid-source test incorrectly expected malformed full-mode input to leave
every file empty. The raw tee had staged 20 bytes before parsing failed, which is
allowed by the existing partial-component contract. The corrected check asserts those
specific partial bytes, empty unrelated components, settled handles and no manifest/
receipt. No product limit, parser admission or cancellation assertion was relaxed.

Final Rust run passed 31 tests (8 library, 1 main heap, 15 container, 7 archive), with
zero failures/ignored tests; format and warnings-as-errors Clippy passed. The expanded
Python companion suite passed 18 checks in 3.032 s without resource warnings; existing
15 decoded-reference checks passed in 1.107 s. Tests use macOS, Rust 1.98.1 and the
existing FFmpeg development tools. No owner source run or full-film archive/encode.

## Claim disposition and remaining work

| Claim | Kind / confidence | Evidence and limit |
| --- | --- | --- |
| Producer closes consumed component descriptors at return | observed_behavior / verified | Generated actual-file success/refusal/worker checks; excludes deliberately cloned caller descriptors and OS close failures |
| Source path/content changes refuse a returned receipt | observed_behavior / verified | Generated actual final-boundary replacement/mutation/removal checks plus unchanged streamed content recheck; not immutable snapshot |
| Cancellation checks I/O and final receipt boundaries | configured_behavior / verified, observed_behavior / verified for generated cases | Wrapper read/seek/write/flush, pre/final cancel and joined worker tests; physical I/O preemption remains unknown |
| Native archive feature is ready | unknown | No native caller, output pathname binding, semantic/publication integration, storage/privacy review, volume/crash or distribution qualification |

Next: trusted caller stage/path ownership, native worker/process cancellation, semantic
disk settlement and integration with exclusive result-set publication. Keep original
preservation distinct from transformed Dolby conversion and edited-picture statistics.
No owner queue/recovery/session edit, listening, signing retry, merge or release.

PR 76's automatic app run passed all 331 tests in 427.221 s and preview/icon packaging;
reader passed in 2m29s. Earlier automatic failures remain retained. No rerun or new
timing observer/deadline/assertion change occurred; one successful automatic run does
not explain those failures or establish timing reliability.


Ordinary app regression passed 331 tests/78 suites in 203.087 s with unchanged default
scheduling/assertions and existing opt-in skips. Optimized build.command and strict
ad-hoc app/existing helper signatures passed. Actual Mach-O minimum declarations
remain macOS 14.0/11.0; older-system execution, hardened Developer ID loading and
notarization remain unqualified. No owner walkthrough or heard VoiceOver claim is
made for unchanged native UI behavior.

Final privacy scan covers eleven changed/nonignored-untracked repository files for
three exact private owner source path/name/stem patterns: zero matches with a positive
private sentinel. Ignored binaries/private receipts/owner media are excluded. This is
scoped identifier absence, not general privacy certification. Source descriptor and
current recovery journal bytes remain unchanged. Planning audit has no findings.
