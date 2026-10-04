# Native original index and manifest prerequisite

D-111, R-059, 2026-10-04. Internal generated development qualification, no archive
UI, stable importer, release writer packaging or full original semantic admission.

CompanionOriginalIndexCheck reads actual original rpu-index.jsonl and manifest.json
through fixed bounded descriptor-relative capabilities on D108's owned read worker.
Source/stage/component handles remain pinned through parsing and final observations.
D109 independently located TrackEntry/hvcC and D110 source packet/RPU observations
are reused; stored producer counts and hashes alone are not semantic authority.

CompanionArchiveJSON is a separate bounded grammar for the fixed version-zero emitted
fields. The existing writer pipe parser/protocol remains unchanged. This grammar
rejects duplicate keys recursively, non-objects at the root, non-ASCII/escaped strings,
fraction/exponent/nonfinite numbers, null, negative zero, leading-zero integers and
trailing data. Signed PTS distinguishes integers from booleans and represents Int64.min
exactly; nonnegative integers retain UInt64 range before per-field admission. Strings
are bounded128bytes, object keys20, arrays16, depth4 and values256. Manifest capture
is at most1MiB, index lines65536bytes including LF; these are configured bounds, not
measured peak memory or a general JSON/session compatibility claim. Fixed emitted
schemas contain no free-text media names requiring escaped or Unicode strings.

The manifest has an exact field set and version0. Retention/association/decoded flags,
source-content recheck, absence of persisted source-path binding and absence of metadata
rewrite must match the existing producer contract. Source bytes/SHA256 match D108 actual
disk settlement; selected original TrackEntry offset matches D109 actual source reading.
Packet/RPU/enhancement counts subsequently match D110 reconstructed source facts. Exact
component names, declared sizes and SHA256 match already independently read actual disk
members. The manifest excludes itself from its component list. Duplicate/unknown/self/
path-like names refuse; component order and permitted JSON whitespace have no meaning.
No executable or pathname from a manifest is opened or executed.

The index reader streams fixed64KiB chunks from only rpu-index.jsonl, never captures the
whole component and never opens an archive-selected path. Each exact typed row is consumed
synchronously for the next actual source RPU observation: record/packet/NAL ordinal,
signed PTS, original escaped source payload offset, archive delimiter offset, payload
byte count and SHA256 must all agree. Encoded order, duplicate and nonmonotonic signed
PTS remain unchanged. At most2000000 rows, component at most512MiB, no incomplete/blank/
extra/reordered records. D110 separately compares every retained escaped RPU byte and
consumes original-rpu.bin exactly. An observation before final settlement is not an
individually successful receipt. Cancellation checks remain cooperative; physical I/O
and parser CPU cannot be preempted.

The result says originalIndexMatchesSource and
manifestClaimsMatchObservedSourceAndComponents. It does NOT assert that the manifest
was produced by a particular execution or supplies immutable source identity. Prototype
version0 remains unbound, not a stable importer or persisted producer provenance. Full
originalMetadataSemanticsVerified and originalPacketRPUSemanticsVerified remain false.

Source-audit schema/source relationships, geometry/default-duration declarations,
libdovi compact summaries and RPU metadata validity remain open. A repaired forged audit
can pass this partial admission because its actual content hash is checked while its
semantics are not; an explicit test preserves that boundary. Matching native index and
manifest results still fail D105 full transaction admission before publication. No native
archive action, helper Python bridge, release writer capability or packaging is added.

Metadata-only retains original selected TrackEntry/hvcC, escaped RPUs and signed encoded
associations, excluding BL/EL pictures and outside-track information while retaining
selected embedded names/metadata. Entire-container retains the entire byte-for-byte
original source with all streams and embedded names/metadata, at source-sized storage.
Future native review must disclose these losses/storage/privacy. Native leases/resource/
signing/distribution, stable import, ENOSPC/volume/crash/blocked-I/O and decoded association
remain separate gates. Preservation, compatible conversion, edited-picture statistics,
enhancement reconstruction and archival remain distinct choices.

