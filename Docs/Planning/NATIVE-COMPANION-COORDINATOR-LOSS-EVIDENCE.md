# Native companion coordinator loss qualification

Date: 2026-10-04
Decision: D-118
Requirement: R-059 / Slice 049
Status: generated process-loss qualification, not production recovery

## Boundary and authority

The owner delegated autonomous generated non-audio development. This unit tests actual
D105 source-dependent companion production/verification and D099 exclusive publication
when a separate native coordinator disappears. Product sources are unchanged. No app
archive action, persistent recovery record, importer, adoption or deletion API is added.
Original media, session, current recovery journal and previous outputs are protected.
Generated files only; no mounted image, owner volume, queue or signing retry.

Before the exclusive rename, the publisher has already read and hashed all components,
and the writer and full native metadata verifier have returned after their helper joins.
After the rename, a successful filesystem operation exists even if no receipt reaches
the caller. A stopped coordinator cannot run D105's catch/discard path. These are the
concrete observations this test establishes. It does not model a failed storage device,
power loss or a coordinator disappearing while another helper still writes.

## Actual native checks

`CompanionCoordinatorLossTests` reexecutes the current Swift Testing helper with only
this test selected. This is test instrumentation, absent from the application product.
The generated Rust writer and reader use an isolated Cargo target. The child runs the
actual native D105 transaction, writer process, full D114 semantic composition and D099
publisher. Fixed generated executable digests are DEBUG trust, not release provenance.

Both metadata-only and entire-container modes exercise both commit boundaries. Writer
and reader launch/settlement hooks record their direct child IDs. The stopped coordinator
checks `waitpid` returns ECHILD for each before announcing readiness. Its bounded frame
contains the operation's source/component observations and stage identity. A separate
closed-file announcement prevents reading a partly written frame. The parent pins the
surviving directory before granting one finite byte. The child then calls POSIX _exit86 on
itself, without Swift unwinding, defer handlers or a returned transaction receipt. The parent never sends a signal to a frame-selected PID.

One POSIX caller owns coordinator spawn and waitpid. It inherits the trusted test-runner
library environment, sets only generated fixture inputs, closes unneeded descriptors
and uses a regular owned log. No Foundation reaper competes with it. Parent readiness
and exit waits have a configured20-second bound; physical I/O and helper execution are
not preempted by that bound. Missing readiness/settlement retains the generated fixture
for review. This is not a generic arbitrary-program supervision guarantee.

The four observed cases require:

- Coordinator immediate exit86 reaped by its one owner, then ECHILD on a second wait.
- Root, destination parent and pinned surviving stage/result identities remain equal.
- Precommit destination absent, original stage retained with only prior output beside it.
- Postcommit original stage absent, result present with only prior output beside it.
- Original generated source and prior output bytes unchanged.
- A new actual owned reader plus full native source-dependent semantic check of every
  surviving archive. Entire-container bytes also equal the generated source.

The parent performs read-only checks. It neither resumes publication nor marks a
persistent operation complete. The frame is trusted test instrumentation, not a recovery
journal, signed producer receipt or an input format for the app. The existing independent
source/component checks determine semantics; the frame alone does not establish them.
Only successful generated fixture ownership/joins/assertions authorize test cleanup.

## Failures retained and correction

Initial four cases passed11.347s, with a test-only local function Sendable warning.
The function was marked Sendable and readiness was changed to announce a closed frame.
That run stalled in Foundation `waitUntilExit` after its child was already absent. A
one-second sample of this new fixture identifies that stack. This diagnostic is scoped
to the new fixture; it does not explain D090 historical hosted timing failures.

The exact owned stalled runner command/start/parent relationship and absence of live
direct children were observed before stopping it. The outer Swift invocation completed
with failure; the generated fixture and private interruption/sample logs remain retained.
No orphan join or successful cleanup is claimed for that failed run. No owner process,
media, output, stage, device or signing artifact was stopped or removed.

The corrected POSIX caller first passed four SIGKILL cases in one test/one suite1.617s.
Ordinary439reported tests/92suites206.791s then failed one new fixture case: raise returned
and the generated child threw instead of disappearing. Its cause is unknown. That child
ran ordinary D105 cleanup, so it is not abrupt-loss proof. Its generated fixture and child
log remain retained; all other ordinary tests completed, with26 unchanged opt-in skips.

The final specification uses POSIX _exit86 for every case, not a silent success fallback.
That operation bypasses Swift/defer/atexit cleanup at the selected native worker boundary.
The owned parent requires normal exit86, not signal9. It is a process-loss test without a
signal-delivery claim. Four cases passed in one test/one suite1.800s with no new warnings.
No historical assertion/deadline, global scheduling or product behavior changes.
Discovery failures for the local test helper's bundle path/framework loading are retained;
they were corrected before the four-case run, not treated as validation of the app.
Ordinary regression and final protection/planning checks follow in the decision outcome.

## Coverage limits and remaining work

This proves process-loss behavior on the current Mac filesystem/runtime. It does not
prove directory fsync, durable journal ordering, power-loss survival, volume removal,
blocked I/O, hostile same-user race resistance or portable descendant supervision.
No forced image detach, storage policy change or assertion relaxation occurred.

D114's source-dependent version-zero archive verification remains required. It is not a
portable importer, immutable source snapshot, persisted execution binding, independent
libdovi implementation, every-field decoder or decoded/edited picture association.
Metadata-only excludes BL/EL pictures and outside-track information; it retains selected
embedded names/metadata. Entire-container retains all original streams/names/metadata
with source-sized storage. Owner losses/storage/privacy review remains required.

D116's retained access registry has no production recovery-release API. Losing its
process also loses its in-memory review state; this test does not solve that obligation.
Static helper signature checks from D117 do not establish successful DeveloperID signing,
live release execution, outer bundle authenticity or notarization. Packaging, release
capability, actual sandbox grants and owner review remain gates before an archive action.

## Final regression and protection

Ordinary439reported tests/92suites207.798s passed, with26 unchanged opt-in skips and no
new warnings. The four-case loss suite passed4.577s within ordinary. Product sources
remain unchanged since D117; its explicit optimized build is reused. Current strict
ad-hoc app/read-only helper signatures pass, writer absent. Five candidate files have
zero private source path/name/stem matches with a positive sentinel. Original source
metadata/current journal remain unchanged and planning findings are empty. No owner
media body, queue, film archive/encode/listening, merge or release was performed.

PR92 automatic app37214474279 failed16 unchanged timing checks438tests618.883s; its new
signature suite passed246.881s. Failure log retained and PR updated without retry. No
reader workflow was triggered, preview packaging skipped. D090 causes remain unknown.
