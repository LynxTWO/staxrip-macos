# Native original source/base-frame association

D-127, R059 / Slice049. Unused native development composition, generated evidence.
CompanionDiskCheck.associateOriginalFrames binds actual owned D124 decoder packet/
base-frame rows to independently reconstructed D126 source/configuration/encoded
packet/escaped-RPU facts using the still-open D125 spool. This is source/base-frame/
raw-RPU association only. It does not qualify samples/rendering, EL reconstruction,
editing, conversion, release provenance or app action.

## Concrete composition

One dedicated native worker owns the pinned source descriptor, fresh source pass,
open SQLite database and synchronous decoder execution. The async source-only method
is not called inside it, no closed database is adopted, and no nested async wait or
Python runtime bridge exists. Fixed source/configuration byte counts and hashes,
packet byte offsets/sizes/hashes, signed PTS and every escaped original RPU are read
from the original. Retained companion APIs remain stricter and unchanged in scope.

After source count settlement, fixed checked rows record each matched packet and
exactly one frame. Primary encoded indices preserve source order; a frame may refer
to an earlier original packet after codec reordering. Every packet must be visible
and match source clock/offset/size/hash. Every frame must match its original packet,
three exact timestamps and original RPU size/hash/packet/time association. Equal
packet/RPU counts alone are insufficient: each original RPU index must match its
corresponding packet. A missing RPU plus a surplus elsewhere refuses. No record is
deduplicated. D124's existing progressive10-bit/geometry/strictly increasing frame
presentation-time contract remains required; ambiguous/nonoutput/duplicate presentation
cases do not silently become qualified associations.

Fixed coverage is created only for decoder passes, leaving source-only schema/rows
unchanged. Primary-key inserts and conditional frame updates refuse duplicate or
missing coverage. Completion requires every packet/frame and full original/table/
decoder counts, then actual owned EOF/zero exit/source/tool/library final observations.
The decoder fingerprint/configuration must match pinned independent source facts;
source is rehashed and path/descriptor/spool membership rechecked. Database/source
checked closes precede return. Only this complete composition returns the true source-
frame association flag. Existing source-only and decoder stream receipts remain false;
edited-picture semantics remain false in every receipt.

Exact rational conversion cancels denominator factors from signed tick magnitude,
time-base numerator and1e9 before checked multiplication. It refuses fractions,
unsupported clock terms and overflow instead of rounding or multiplying before division.
Tests include exact signed magnitude extremes and a result fitting Int64 whose naive
multiply-then-divide intermediate exceeds UInt64. The decoder still refuses its
AV_NOPTS_VALUE sentinel; arithmetic tests do not broaden that process contract.

Bounds remain fixed: source1TiB/read1MiB, packet16MiB/RPU65536bytes,2M original
packet/RPU/decoder records,4096-byte pages/512MiB maximum database, requested8MiB
cache/no mmap and checked MEMORY row autocommit. Coverage shares the database cap.
Neither configured settings nor fixture times establish total memory or whole-film
performance guarantees. Decoder deadline applies to its owned phase; the source
pass remains cooperatively cancellable, without a whole-operation wall-clock promise.
Physical I/O, SQLite, parser/consumer CPU and wait cannot be preempted by checkpoints.

## Ownership and limits

Ordinary errors/cancellation settle decoder worker/direct child/pipes/readers before
spool/source close and async return. Late cancellation after child join refuses the
association, which performs no publication. Shared uncertain process/close ownership
propagates unchanged and retains needed source/folder/access. There is no automatic
cleanup, candidate adoption/import, directory search, source-selected tool, resource/
security-scope controller, production review release, default bundling or archive UI.
A trusted caller owns explicit source access and an empty0700 temporary folder.

Fixed DEBUG tool content/library identities are development trust, not positive
DeveloperID or release authentication. Source observations are not immutable snapshots,
persisted producer provenance or hostile same-user assurance. The decoder is the
frozen ordinary ad-hoc compatible candidate; no rejected hardened loader or incomplete
certificate operation was retried. Raw originals are independently reconstructed;
decoded picture/metadata claims rely on that fixed FFmpeg implementation. No independent
second decoder, all-field Dolby interpretation, EL association or display proof follows.

## Executed generated evidence

The five frozen object hashes match D097 before execution. Ten actual generated native
trials pass: one/four threads for B-frame, BlockGroup, variable-VINT, conformance and
complete open-GOP sources, four or24 original packets/base pictures/RPUs. Source hashes,
configuration and count settlement agree. Conformance retains coded176x112 and codec
crop[0,14,0,14]; codec/container cropping is not silently applied. Sources/prior outputs,
frozen executable/libraries and owner metadata/current journal are protected.

Additional actual native final-copy source mutation, extra spool membership and same-
content source pathname substitution refuse after helper join. Cancellation after
already-joined zero-exit helper also refuses. A repeated2000-cluster generated input
observes a live/non-zombie decoder before Task cancellation; ordinary settlement joins
it and preserves input/prior/frozen hashes. Final actual opt-in test2.479s passes with
15 helper direct children joined. Initial actual ten-case/live test7.488s also passed.
No new uncertain-group fault was observed; retained uncertainty policy is not fault proof.

Twelve plausible row forgeries pass D124's partial parser alone but fail source binding:
configuration size/hash/time-base, packet timing/position/size/hash, frame packet index/
position/size and RPU size/hash. Reordered frame coverage succeeds without changing source
rows. Missing delivered coverage, surplus or misplaced RPUs and encoded invisibility
refuse. Existing page-full/cancellation/path/row-limit checks remain required. These
forgeries are generated native parser/spool checks, not forged production helper trials.

Two new test compilation failures lacked a declaration-separating newline; both logs
are retained and precise formatting corrected. No assertion/deadline/global concurrency
or historical timing observer changes follow. Final composed focus36tests/5suites13.072s
passed without warnings, including existing93-source statically linked hardened host.
That host compiles the new implementation but executes its existing preservation/review
pipeline; this decoder candidate is not qualified for hardened app loading there.
Ordinary/optimized/signature/protection and prior automatic outcome are recorded below.

No owner media body or repeated120552-source association, queue/full-film archive/encode,
listening, known-crashing SwiftPM module fixture, signing retry, merge or release occurs.

Final ordinary479tests/98suites210.792s passes29 explicit opt-in skips/no warnings
(one additional actual frozen association opt-in). Explicit production build19.56s
and strict ad-hoc app/read-only helper signatures pass, minima14.0/11.0, writer and
decoder absent. Nine changed files pass owner path/name/stem privacy scan with zero
matches/positive sentinel; owner source metadata/current journal unchanged, planning
findings empty. No new UI walkthrough or hardened decoder loading claim.

Prior PR101 automatic37233860856 failed474tests1271.833s68issues, retained without
retry:26 unchanged60s/33 unchanged120s deadlines, four absent-positive decoder child
assertions, three motion expectations, owned static compiler/host bound and measuring
EOF. Source packet suite714.516s/spool57.787s passed. Log/PR updated; timing/phase/
prelaunch causes unknown. Local pass does not explain or remove those failures.
