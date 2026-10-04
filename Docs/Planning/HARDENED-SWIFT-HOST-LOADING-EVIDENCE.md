# Hardened Swift host/test-module loading discriminator

Date: 2026-10-04
Decision: D-122
Requirement: R-059 / Slice049
Status: generated concrete loading refusal; no positive native-host qualification

## Owned copies and constraints

D121's sealed Rust reader-host does not establish Swift host or test-module loading.
Local inspection found the installed SwiftPM testing host has get-task-allow and the
compiled test module links XCTest/Testing SDK frameworks. This test copies both into an
owned generated bundle with D121's fixed hardened reader/writer helpers and notices.
Original installed host and compiled module hashes are checked before/after and unchanged.
No original tool, product source, app startup, default Preview or owner session is modified.

The copied host's old signature is removed, eliminating its original entitlement, then
explicit ad-hoc runtime signing supplies no entitlements. The copied test module's original
signature is removed; its rpath includes the explicit framework directory from the selected
installed Xcode developer location, then it is signed ad-hoc with runtime and no entitlements.
No SDK binary is redistributed or copied. The outer bundle is signed after these owned edits.
Native Security strict/nested/all-architecture validity, fixed identities, runtime/ad-hoc
flags and absent entitlements/Team are required. D117 fixed helper-role admission is separate.
DYLD overrides are omitted from child environment. HOME/CODEX_HOME are never repurposed.
There is no library-validation disablement, widened entitlement or unsigned fallback.

The selected test-only entry would execute actual D116 preservation and D120 read-only review
for both modes, require six helper direct-child joins and source/prior preservation, then
write one bounded exclusive completion record. This is not a runtime bridge, importer,
producer provenance or recovery journal. That entry did NOT run in the actual observations.
No positive source-dependent semantics or actual helper execution follows from this unit.

## Sole caller and actual refusal

One POSIX caller owns the exact spawned PID/group and waitpid. It uses null stdin and an
owned regular log, checks a configured20-second entry bound and1MiB observed log bound, and
confirms ECHILD before reading the settled result. Configured bounds cannot preempt physical
I/O or guarantee a hard file-size cap between polls. Timeout/log overflow is failed uncertain
qualification with retained fixture; it never becomes expected loading refusal or cleanup.
Only an unreaped owned group/PID may be stopped. Universal orphan/descendant settlement is
not claimed. Ordinary classified refusal retains the exact copied signed artifacts and log.

The copied hardened Swift host started and its loader refused the copied test module:
“mapping process and mapped file (non-platform) have different Team IDs”. The installed
host's source signature and compiled module remain unchanged. The copied host/module outer
and nested signatures still validate with runtime flags, no entitlements and no Team.
The host is joined/reaped. No entry or completion marker exists, destination contains only
its original prior file, and source/prior bytes and root/destination identities are unchanged.
No native archive operation, worker, Rust producer or metadata reader was invoked by the entry.

This is a concrete dynamic test-module/library team refusal. It does not establish that
statically linked native app code fails, that SwiftUI loading fails, or that whole-program
work is blocked. A separately compiled statically linked native qualification host is a
useful next discriminator; it must keep runtime validation and entitlements intact.
The selected harness additionally recognizes a narrowly diagnosed missing XCTest/Testing
SDK dependency as a distinct refusal, not native success. No missing-SDK case was observed
locally. Unknown crashes, ordinary test failures, partial entry or timeouts fail and retain
review; no arbitrary nonzero exit is accepted.

## Retained new fixture failures

Initial compilation exposed actor isolation and two throwing-hash expressions in test
assertions. MainActor caller ownership and separate explicit hash assertions corrected
those without product changes. The first actual loading run failed classification because
its predicate expected “no Team ID” rather than the actual “different Team IDs” diagnostic.
Its signed fixture/log remain retained. The predicate now recognizes that concrete existing
library-validation message; this changes only the new fixture discriminator, not D090 or
historical assertions/deadlines. The corrected focused1test/1suite1.216s passed by confirming
the refusal, not by loading native code.

The final test rechecks outer/module/original hashes and helper-role admission before any
possible parent-side helper dispatch. These checks were moved ahead of result handling after
the ordinary run began; final focused qualification covers that exact test-only sequencing.
The native-success branch remains unexercised, with no positive loading or lifecycle claim.

## Product and remaining gates

Product sources, default Preview and writer packaging remain unchanged. Reuse the D120
explicit optimized product build receipt; current strict ad-hoc app/read-only helper
signatures are checked separately. Ad-hoc is not Developer ID or notarization, and the
shipping preview is not made a hardened release by this fixture. D097/D117 interrupted
Developer ID attempts remain retained without retry or presumed prompt/network cause.

Actual sandbox grants, production retained-review recovery/release, owner retention-mode
loss/storage/privacy review, stable import/execution binding, decoded/edit association and
power/volume/blocked-I/O durability remain open. Version-zero source-dependent archive
semantics are unchanged. Metadata-only excludes BL/EL pictures/outside-track information;
entire-container retains whole source-sized data/all embedded streams/names/metadata.
Preservation, compatible conversion, edited-picture statistics, enhancement reconstruction
and archival remain separate qualified choices. No owner media body, queue, film archive/
encode, listening, merge or release occurs.

PR96 automatic37221710621 failed454reported tests732.817s27issues:16existing60-second and
10existing120-second deadline issues plus a mastering cancellation phase observer saw EOF.
Signature suite434.771s and access435.537s passed; preview skipped/no reader workflow. Log
retained/PR96 updated without retry, causal claim, historical observer, assertion/deadline
or scheduling changes. D090 historic timing and the phase expectation cause remain unknown.
Ordinary455reported tests/94suites208.327s passed with26unchanged opt-in skips and no
new warnings. Final focused1test/1suite1.300s passed without warnings after moving the
common post-join admission checks ahead of any possible parent helper dispatch. Both runs
classified the same concrete team-loading refusal; neither executed the native entry.
Current strict ad-hoc app/read-only helper signatures pass, deployment minima14.0/11.0,
writer absent; the unchanged explicit optimized product build is reused from D120.

Next qualify a separately compiled statically linked Swift native host using the concrete
production source closure and fixed generated helpers. Keep the entry test-only, exclusively
owned, hardened/no-entitlements and independent of XCTest/plugin loading, app startup and
owner session. Actual operations, cancellation, helper/host settlement and source/prior
preservation must be established there; this refusal gives no positive evidence for them.
No validation bypass, unsigned fallback or blind Developer ID retry is authorized.

Final five-file privacy scan has zero private source path/name/stem matches and a
positive sentinel. Owner source metadata/current recovery journal remain unchanged;
full planning findings empty. Current owned84530 bounded awake assertion exact command/
start matches receipt and expires19:37UTC; no persistent locking/security changes.
