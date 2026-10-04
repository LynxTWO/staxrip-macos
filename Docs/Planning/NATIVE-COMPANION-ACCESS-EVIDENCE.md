# Native companion access and activity ownership
Date: 2026-10-04. Scope: D-116 / R-059 / Slice 049.

## Concrete operation and authority

CompanionArchiveOperation is an unused internal MainActor entry point joining the actual
fixed native writer, complete source-dependent native semantic verifier and exclusive
D105/D099 publication. Explicit Tool capabilities still have DEBUG development factories
only; no release constructor, writer bundling or archive UI exists. No Python fixture,
untrusted manifest or session chooses a producer/verifier callback. The bridge uses
Foundation security-scoped access and existing ExportActivity, not a new export engine.

It validates file URLs, destination name and cancellation before acquisition, attempts
source then destination-parent access, and opens no-follow/nonblocking/CLOEXEC/NOCTTY
source and parent descriptors. Source must be a regular nonempty file within1TiB; parent
must be a directory. Path/descriptor identity and mode/owner agree; source size/link/
mtime/ctime observations match. Security-scope false on an ordinary URL is not denied
access. Actual descriptor/stage creation failures still refuse. No durable bookmark or
new sandbox entitlement is inferred. Pins check again before native writer and verifier;
D105 source and D099 parent/member observations remain required at exclusive commit.

Successful scope acquisitions end exactly once in reverse order. Descriptor pins,
scopes and temporary idle-system-sleep activity span settled native phase return,
publication and owned stage cleanup. The constant activity reason carries no media name.
Ordinary failure/cancellation balances resources only after the pipeline returns;
post-commit cancellation continues to report actual publication. No scheduling, QoS,
display/lock/manual-sleep or persistent preference change occurs.

## Unsettled review boundary

D105 UnsettledPhaseFailure and CleanupFailure become a typed ReviewFailure with a
process-local ID and intended-stage review locator. A registry retains actual access
closures and descriptor pins even if callers drop the error. Neither the locator nor
retention authorizes deleting any path. The operation admits at most one active run,
and refuses further runs while a review is retained. There is no production release
from review API yet: proving settlement/review remains a prerequisite before archive UI.

The idle-sleep request expires after an additional configured120seconds in review;
source/parent scopes and pins remain retained. Expiry is energy policy, not worker
settlement or cleanup authorization. The main queue must service the timer; this is not
a preemptive wall-clock/power guarantee. DEBUG tests use50milliseconds and a test-only
release for controlled generated phases after independent child settlement. No production
ownership proof follows from that test API or an injected error.

## Generated checks and evidence distinctions

The actual writer/full native verifier/exclusive publication succeeds in metadata-only
and whole-container modes with source protection, fixed membership and exact whole-source
bytes. Writer/reader child launch and joined callbacks plus commit observations see
activity active. Actual fstat file IDs show source/parent descriptors remain pinned at
phase boundaries and after review energy expiry. Existing outputs refuse without changes.

A real native reader is held after launch, allowing independent pmset inspection of the
test PID's named PreventUserIdleSystemSleep assertion. Cancel leaves resources active
until the gate opens and native control settles. The assertion disappears after ordinary
release. This is actual OS activity observation, separate from injected lifecycle counters
and unrelated caffeinate. No forced sleep/lock test or power/platform guarantee is claimed.

Positive scope balancing and second-acquisition rollback use an explicit fake provider;
they do not establish sandbox extension grants or revocation. Actual Foundation calls
and ordinary generated source/parent descriptor checks qualify current unsandboxed access
only. Pre-cancel, nonexistent source and file-as-parent refuse without activity. Actual
non-root POSIX source-read denial refuses before activity, and destination-parent write
denial balances its acquired activity after refused stage creation without launching a
writer. Only owned generated permissions are changed/restored; root skips that case. A real
malformed generated source launches/joins the native writer, refuses, removes its owned
stage and then balances resources while preserving source bytes. Duplicate active starts
and retained-review starts refuse. Actual stage substitution after joined writer retains
both the original stage and replacement for cleanup review, without following/deleting it.

