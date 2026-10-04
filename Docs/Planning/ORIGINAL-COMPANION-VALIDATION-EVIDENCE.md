# Original companion semantic validation
Version: 0.1. Date: 2026-10-04. Scope: D-101 / R-059 / Slice 049.
Status: generated development verification, ordinary app regression and optimized
bundle/signature checks passed. No native archive/import/conversion admission.

## What the result establishes

The read-only development checker rereads the actual version-zero component files
against an independently supplied original source. It opens an exact package set,
checks actual byte counts/hashes, independently walks bounded EBML structure to locate
the selected original video TrackEntry, and compares its payload and hvcC to disk
components. A fresh trusted Rust reader source audit must match the stored ordered
audit. Every RPU index entry must identify that fresh packet/NAL/PTS/payload observation;
the exact original escaped payload and delimiter must match the archive at contiguous
offsets. Complete mode additionally requires the entire retained container to match
the supplied source content identity. Repairing a component hash does not repair a
wrong configuration, reference, timeline or payload relationship.

Packet/RPU order is retained without sorting or deduplication. Negative, repeated and
nonmonotonic timestamps and multiple RPUs in one packet are valid archival observations.
The separate decoded-frame reference's unique-PTS/one-RPU-per-frame rule is intentionally
not applied. No decoder runs in this new checker; it cannot qualify decoded frames,
base/enhancement pairing, residual reconstruction, picture statistics or playback.
Fresh libdovi summaries are recomputed by the trusted reader, not a second independent
Dolby metadata algorithm. The independent mechanism here is disk/source relationship
verification and a separate bounded EBML configuration-location walk.

The original producer manifest is not rewritten. Its source_path_identity_bound=false
and decoded_frame_association=not-established remain intact. Separate verifier output
reports original_components_match_source and source_identity_checked_at_boundaries,
with immutable_snapshot=false and stable_importer=false. No flag enables native
import, export or conversion. Metadata-only still omits original BL/EL pictures and
outside-track metadata; full mode still has original source-sized storage and retains
embedded names/metadata/other streams. Those consequences need future native review.

## Ownership, bounds and failure behavior

Source and package components use no-follow, nonblocking regular-file opens; package
entries are opened relative to a pinned directory descriptor and must have one link.
Exact known component membership excludes untrusted executable/path selection. The
manifest has a strict version/field set, duplicate-key rejection and bounded integer/
digest/type checks. Comparisons preserve JSON numeric/boolean distinctions. The source
is hashed before and after verification; descriptor/path identity, every actual package
file's content/identity and directory membership/identity are checked again.

These are observed boundaries, not immutable snapshots, ancestor-path sandboxing,
cryptographic authenticity or protection against a same-user adversarial writer.
The helper is explicitly operator-supplied trusted development tooling, never supplied
by the package. Native work must pin its own bundled helper and process/resource policy.
All failures leave the source/package untouched; CLI diagnostics omit private paths.

Hash reads stream in 1 MiB chunks. Source/full container are bounded at 1 TiB, track/
configuration/manifest 1 MiB each, RPU/index 512 MiB each, audit 1 GiB, JSON row 64 KiB,
packet/RPU count 2 million. The independent EBML walk bounds child counts and track
payloads. The Rust helper retains its existing 64 MiB heap policy; this is not a whole-
process or full-file time guarantee. A new 120-second generated-development helper
deadline kills the owned group; refusal/interruption closes pipes and joins the direct
child before returning. Historical native timing assertions/deadlines are unchanged.

The first generated run refused invalid components but exposed subprocess/pipe cleanup
warnings: Darwin could refuse signaling a fast, already-exited helper group. The final
implementation reaps an exited child, falls back to its owned direct child when live,
and puts close/wait/join cleanup in a finally block. Refusal tests now assert every
started direct child's settled status and closed stdout, not merely an exception.
Final generated run has no resource warnings. Direct children are joined; the generated
pipe-holding descendant test observes termination (an orphan can briefly remain zombie
until the OS reaps it), not a claim that this process can join an unowned descendant.

## Generated checks

Seventeen Python checks run against actual exclusively exported generated Rust producer
packages in both modes. The fixture contains four encoded packets, five RPUs including
a duplicate, signed/repeated/reordered PTS, an invisible packet, supplementary unknown
track metadata, opaque enhancement bytes and another stream. This wire fixture does
not provide valid decoded pictures or enhancement residuals. Existing separate actual
HEVC reference checks retain their own scoped evidence.

Tests cover:

- Both retention modes, unchanged source/package bytes, manifest flags and order.
- Corrupt/missing/extra components, malformed/oversized/duplicate JSON and unknown fields.
- Forged track/configuration, counts/qualification flags, index packet/NAL/timestamp/
  offsets/sizes/hashes and audit flags/summaries/order/completion after hash repair.
- Forged raw RPU/full-container bytes, trailing/partial/missing/reversed/duplicate rows.
- Symlink/hardlink/FIFO/directory components, source/package symlinks and replacements.
- Source mutation/replacement and package file/directory replacement during verification.
- Failed helper with otherwise complete output, malformed/incomplete/unknown rows,
  bounded timeout, pipe-holding descendant and interruption with owned cleanup.
- Generic CLI refusal without private source/package paths in diagnostics.

Final generated companion suite passed 17 checks in 2.025 s. All 24 Rust tests,
format and warnings-as-errors Clippy passed; the 15 existing generated software-decoder
reference checks passed in 1.660 s. Existing reader CI now includes the new generated
checks; no separate workflow, dependency, native helper command or protocol changes.

## Remaining qualification

The validator is standalone development tooling. Native producer/source descriptor
ownership, cancellation, settled output validation and D-099 exclusive publication
integration remain open. So do stable archive/import migration, native storage/privacy
review, ENOSPC/volume/crash recovery and signed distribution. Original preservation,
compatible conversion, edited-picture statistics and enhancement reconstruction remain
different contracts. No owner archive/queue/encode/listening, decoder bundling, signing
retry, native UI walkthrough, merge or release is performed by this unit.

PR 75 automatic reader passed in 1m37s. Its automatic app run failed the existing AV1
120-second deadline at 140.150 s; all 331 tests finished in 519.513 s with one issue
and preview packaging skipped. Failure log is retained privately; no rerun, new timing
observer, deadline/assertion relaxation or causal claim follows. Local checks below
remain separate from automatic hosted acceptance.


Ordinary app regression passed 331 tests/78 suites in 202.422 s with unchanged default
scheduling/assertions and existing opt-in skips. Optimized build.command and strict
ad-hoc outer app/existing helper signatures passed; actual Mach-O minima remain
macOS 14.0/11.0. These are declarations, not execution qualification on older hardware
or hardened Developer ID loading/notarization. Native UI/controller/session/CLI protocol
are unchanged; no owner walkthrough or heard VoiceOver result is claimed.

Final privacy scan covers twelve changed/nonignored-untracked repository files against
three exact private owner source path/name/stem patterns: zero matches and a positive
private sentinel. Ignored binaries, private receipts and owner media are excluded;
this establishes scoped identifier absence, not general privacy certification. Original
source descriptor and current recovery journal bytes remain exact. Planning audit
findings are empty. No owner queue, archive or encode was executed.
