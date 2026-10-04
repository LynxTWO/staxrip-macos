# Native companion writer protocol evidence

Date: 2026-10-04. R-059 / Slice049 / D-106. Internal generated admission prerequisite,
not an application writer feature or native process bridge.

## Need and enforcement

The writer's ready row authorizes one finite start response, not archive completion.
Staged files still require child/pipe settlement, independent disk/source/semantic
verification and exclusive publication. Extending the general ToolRunner immediately
would leave an undefined bidirectional handshake: it currently supplies null stdin.
D-106 first defines a narrow, strict native admission state for the fixed writer.

CompanionWriterProtocol is unused internal Swift code, confined to a single pipe owner.
Expected operation is exactly32 lowercase hex, source size1...1TiB, with chosen mode and
captured source/stage UInt64 device/inode IDs. Initial ready must have exactly its three
fields and correct protocol1/operation. authorizeStart returns one exact start token
plus newline and advances state. Staged before authorization, repeated readiness/start,
trailing rows/data and incomplete/nonzero completion invalidate receipt state. finish
is the controller's declaration of joined stdout EOF/exit status, not proof the parser
can obtain itself. It reports completion once only. No callback launches a process.

Each row is bounded16KiB including LF. The private ASCII JSON grammar bounds nesting4,
object fields20, arrays16, strings128 and unsigned decimal numbers20digits, rejecting
UInt64 overflow and leading zeroes. It accepts only printable ASCII strings without
escapes, numbers and booleans plus arrays/objects. Negative, fractional/exponent numbers,
null, escaped/non-ASCII/control strings deliberately refuse. This is not a general JSON
importer; every current fixed Rust key/value satisfies this subset. Duplicate keys refuse
before schema decoding, so Foundation numeric/boolean coercion or key collapse is avoided.
No dependencies, wire version or writer serialization change is needed.

The staged schema requires exact fields, matching correlation/retention/source/stage IDs
and size,64 lowercase-hex digests, packets/records1...2million, enhancement count0...4trillion,
heap limit64MiB and peak1...64MiB. semantic_verification must be boolean false; neither true
nor numeric0 can pass. Fixed unique member names, positive component-specific sizes and
hashes are mapped into D105 typed Contents. Six metadata/seven entire-container members
are required. A receipt describes claimed content: the parser does not read/hash source,
prove heap usage, authenticate the executable, verify original semantics or publish.
Generic refusal diagnostics never contain malformed source-derived data. Source and
stage paths/payloads are not parser inputs or retained diagnostics.

## Generated checks and limits

Eight focused Swift test functions / one suite passed in0.701s, including five chunk
partitions in both modes and actual generated writer rows in both modes. Chunk sizes
1,2,7,256,16384 preserve readiness/start/receipt behavior. Actual rows retain the full
UInt64 file ID domain; synthetic UInt64.max proves no JSON floating-point rounding.

Readiness/start/incomplete/extra/nonzero/oversize cases refuse and invalidate any previous
partial state. Twenty-four root field/type/bound substitutions, every omitted root field,
ten component mutations and malformed grammar cases reject wrong correlation, source/mode/
member/resource counts, duplicate root/component fields, wrong booleans, escaped traversal,
unknown/missing keys, fraction/exponent/negative/leading-zero/overflow integers, null,
non-ASCII, trailing commas/documents and depth/collection overflow. These are parser
fixtures, not historical timing observers or relaxed admission rules.

The actual integration case exports an operation-owned Rust source fixture, builds only
the optional unbundled writer, captures its actual ready/staged output, admits it with
native state, and compares every component size/hash and source digest to generated disk.
Its one packet/two duplicate RPUs are signed encoded associations, not decoded pictures.
Both modes preserve original bytes; complete mode retains exact full-container bytes.
The finite native start response is checked against the fixed control frame, but the
Python fixture sends that frame. This is actual parser compatibility, not native control
of the writer or active-copy cancellation qualification. Captured child status/stdout
settle in the explicit test transport; no process path may come from a manifest.

The test-only protocol_fixture.py uses explicit Popen argv and closes/reaps its direct
child, with a120second transport limit and32KiB final stdout acceptance. Its stdout capture
allocates before the post-capture bound; fixed Rust stdout is independently bounded to two
16KiB rows. It must not become the generic native process bridge. Terminating this Python
adapter externally is not qualified to settle its separate writer process group. Future
native control must own the actual executable/group/pipes without nested test transports.

Rust producer/parser/protocol/semantic tools are unchanged; D105's40Rust/19companion/
11process/15reference passing receipts remain scoped to those unchanged sources and are
reused rather than presented as new execution in this unit. New native protocol and test
transport behavior is checked here. No native UI/VoiceOver or listening claim follows.

PR80 automatic reader37192320483 passed1m26s. App37192320472 failed unchanged Fresh analysis
cancellation5.133918vs5;340tests401.731s1issue, preview skipped. New actual transaction case
passed58.064s/suite58.066s and AV1 passed its existing bound. Private failed log retained
and PR updated. No rerun, historical observer or weakened timing/assertion/scheduling.
Earlier timing failure causes remain unknown; D090 investigation stays completed.

## Remaining acceptance

Next prerequisite is native owned writer/group/stdin/stdout/stderr lifecycle with fixed
trusted provenance, finite handshake, real ready/active/late cancellation and deadline
settlement on generated fixtures. Then independently native semantic admission and D105
transaction integration, lease/resource/signing and truthful owner review. Metadata-only
excludes BL/EL pictures/outside-track information; entire-container preserves source-sized
whole original including other streams and embedded names/metadata. Stable archive/import,
persisted producer binding, physical I/O preemption, ENOSPC/volume/crash and decoded
association remain separate gates. No archive action or writer packaging was added.
Original source/session/journal/prior outputs protected; no owner queue/archive/full-film
encode, merge/release, listening or interrupted DeveloperID signing retry occurred.

| Claim | Kind / confidence | Evidence and coverage limit |
| --- | --- | --- |
| Duplicate/unknown/type/bound/stale protocol rows refuse | configured_behavior / verified; observed_behavior / verified on generated cases | Private ASCII grammar/schema/state and eight Swift tests; not arbitrary JSON support |
| Current actual writer stdout is admitted in both modes | observed_behavior / verified on generated fixtures | Actual optional Rust executable stdout + native parser + disk hashes; source identity one generated packet/two RPUs, not native process control |
| Native archive process is ready | unknown | No native launch/stdin/group/pipe/lease/provenance policy or independent native semantics implemented |

Consequence local_only for this generated unit, future user_data admission boundary.
Method Apple Swift6.4 (swiftlang6.4.0.34.1), Swift Testing, locked unchanged Rust writer;
source identities bind in the draft PR/private completion handoff. Writer serialization,
protocol/schema, phase interfaces and tool/lifecycle changes invalidate affected claims.
No new UI walkthrough, heard VoiceOver or whole-file source measurement was performed.

Final ordinary regression passed348tests/80suites203.731s with default scheduling/assertions.
Optimized build and strict ad-hoc app/read-only helper signatures passed; actual minimum
14.0/11.0, writer absent. Ad-hoc validity is not hardened writer/notarized distribution
or older-OS runtime proof. Source stat and current recovery bytes unchanged. Ten changed/
nonignored-untracked repository files scanned for three exact owner path/name/stem patterns:
zero matches with positive private sentinel. Private media/receipts/ignored binaries
excluded; scoped absence, not certification. Planning audit findings empty.
