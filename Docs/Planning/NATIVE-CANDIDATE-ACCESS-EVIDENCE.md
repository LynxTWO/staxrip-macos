# Source and candidate access for native read-only review

Date: 2026-10-04
Decision: D-120
Requirement: R-059 / Slice049
Status: unused concrete native prerequisite; generated qualification

## Contract

CompanionArchiveOperation.reviewCandidate takes explicit original source, candidate folder,
retention and the fixed trusted metadata reader. It reuses the concrete D116 access/pins,
activity and process-local exclusion registry with D119 read-only source-dependent review.
Only source and candidate URLs are offered to Foundation security-scope acquisition. The
candidate folder grant does not confer its parent grant. False acquisition on ordinary
unsandboxed URLs is not denied access: actual no-follow source/file and candidate/directory
descriptors must open and match their paths before activity starts. Source size remains
bounded to1TiB. D119 then requires private0700 candidate and fixed regular0600 single-link
members, bounded reads, complete D109-D114 original reconstruction and final observations.

Source and candidate pins/grants stay held while the dedicated native disk worker and
actual owned metadata helper read. Normal success, semantic refusal and settled cancellation
close descriptors and balance granted scopes in reverse order, then end activity. Fresh
metadata equality is source-dependent evidence, not producer provenance, immutable snapshot,
portable/stable import, independent libdovi implementation, every-field interpretation or
decoded picture/edit association. No release tool capability or archive interface is added.

Shared executing/review exclusion prevents a preservation operation or another review
while access is held. A typed CompanionUnsettledOwnership refusal retains source/candidate
pins/scopes and a locator in the existing registry, even when the thrown error is dropped.
Loss of the outer source/candidate path/descriptor observations also retains review rather
than treating those locators as still admitted. Changed component content with unchanged
outer identities is an ordinary read-only refusal after the native worker settles.
The bounded additional activity expiry ends only energy, never access or review. No
production recovery-release API exists; DEBUG release is limited to controlled generated
settled tests. A locator is not deletion, adoption, access-release or publication authority.

## Generated checks

Six new tests share the existing serialized concrete-operation suite because the same
process-local registry intentionally admits only one operation. This does not change global
test parallelism or historic timing checks. Actual fixed Rust writer constructs generated
candidates before the reviewed operation; only the owned native reader executes during
review. Both retention modes undergo complete native original semantic admission. Source,
candidate and unrelated prior-output bytes remain unchanged. Captured fake scope requests
are exactly source/candidate and stops exactly candidate/source; pins retain descriptor IDs
through helper launch/join. Actual direct-child joins are confirmed with ECHILD.

Tests also cover second acquisition rollback, pre-cancellation, missing/incorrect descriptor
types, real POSIX source-read/candidate-directory permission denial, plausible compact
metadata forgery with repaired hashes requiring joined fresh-reader refusal, live cancellation
and conflict exclusion, controlled dropped-error retention after activity expiry, and actual
final candidate-directory substitution after reader join. The original directory remains
pinned and intact; no candidate is created, changed or removed by the review operation.

The live-reader test observes the actual current-PID OS PreventUserIdleSystemSleep assertion
with the review reason and verifies absence after settlement. ExportActivity still permits
screen/manual locking. Fake positive scope balancing is not actual sandbox extension grant
or revocation qualification. The acquisition denial test uses real chmod/open refusal;
restores only its own generated fixture permissions before test cleanup.

Cancellation preserves the existing typed native group-EPERM/direct-child-joined refusal
when observed. Such a generated candidate is retained outside Git. DEBUG registry isolation
after fixed-child join does not establish group settlement or authorize candidate cleanup.
Controlled markers are explicit injected evidence, not actual OS signal-denial repair.

## Remaining gates

The archive version-zero schema and source Matroska/HEVC subset remain unchanged. No MP4/AV1
parser, release helper factory, writer packaging, recovery UI, stage creation, publication,
delete/adoption/republication or directory discovery is added. Positive Developer ID admission
and loading are still open; prior D097/D117 interrupted signing artifacts remain retained
without retry. Actual sandbox grants, production retained-review release/recovery, owner
mode/loss/storage/privacy review, volume loss/blocked I/O and power durability remain open.
Physical I/O, parser/consumer/wait work cannot be preempted and universal escaped-descendant
settlement is not claimed. Source and helper filesystem observations are not hostile same-user
or immutable execution guarantees.

Metadata-only retains selected TrackEntry/hvcC/escaped RPUs/signed encoded associations and
selected embedded names/metadata, excluding BL/EL pictures and outside-track information.
Entire-container retains the whole original including other streams/names/metadata with
source-sized storage/privacy. Neither mode is edited-picture conversion qualification.

## Qualification

Focused14tests/1suite4.989s and ordinary451reported tests/93suites210.803s passed without
warnings, with26 unchanged opt-in skips. Expanded access suite17.603s passed ordinary.
Explicit STAXRIP_CONFIGURATION=release production build and strict ad-hoc app/read-only
helper signature checks passed without warnings; minima14.0/11.0 and writer absent.
Seven-file privacy scan has zero matches/positive sentinel; owner source metadata/current
recovery journal remain unchanged and planning findings are empty. This backend is unused,
so no UI walkthrough or production completion is inferred.
PR94 automatic37217896269 failed445reported tests734.974s47issues:17existing60s,25existing120s,
2existing180s deadline issues and3motion expectations. Candidate suite313.611s/access
suite320.415s passed; preview skipped. Log retained and PR updated without retry, causal
claim, historic observer, assertion/deadline or scheduling change. D090 causes remain unknown.
