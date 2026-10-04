# Native companion disk settlement evidence

Date: 2026-10-04. R-059 / Slice049 / D-108. Unused internal native integrity checks;
no owner media operation or native archive action.

## Contract

A parsed producer receipt is a claim. Native CompanionDiskCheck independently rereads
source and stage components, verifies actual bytes and identities, and returns a disk
receipt with originalMetadataSemanticsVerified=false. Packet/RPU/enhancement counts are
bounded producer claims; this check does not establish their original relationships.
A later independent native original semantic validator remains required. The prototype
manifest stays version zero/unbound; no immutable snapshot, persisted execution binding,
stable importer or decoded association is inferred.

A one-way cancellation flag and dedicated read worker own all no-follow/CLOEXEC source,
stage and descriptor-relative component handles. Source is a regular1...1TiB file with
expected device/inode and byte count. Stage must be owned0700, exact fixed6/7 membership.
Components are owned0600 regular single-link files with positive receipt-exact size under
D105 retention bounds. All source/component descriptors remain in the operation through
final observations. Source/component SHA256 is recomputed with1MiB pread chunks. Entire-
container mode additionally compares every original-container chunk byte-for-byte against
the original source descriptor, with equal total sizes. No pathname/payload is emitted
in generic errors, and no file write, cleanup or publication occurs in this checker.

Final source/stage/component path and descriptor IDs, type/mode/owner/link count/size and
modification/change times must equal initial observations; stage membership is reread.
These checks are observations, not hostile same-user race proof or immutable snapshots.
Cancellation checks surround chunked reads, hash updates, final observations and async
return. All owned readers unwind before return/throw; physical I/O cannot be preempted.
There is no native volume/blocked-I/O/deadline or crash-durability qualification here.
DEBUG generated progress/final boundaries are new-unit fault fixtures, not D090 historical
failure observers. No existing assertions/deadlines/default suite scheduling changed.

CompanionUnsettledOwnership marks a phase whose ownership is not settled. Native D107
OwnershipFailure conforms. D105 catches that marker before any discard, returning typed
UnsettledPhaseFailure with a stage locator and original error, retaining all stage files
for review. The wrapper also preserves the marker. A locator is not deletion authority.
Normal settled phase errors retain existing owned cleanup. Trusted phases still must join
all workers; the marker does not itself prove process settlement or justify publication.

## Generated checks

Nineteen focused test functions across disk and transaction suites passed4.569s. Actual
native Rust writer runs both retention modes, then native disk verification, independent
Python original-semantic verification explicitly as a test oracle, then native D105/D099
exclusive publication. Native application runtime does not use that Python adapter or
claim a native original semantic validator. Generated source and full original-container
bytes are preserved; original fixture retains duplicate signed packet/RPU associations.

Seven forged receipt cases refuse wrong source/member hash, source/stage ID, invalid count,
incomplete membership and retention mismatch. Six disk faults refuse extra/missing files,
symlink, hardlink, broad mode and changed bytes. Final source/component byte mutations and
stage replacement refuse after hashing. A wrong entire-container copy with a recomputed
self-consistent component digest still refuses exact original-byte comparison. An opaque
integrity-only3MiB append verifies multiple chunks and refuses an altered later chunk
even with a recomputed copy digest; no Matroska semantic claim follows. Pre-cancel,
source-read/component-read and late cancellation refuse successful receipts after worker
settlement, preserving caller stage files. Source and component reads use actual generated
bytes. Cancellation gates qualify cooperative normal-file reads, not blocked kernel I/O.

Transaction faults from both producer and verifier retain stage on native OwnershipFailure.
A separate pending generated worker proves the stage remains present before explicit
caller release/join; test cleanup runs only after joining. This is an injected ownership
contract fault, not an OS group-signal-denial/reap-failure claim. Existing settled-failure
and cancel-wait cleanup, substitution review and late-commit success tests remain active.
Initial test compilation missed a try in a digest expression; fixed before verification.
No product policy or legacy deadline was changed. Existing optional-Bool test macro warnings
in the earlier transaction oracle remain; new oracle unwrapping is explicit.

## Limits and retained state

No app archive action, native original semantic runtime validator, release writer capability,
packaging, security-scope lease/resource/signature admission is installed. Future native
review must disclose that metadata-only preserves original selected TrackEntry/hvcC, escaped
RPUs and signed duplicate-preserving encoded associations but excludes BL/EL pictures and
outside-track information. Entire-container retains the whole byte-for-byte source including
other streams and embedded names/metadata with source-sized storage/privacy consequences.
Original preservation, compatible conversion, edited-picture statistics, enhancement
reconstruction and companion archival remain separate choices. Stable import/persisted binding,
ENOSPC/volume/crash/blocked-I/O and decoded association remain gates. Completed120552 original
source association is retained without repetition; decoder remains unbundled. Interrupted
DeveloperID signing remains retained, no retry. No queue/full-film/archive/listening/merge/release.

PR82 automatic reader37195350536 passed1m41s. App37195350567 failed21 existing120-second
integration deadline cases (chapters2, external captions6, trimmed captions3, ten-bit copy1,
video copy8, AV1 copy1). All355tests finished594.627s with21issues; preview skipped. Native
process suite passed123.267s. Private failed log retained/PR updated; no rerun, observer,
assertion/deadline or scheduling workaround. Causes remain unknown; D090 remains completed.

| Claim | Kind / confidence | Evidence and limit |
| --- | --- | --- |
| Native actual disk/source receipt agreement | observed_behavior / verified on generated fixtures | Both actual writer modes, independent rereads and exact full original bytes; no original metadata semantic claim |
| Unsafe/changed/self-consistent wrong-copy results refuse | observed_behavior / verified on generated fixtures | Forged receipts, link/mode/membership/bytes/final-identity tests; not immutable race proof |
| Unsettled phases retain the stage | source_fact and observed_behavior / verified contract | Shared error marker, producer/verifier and pending generated worker; not actual forced OS signal-denial |
| Production native archival is complete | unknown | Original semantics, review, lease/provenance/resources/signing/import/storage/decoded gates remain |

Consequence local_only generated, future user_data. Method Swift6.4/Swift Testing, fixed
DEBUG generated Rust writer and independent Python test oracle. Process/parser/disk/source/
retention/component/OS contracts invalidate affected evidence if changed. Prior unchanged
Rust/semantic/process/reference receipts are reused, not new executions of their full suites.
Ordinary regression, optimized build, protection/privacy and planning settlement follow below.

Final ordinary365tests/82suites passed205.194s after explicit descriptor lifetime and multichunk qualification. Earlier364-test baseline passed204.365s; it is not reused as the final receipt. No new warnings in the final19-test focused compile; existing older transaction optional-Bool macro warnings were observed separately.

Final optimized development build and strict ad-hoc app/read-only helper signatures passed.
Actual minimum declarations remain14.0/11.0; default bundle excludes writer. No hardened
DeveloperID/notarization/older-OS runtime qualification. Source metadata/current recovery
bytes unchanged. Ten changed/nonignored-untracked public files scanned for three exact
private source path/name/stem patterns: zero matches with a positive private sentinel;
private media/receipts/ignored binaries excluded. Scoped absence, not certification.
Planning audit findings empty. No native UI change or owner session/queue execution.
