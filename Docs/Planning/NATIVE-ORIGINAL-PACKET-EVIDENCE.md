# Native original packet and raw-RPU prerequisite

D-110, R-059, 2026-10-04. Internal generated development qualification; no archive
UI, release writer packaging, stable importer or full semantic admission.

D109 original track/configuration matching and D108 source/stage/component descriptor
ownership precede a new independent native source walk. The shared bounded EBML walker
keeps D109's100000-element pre-cluster limit; the new source walk uses128000000 parsed
elements,32000000 blocks and2000000 selected packets/RPUs. Source limit1TiB, selected
packet16MiB, original escaped RPU1...65536bytes, fixed component read1MiB maximum.
These are configured bounds, not measured peak memory or production performance claims.

The source reader checks finite header/parent framing, Matroska DocType/header limits,
Info/TimestampScale uniqueness and positivity, one pre-cluster Tracks selection and
finite clusters with exactly one preceding timestamp. Unknown size is accepted only
for Segment; finite-source trailing elements are limited to Void/CRC. Unsupported
selected lacing, reserved block bits, undeclared track numbers, nested/direct blocks,
unsupported selected BlockGroup payload modifiers and nonzero track timing modifiers
refuse. Other declared tracks are skipped and never counted as selected video packets.
DefaultDuration is not substituted for missing packet duration. Geometry/codec parameter
sets remain uninterpreted and no whole-container semantic demuxer is claimed.

Selected HEVC packets are hashed in1MiB chunks. Exact signed PTS uses integer arithmetic,
including Int64.min and a large unsigned cluster timestamp brought back into signed
range by a negative relative timestamp. Encoded order, duplicate PTS and nonmonotonic
PTS are preserved. The canonical packet sequence hashes signed64-bit little-endian
PTS, signed64-bit packet byte count and raw32-byte SHA256 per packet. Optional block
duration uses independently checked unsigned multiplication; it is omitted from this
existing sequence contract.

Length-prefixed NAL framing, forbidden/temporal header bits, RPU layer-zero headers,
source payload offsets and NAL ordinals are read directly from the source. Each retained
raw record must equal00000001 plus the exact original escaped RPU payload. No unescape/
re-escape, interpretation or deduplication occurs. The raw component must be consumed
exactly; recomputed counts must match the bounded producer receipt. Packet/RPU events
are synchronous source observations, not an unbounded collection or a helper claim.
They occur before final settlement and are not independently successful receipts.

New read capabilities accept only fixed original-rpu.bin, bounded offset/count and
an already pinned component descriptor. Original track/configuration reads remain fixed
and bounded. Source/stage/component descriptors remain pinned through native parsing
and final path/descriptor observations on the same owned worker. Cancellation is
cooperative; ordinary returns unwind that worker before caller cleanup. Physical I/O
cannot be preempted. D105 unsettled-ownership retention remains unchanged.

The receipt separates sourceEncodedPacketFramingReconstructed from
originalEscapedRPUBytesMatch. originalPacketRPUSemanticsVerified and
originalMetadataSemanticsVerified remain false. Stored rpu-index/source-audit/manifest
schema, qualification flags, original offsets and relationships are NOT admitted.
RPU metadata validity, active-area geometry, libdovi summary interpretation and decoded
frame associations are also NOT admitted. Rehashed index/manifest substitutions can
pass this partial API; a dedicated test preserves this explicit boundary, and matching
native packet/raw results still refuse D105 full transaction admission.

Metadata-only retention excludes BL/EL pictures and outside-track container information
while retaining selected embedded names/metadata. Entire-container mode retains the
whole original byte-for-byte source, all streams and embedded metadata/names, with
source-sized storage and privacy consequences. These are distinct preservation choices,
not conversions or edited-picture-statistics workflows. Version-zero manifest remains
unbound, no immutable snapshot, persisted execution provenance or stable import claim.