A controlled shared-ownership marker injected before verifier after an actual joined
writer proves dropped-error registry retention and energy expiry. It is not an OS signal
failure. Actual reader cancellation permits only ordinary cancellation or the existing
D113 observed group-EPERM/direct-child-joined marker, propagated into typed review. It
still requires joined direct child, source protection and no destination. It does not
relax D090 historical timing assertions or infer universal descendant settlement.

Final focused/ordinary/build and privacy receipts are appended after execution. Earlier
new test method-reference Sendable conversion warnings were corrected using explicit
Sendable closures; the initial log is retained. No compiler or timing assertion weakened.
Rust41/format/Clippy, independent companion30 and frame-reference15 checks are reused
from unchanged D115 contracts, not reported as newly executed here. The opt-in APFS case
is also reused, not rerun. Owner media bodies/queue/film archives/listening are untouched.

## Limits and next boundary

Original semantic composition is source-dependent prototype verification, not portable
import, immutable snapshots, persisted producer binding, independent libdovi interpretation,
all-field decoding, decoded frame association or crop/resize conversion qualification.
Metadata-only excludes BL/EL pictures and outside-track information while retaining
selected embedded metadata/names. Whole-container retains every original stream/name/
metadata with source-sized storage. Future owner review must disclose those distinctions.

Release executable authentication, hardened packaging/loading, distribution and actual
sandbox grants/revocation remain unqualified. No measured memory/throughput/volume-loss/
crash durability or blocked-I/O guarantee follows from descriptor/activity ownership.
Retained review recovery is not installed. The separate minimal LGPL decoder is unbundled.
No Developer ID retry, owner queue, film archive/encode, merge or release is authorized
by this evidence. Prior hosted runtime timing failure causes remain unknown.


## Local settlement receipts

Final focused26tests/3suites3.807s passed, including actual POSIX permission denials;
new access suite8tests2.522s. Before adding that discriminating denial test, ordinary
432reported tests/90suites208.601s passed with26 opt-in skips, access suite13.954s.
A final ordinary run of the expanded test set is recorded below after it settles.
Earlier focused6tests11.817s compiled the isolated Cargo artifacts and passed but emitted
new test method-reference Sendable conversion warnings; explicit closures removed them.
Final focus emitted no warnings. An initial planning audit found a missing D116 index
row; corrected full audit reports empty findings. These observations are retained,
not substituted for final qualification.

Optimized development app/read-only helper build and strict ad-hoc signature verification
passed without new warnings; app/helper minima14.0/11.0, development writer absent.
This optimized build uses the same unchanged product code as the added permission test;
it is not DeveloperID/notarization or older-OS runtime qualification. No UI walkthrough
is claimed for an internal operation that remains unexposed.


D-116 final qualification: expanded ordinary433reported tests/90suites205.588s passed,
26 opt-in skips unchanged; new access suite8tests14.273s including actual non-root
POSIX read/write denials. No new warnings. Focused26tests/3suites3.807s passed before
final generated permission-restoration cleanup adjustment; expanded ordinary run covers
that final test code. Optimized unchanged product build/strict ad-hoc app/read-only helper
signatures passed without warnings, minima14.0/11.0; writer absent. Actual live-reader
PID-specific idle-sleep assertion present during ownership and absent after settled release,
source/parent descriptor FileIDs held through phases and retained review. Positive scope
counts are explicitly fake-provider lifecycle evidence; sandbox grants/revocation remain
unqualified. Controlled retention persists across dropped errors and energy expiry; real
joined-writer stage substitution retains cleanup review. Only one run/pending review is
admitted. No production recovery-from-review API, release tool trust, archive UI or writer
packaging follows. Rust/reference/APFS unchanged D115 evidence reused, not re-executed.
PR90 reader passed; app three unchanged timing failures retained/PR updated; no retry or
D090 observer/assertion/deadline/global scheduling change. Protection/privacy final below.


Final seven-file public/nonignored change scan: three private source path/name/stem
patterns have zero matches with positive decoded source-field sentinel. Owner source
metadata and current recovery journal unchanged; full planning audit findings empty.
No source-body read, owner queue, private film archive/encode/listening, merge or release.
Initial missing-index planning finding retained and corrected. Existing bounded awake
PID32011 exact command/start inspected; expiry16:01:07UTC, no renewal/security changes.
