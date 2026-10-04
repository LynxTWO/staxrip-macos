# Native original track and configuration evidence

Date: 2026-10-04. R-059 / Slice049 / D-109. Unused internal native prerequisite on
generated fixtures; no owner media operation or application archive action.

## Contract and ownership

Component hashes prove bytes agree with a receipt, not that those bytes came from the
selected original stream. Native CompanionOriginalTrackCheck independently locates the
pre-cluster selected HEVC video TrackEntry in original source EBML bytes and compares its
exact payload and hvcC with retained components. The result contains original source
payload offset, track number, sizes/digests and structural NAL length width. It explicitly
leaves originalPacketRPUSemanticsVerified=false. Enclosing D108 disk receipt still says
originalMetadataSemanticsVerified=false; native full originalComponentsMatchSource is
not asserted. This partial match cannot admit D105 transaction publication.

D108 verifyOriginalTrack runs actual disk integrity checks first, then the synchronous
native parser on the same dedicated cancellable read worker. Read-only capabilities are
constructed from operation-owned source/component descriptors, not package-selected paths
or commands. Source reads are bounded1MiB, offset/size within pinned source length; only
fixed original-track-entry-payload.bin/hevc-configuration.bin component reads are allowed,
each bounded1MiB. Descriptor lifetimes extend through native track parsing and final
source/stage/member observations. Parser cannot write, delete, publish, launch a process,
or select another source/component. Ordinary errors unwind owned readers before returning.
D108 integrity-only verify keeps its behavior and returns no original track result.

Native EBML parser reads finite1...4byte IDs and1...8byte sizes, parent-exact bounds, with
unknown size allowed only for Segment. It requires an initial finite EBML header and
Segment, walks pre-cluster structures and refuses unknown-sized children. Total parsed
elements<=100000, tracks<=256 and each TrackEntry payload<=1MiB. Critical track fields
are unique; track numbers are unique/positive/bounded1TiB, kind positive. Only one video
track is selected and its CodecID must exactly equal V_MPEGH/ISO/HEVC with hvcC present.
Other streams and opaque selected metadata are not interpreted as picture/packet/geometry
semantics. Selection stops at the first finite Cluster. Tracks or malformed structures
after that boundary are not examined here; this is not a whole-container demuxer.

Structural hvcC validation requires version1/min23bytes, bounded complete NAL arrays,
exact array/NAL type agreement, nonempty2byte-or-larger NAL headers with forbidden bit
clear/nonzero temporal ID and no present RPU/enhancement NAL in configuration. Empty type62
arrays contain no RPU and remain allowed, matching the existing Rust reader. All native
length widths1...4 remain supported. No VPS/SPS/PPS decoding, codec capabilities, picture
or enhancement reconstruction, playback or transformed metadata quality is inferred.

Cancellation checks surround native source reads, every element and hvcC iteration, final
observations and async return. The new DEBUG originalTrackRead boundary qualifies actual
new-unit cancellation, not D090 historical timing observation. Physical I/O cannot be
preempted. No immutable snapshot or same-user adversarial race guarantee; D108 observation
limits remain. No independent native heap/blocked-I/O/deadline qualification is claimed.

## Generated verification

Actual fixed unbundled native Rust writer both retained modes supplies generated selected
track/configuration. Native original selection and exact source/component bytes agree;
independent Python original semantic checker is an explicit test oracle only. No Python
runtime app bridge is installed. Entire-container source bytes remain exact and original
source is unchanged. Integrity-only calls have no partial original-track receipt.

Rehashed substituted original TrackEntry or hvcC passes integrity-only settlement but
refuses native original matching. A matching native partial result used as the verification
phase explicitly fails D105 full semantic admission; prior result/source bytes survive
and only its settled owned stage is cleaned. Native source-read cancellation returns only
after worker unwind, leaves caller components, and cannot admit late success. Source/stage/
component mutation after native parsing refuses final observations, retaining caller data.

Finite/unknown Segment generated cases retain opaque embedded selected fields exactly.
Nonvideo tracks are not mistaken for selected video. Duplicate critical fields/Tracks/video/
track numbers, wrong codec/missing track, unknown child/truncation/parent overflow/invalid ID
refuse. Malformed hvcC version/length/type/forbidden/temporal/RPU/trailing/array count refuse
while retained bytes themselves match source. Element/track/payload bounds refuse without
unbounded capture. Empty RPU arrays/all1...4 length widths match existing reader behavior.
These small synthetic codec bytes establish structural behavior, not decoded video validity.