Generated acceptance covers actual native Rust writer both retention modes, four packets/
five RPUs/one enhancement NAL, exact offsets/flags/duration/digests/sequence versus the
stored generated audit and index, plus the independent Python original checker as a
TEST-ONLY oracle. No Python runtime bridge is introduced. Signed duplicates and
nonmonotonic timestamps, all1...4 length widths, finite/unknown Segment, BlockGroup
duration, other declared track skipping, maximum RPU and a picture packet above2MiB
are exercised. Rehashed raw forgery, forged producer counts, malformed framing/header/
track timing/blocks/NAL/RPU/raw-tail cases refuse. Native actual packet-read cancellation
and final raw-member mutation refuse after worker unwind. Partial transaction refusal
preserves source and removes only settled owned work.

| Claim | Kind / confidence | Evidence and limit |
| --- | --- | --- |
| Native reader reconstructs signed encoded packet facts independently from source | observed_behavior / verified on generated fixtures | Actual generated source versus Rust audit/index and independent test oracle, signed/extreme/block/NAL tests; no decoded association |
| Retained escaped RPU bytes match original source byte for byte | observed_behavior / verified on generated fixtures | Actual both-mode writer, rehashed forgery/raw-tail refusal, maximum-size and escaped-byte fixtures; no metadata validity claim |
| Partial packet/raw match cannot admit full transaction | source_fact and observed_behavior / verified contract | False semantic flags and actual D105 refusal; rehashed index/manifest boundary explicit |
| Native archival is production complete | unknown | Index/audit/manifest/metadata, resource/lease/signature/storage/crash/import/owner-review/decoded gates remain |

Consequence local_only generated, future user_data. Method Swift6.4/Swift Testing,
CryptoKit and bounded native EBML/source reads. Source/parser/worker/configuration/
retention/OS changes invalidate affected evidence. Rust/helper contracts unchanged;
prior full Rust/semantic/process/reference suite receipts are reused, not new executions.
Owner queue, full-film archive/encode, listening, merge/release and UI execution excluded.


D-110 focused outcome:42tests in4suites passed4.573s after receipt field clarification.
The earlier focused run passed42tests4.411s and the earlier ordinary baseline passed
388tests/84suites207.319s before field clarification; those are retained separately.
Actual native writer both modes and independent test oracle match source packet/RPU
observations. Rehashed raw forgery and independent count disagreement refuse. Signed
extremes/duplicates/nonmonotonic order, all NAL widths, BlockGroup duration, other-track
skipping and >2MiB packet hashing with maximum65536-byte escaped RPU pass. Thirty-nine
malformed/unsupported source/raw cases refuse. Actual packet-read cancellation and late
raw-member mutation unwind the read worker before refusal. Matching partial packet/raw
results cannot admit D105 transaction; rehashed index/manifest remains explicitly
unqualified and full semantic flags false. Final ordinary/build settlement follows.


D-110 final ordinary regression:388tests in84suites passed205.711s after receipt field
clarification. Earlier207.319s baseline remains separately recorded. Final42focused
checks passed4.573s; actual both-mode source/oracle case0.718s, partial D105 refusal
0.196s and actual packet-read cancellation0.196s. No new compile warnings in final
focused/regression logs. No legacy assertion/deadline/default scheduling change.


Final optimized development build and strict ad-hoc app/read-only helper signatures
passed. Minimum declarations remain14.0/11.0; development writer absent. No hardened
DeveloperID/notarization or older-OS runtime qualification. Source metadata/current
recovery bytes unchanged. Nine changed public/nonignored-untracked files scanned for
three exact private source path/name/stem patterns: zero matches, positive decoded
private source-field sentinel. Private owner media/logs/receipts/ignored binaries
excluded; scoped absence only. Planning findings empty. No native UI/action or owner
session/queue execution. PR84 automatic three timing failures retained without retry;
HDR10/Fresh-analysis cancellation and AV1 deadline causes remain unknown.
