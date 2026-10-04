# Relocated sealed generated Rust reader-host bundle

Date: 2026-10-04
Decision: D-121
Requirement: R-059 / Slice049
Status: generated test packaging/execution only; product unchanged

## Concrete host choice

D117 checked individual fixed-role helpers and executed them, but its minimal fixture was
not an outer sealed bundle with complete notices. HardenedReaderBundleFixture creates an
exclusively owned generated app bundle whose main executable is the actual Rust read-only
reader. It includes separately fixed reader/writer helper roles. This qualifies a Rust
reader-host layout, not the SwiftUI app host, a release tool factory or distribution.
No wrapper, app startup change, Python runtime bridge or archive-selected executable is
introduced. Default Preview remains read-only, with no writer bundled or archive action.

The creator copies isolated Cargo-built executables, signs each helper with its fixed D117
identifier, then signs the outer generated bundle ad-hoc with runtime options and a distinct
generated identifier. The outer code-directory hash and main content hash are captured
immediately after this owned signing. It then moves the bundle to an owned folder containing
spaces. Captured trust comes from the generator, not a source/archive or discovered bundle.
Each suite owns its Cargo target; product and existing fixture artifacts are unchanged.

## Seal, roles and notices

Before creating generated process capabilities, native Security checks the outer signature
against the captured hash/identifier using strict, nested-code and all-architecture options.
Actual signing flags require runtime plus ad-hoc, no entitlement blob and no Team. Fixed
helper-role admission independently requires D117 native thin architecture, runtime/no
entitlements, fixed identifier/captured CDHash and pinned file/content observations. Main
content and all notice hashes must still match. No positive Developer ID trust follows.
Static validity is not live authentication, immutable execution or hostile same-user proof.

The fixture copies the repository's product notices, helper license and locked dependency
catalog/texts. Native test code matches trusted Cargo.lock name/version entries exactly to
that catalog and checks each supplied license SHA256. It includes the active Rust toolchain's
MIT/Apache/COPYRIGHT/library-copyright catalog and license directory. All these resources are
captured as hashes before outer signing and must remain identical after relocation/execution.
This is actual supplied-text/catalog integrity, not legal advice or a release compliance claim.

## Actual native execution

The writer capability points to the fixed signed writer helper. The read-only capability
points to the generated bundle's actual Rust main. D107/D113 execute both through their
existing owned native process workers. No launcher wrapper changes their argv or protocol.
The test calls the concrete D116 preservation operation for both retention modes, including
D114 complete source-dependent verification and D099 exclusive publication. It then calls
D120 concrete read-only candidate review on the actual result, again requiring full D119
source-dependent composition. Access pins/activity remain held through observed child joins;
ECHILD checks confirm the direct children are already reaped. Original generated source,
prior output, published candidate and bundle notices remain unchanged. Ordinary Foundation
scope attempts in this test are not sandbox extension grants.

A separate test cancels the actual relocated main during native candidate review. Ordinary
cancellation must join before balanced release. Existing group-EPERM/direct-child-joined
ownership refusal remains typed and retains the fixture/access review where observed.
DEBUG registry isolation after the fixed child's join does not establish group settlement
or permit candidate cleanup. Physical I/O/parser/wait cannot be preempted and universal
escaped-descendant join is not claimed.

The outer resource notice, Info.plist and fixed helper-role substitutions refuse admission
before any process capability is used. The role substitution independently fails D117
role admission. Restoring only the owned exact original bytes restores generated admission.
These tests do not create a production recovery/import/adoption/delete API or authorize it.

## Retained failures and limits

Initial test-only compilation failed on Data/string decoding and nested throwing assertion
expressions. These were corrected by explicit UTF8 decoding and precomputed throwing values;
logs remain outside Git. No product patch, historic timing observer or assertion/deadline/
concurrency workaround follows from these new fixture compile corrections.

PR95 automatic37219515075 failed451reported tests799.399s35issues:19existing60-second and
14existing120-second deadlines, a motion CancellationError/frame-bound message mismatch,
and an FFmpeg cancellation test observing Inspecting instead of Encoding. Access suite
320.347s passed. Log retained/PR95 updated without retry or causal claim; preview skipped.
D090 historic timing causes and these phase/message observation causes remain unknown.

D097/D117 interrupted Developer ID attempts remain retained without retry. This ad-hoc
reader-host fixture does not establish Developer ID admission/notarization, hardened SwiftUI
host loading, actual sandbox grants, release packaging/capabilities, production recovery
release, stable import/provenance/immutable snapshots, every-field independent decoding,
decoded/edit association, blocked-I/O/volume/power durability or owner mode review. Metadata-
only still excludes BL/EL pictures/outside-track information and retains selected names/
metadata. Entire-container still retains the entire original with source-sized storage and
all embedded streams/names/metadata. No owner media body, queue, film archive/encode,
listening, merge or release is performed.

## Qualification

Expanded focused22tests/2suites17.725s passed, including cold isolated Cargo targets;
one redundant nested test-only require warning was subsequently corrected by explicit
code/requirement locals before the Security validity call. Assertions and policy stay intact.
Actual sealed both-mode creation/review12.136s, relocation/substitution13.317s and cancellation
0.383s passed in that focus. Ordinary454reported tests/93suites210.177s passed with26 unchanged opt-in skips and no
new warnings in that cached build; actual sealed both-mode pipeline0.749s, substitutions
2.363s and cancellation0.498s passed ordinary. Final focused checks cover the exact
test-only local-unwrapping correction after this ordinary run. Protection follows below.
The unchanged product's explicit optimized build receipt is reused from D120, not a new
optimized build execution. Its current strict ad-hoc app/read-only helper signatures are
checked independently. No new UI or walkthrough qualification is inferred.

Final focused22tests/2suites5.701s passed without warnings, covering the exact test-only
local-unwrapping correction after ordinary qualification. New hardened reader-host
cancellation settled ordinarily in all runs; its typed retention branch was not newly
observed as an OS group fault. D120's scoped retention evidence stays separate. Current
native architecture/runtime evidence does not establish a separate macOS14 machine run.
Current strict ad-hoc product/read-only helper signatures passed; product minima14.0/11.0
and writer absent. Protection/privacy/planning receipts follow before publication.

Final seven-file privacy scan has zero private source path/name/stem matches and a
positive sentinel. Owner source metadata/current recovery journal remain unchanged;
full planning findings empty. Prior owned55829 was stopped only after exact receipt/
command/start inspection; current owned84530 temporary capped assertion expires19:37UTC
and exact command/start matches receipt. No persistent locking/security changes.