## Limits and retained failure

Native original RPU bytes, duplicate-preserving signed encoded packet/index relationships,
source-audit/manifest semantics and original offset/qualification binding remain unverified.
The manifest is still version zero/unbound, not a stable importer or persisted producer
binding. The returned actual offset is not admission of the stored manifest's offset.
Full native semantic settlement and D105 joining remain next. No application archive action,
release writer capability/packaging, native lease/resource/provenance/signing admission.
Future owner review must disclose metadata-only BL/EL picture/outside-track losses and
selected embedded metadata/names; full container retains source-sized entire original
including other streams/names/metadata. Stable import, ENOSPC/volume/crash/blocked-I/O and
decoded association remain gates. Original preservation, compatible conversion, edited-
picture statistics, enhancement reconstruction and archival remain separate choices.

Completed120552 packet/base-picture/raw-RPU source association retained without repeat;
decoder remains unbundled. Interrupted DeveloperID signing retained without retry. No
owner queue/full-film archive/full-film encode/listening/merge/release or UI action.

PR83 automatic app37197046205 failed unchanged AV1/ten-bit120-second deadlines.
All365tests finished566.630s with two issues, native disk suite passed104.138s, preview
skipped. Private failed log retained/PR updated; no retry, historical observer, assertion/
deadline or scheduling change. Causes remain unknown; D090 remains completed.

| Claim | Kind / confidence | Evidence and limit |
| --- | --- | --- |
| Retained selected TrackEntry/hvcC exactly matches independently located original | observed_behavior / verified on generated fixtures | Actual native writer both modes, original offsets/bytes/digests, independent test oracle; selection is pre-cluster and partial |
| Hash agreement cannot substitute source provenance for these components | observed_behavior / verified on generated fixtures | Rehashed component forgeries pass integrity but fail native original match |
| Partial native original track match cannot admit full transaction semantics | source_fact and observed_behavior / verified contract | False full semantic flags and actual transaction refusal preserving prior/source bytes |
| Native original archival is complete | unknown | RPU/index/audit/manifest semantic and action/resource/lease/signature/storage/decoded gates remain |

Consequence local_only generated, future user_data. Method Swift6.4/Swift Testing, native
bounded EBML/hvcC reader, actual fixed DEBUG-generated writer and Python test oracle.
Source/parser/configuration/worker/retention/OS changes invalidate affected evidence.
Unchanged full Rust/semantic/process/reference suites retain prior receipts, not new
executions. Focused/final ordinary/build/protection/privacy/planning settlement follows.

D-109 focused outcome: thirty tests in three suites passed4.439s after empty-array
compatibility qualification. Actual native writer both modes matches independently
located original TrackEntry/hvcC and independent test-only Python original checker.
Rehashed substituted components pass integrity-only checks but refuse original matching;
a matching partial result cannot admit D105 full semantics. Actual native read cancellation
and final source/stage/component changes refuse after owned reader unwind. EBML ambiguity/
framing/count/payload and hvcC framing/header/array faults refuse; empty type62 arrays and
all1...4 NAL length widths match existing reader semantics. No full native RPU/index/audit/
manifest or decoded claim. Earlier375tests/83suites passed206.025s before empty-array
compatibility change; final regression/build/protection settlement follows. See
NATIVE-ORIGINAL-TRACK-EVIDENCE.md.

D-109 final ordinary regression:376tests/83suites passed204.602s after empty-array compatibility qualification. Earlier375-test baseline206.025s is retained separately, not reused as final acceptance. Final thirty-test focused compile had no new warnings; existing older async-main-thread/optional-Bool macro warnings were observed separately. No legacy assertion/deadline/default scheduling change.

Final optimized development build and strict ad-hoc app/read-only helper signatures passed.
Minimum declarations remain14.0/11.0, writer absent; no hardened DeveloperID/notarization/
older-OS runtime qualification. Actual both-mode native original track case0.674s and
partial transaction refusal0.182s passed. Source metadata/current recovery bytes unchanged.
Eight changed public/nonignored-untracked files scanned for three exact private source
path/name/stem patterns: zero matches with positive private sentinel; private media/logs/
receipts/ignored binaries excluded. Scoped absence, not certification. Planning findings
empty. No native UI action or owner session/queue execution.
