# Native original source-audit framing evidence

D-112 is an unused internal prerequisite. `verifyOriginalAudit` owns the same D108
pinned source/stage/component reader and cancellation settlement as earlier partial
APIs. No archive action, Python app bridge or release writer is introduced.

The native validator independently reads selected original container declarations:
pixel width/height, crop left/right/top/bottom, optional display width/height/unit,
optional default duration. D110 supplies actual TimestampScale and Segment known/
unknown-size state before the first packet. D111 simultaneously consumes original
RPU index rows. Audit begin/packet/RPU/complete schemas and relationships are matched
to source order, signed PTS, nullable duration/flags, offsets, actual packet/RPU hashes,
actual source hash/size, peak RPU bytes, counts and canonical packet sequence.
Exactly one begin and complete, with no missing/extra/trailing/non-LF rows, are required.

Compact libdovi summaries receive exact key/type/range/array shape checks only. Their
metadata values are not independently decoded from escaped RPU bytes. A plausible
changed profile can pass this partial framing check; a dedicated generated test keeps
`compactMetadataSummaryVerified`, `originalPacketRPUSemanticsVerified` and enclosing
`originalMetadataSemanticsVerified` false. A matching partial result refuses D105
full transaction publication. Stored parser identification is a checked claim, not
executable authentication or persisted producer provenance.

Fixed audit capability: source-audit.jsonl only, existing descriptor pinned until final
source/stage/member observations, maximum1GiB/4,000,002 rows/65,536 bytes per LF-inclusive
row/65,536-byte read chunk. Existing index512MiB/2M rows and manifest1MiB unchanged.
JSON limits: depth4/256values/20keys/16array entries/128ASCII string bytes; duplicate
keys, escapes/non-ASCII, fractions/exponents/nonfinite and negative zero refuse.
Null is permitted only in audit parsing and exact schema getters; index/manifest and
D106 pipe protocol preserve their earlier refusals. Limits are configured bounds,
not measured peak memory/resource guarantees.

Geometry: width/height2...16384; crop sums checked for overflow and strictly inside
picture; optional display dimensions1...65536/unit0...4; positive optional default
duration preserves UInt64.max. Unique critical fields and bounded finite parent
framing required. This reads original container declarations, not codec parameter
sets, decoded picture geometry or edit/conversion acceptance. Existing lower APIs
still admit their prior narrower scope without geometry/audit receipts.

Focused52tests/5suites12.602s passed; audit suite3.011s. Actual native Rust writer
both generated retention modes matches independent test-only original Python oracle
0.780s. Actual signed Int64 extremes with unknown Segment/nonzero crop/display/
UInt64.max duration pass0.450s. Matching partial native transaction refuses0.213s.
Repaired audit source substitutions pass lower index/manifest checks then refuse;
geometry malformed/default/boundary cases, row framing/type limits, cancellation
inside actual audit reads and late source/stage/audit changes are checked. Readers
unwind before refusal. Physical I/O/parser CPU cannot be preempted; observation is
not an immutable snapshot or hostile same-user guarantee.

Final ordinary regression/build/protection settlement is recorded below when complete.
Native owned fresh metadata decoding/comparison, complete semantic transaction admission,
resource/security leases, release capability/packaging/signing/owner review, persisted
binding/stable import, ENOSPC/volume/crash/blocked-I/O and decoded association remain
separate gates. Original metadata-only and entire-container storage/privacy contracts
remain unchanged. No owner media/queue/archive/encode or listening operation performed.


D-112 final ordinary regression:409tests in86suites passed206.948s. Native audit
suite11.006s passed in that ordinary run. Focused52tests/5suites12.602s receipt retained;
54 repaired audit-forgery cases and25 malformed geometry cases checked. No new compile
warnings in final focus/regression and no legacy assertion/deadline/scheduling change.
PR86 automatic all399 tests471.151s and preview passed without retry; prior hosted
unknown-cause failures retained. Full metadata semantics/publication remain unavailable.


Final optimized development build and strict ad-hoc app/read-only helper signatures
passed; minimum declarations14.0/11.0 and development writer absent. No DeveloperID,
notarization or older-OS runtime qualification. No native UI/action, owner session/
queue/archive/encode or listening operation. Owner source metadata/current journal
unchanged. Eleven changed public/nonignored-untracked files scanned against three
exact private source path/name/stem patterns: zero matches with positive decoded
private source-field sentinel; private media/logs/receipts/ignored binaries excluded.
Planning findings empty. Next: qualify an actual fixed trusted owned native metadata
reader/library and compare fresh compact RPU metadata to stored summaries before
complete semantic transaction admission. Existing ToolRunner drains/joins direct
child and readers but does not qualify group/descendant ownership for this archive
bridge; do not treat a test oracle or current summaries as native metadata proof.