Generated acceptance covers actual native Rust writer both modes and the independent
Python original checker as an explicit TEST-ONLY oracle. Four-packet/five-RPU/one-EL
source duplicates/nonmonotonic PTS remain in order. Additional actual Rust writer sources
with Int64.min/Int64.max PTS retain exact persisted index associations. Rehashed manifest
and index forgeries pass narrower packet/integrity checks but fail native source admission.
Type/schema/flags/names/source/count/track-offset/component and index offset/order/hash/
truncation/extra-record mutations refuse. JSONL lines crossing fixed read chunks and
bounds are exercised without whole-file capture. Actual manifest/index-read cancellation
and late source/stage/index/manifest mutations refuse after read worker unwind. Matching
partial D105 refusal preserves source and cleans only settled owned work.

| Claim | Kind / confidence | Evidence and limit |
| --- | --- | --- |
| Persisted signed encoded RPU associations match independently read original source | observed_behavior / verified on generated fixtures | Actual Rust writer both modes, signed extreme sources, rehashed index/order/offset/type forgeries; no decoded association or metadata validity |
| Fixed manifest claims match observed original source and actual disk members | observed_behavior / verified on generated fixtures | Exact schema/qualification/offset/source/component comparisons and rehashed forgery refusals; no persisted execution or immutable-snapshot proof |
| Partial index/manifest success cannot approve full original semantics/publication | source_fact and observed_behavior / verified contract | Full flags false, repaired audit boundary test and actual D105 refusal |
| Native archival is production complete | unknown | Source-audit/metadata/geometry plus native action/resource/lease/signature/storage/crash/import/decoded gates remain |

Consequence local_only generated, future user_data. Method Swift6.4/Swift Testing,
bounded native JSON/EBML and actual native generated writer. Source/parser/worker/
configuration/retention/OS changes invalidate affected evidence. Unchanged full Rust/
semantic/process/reference suite receipts are reused, not new executions. Owner queue,
full-film archive/encode, listening, merge/release and native UI execution excluded.


D-111 focused outcome:53tests in5suites passed12.500s. Actual native writer both modes
and independent test-only original oracle pass0.792s; actual signed-extreme source writer/
index admission pass0.415s. Matching partial D105 refusal passes0.191s. Rehashed manifest
27-case and index20-case forgeries pass narrower integrity/packet checks but refuse
actual native source admission. Cancellation during manifest/index reads and late
source/stage/index/manifest changes refuse after worker unwind. Fixed chunk/row bounds,
integer/type grammar and permitted whitespace/component order pass. A repaired audit
forgery remains explicitly outside partial semantic admission; full flags stay false.
Earlier51-focused12.106s receipt before signed-extreme/whitespace qualification retained
separately. Final ordinary/build/protection/privacy/planning settlement follows.


D-111 final ordinary regression:399tests in85suites passed204.805s. Native original
index suite passed20.427s in that unchanged ordinary run; focused53tests/5suites passed
12.500s. No new compile warnings in final focused/regression logs and no legacy
assertion/deadline/default scheduling change. Full source-audit/metadata/geometry
semantics and publication remain unavailable. Final optimized build settlement follows.


Final optimized development build and strict ad-hoc app/read-only helper signatures
passed. Minimum declarations remain14.0/11.0; development writer absent. No hardened
DeveloperID/notarization or older-OS runtime qualification. Source metadata/current
recovery bytes unchanged. Nine changed public/nonignored-untracked files scanned for
three exact private source path/name/stem patterns: zero matches, positive decoded
private source-field sentinel. Private owner media/logs/receipts/ignored binaries
excluded; scoped absence only. Planning findings empty. No native UI/action or owner
session/queue execution. PR85 automatic two unchanged AV1/ten-bit timing failures
retained without retry; causes remain unknown.
