# Original packet first-slice PPS prefix binding

D152 adds an unused source-only first-slice VCL reference finding on the existing pinned
synchronous source/open SQLite worker. Fresh selected Track/configuration/source CodecPrivate
binding reuses D151 VPS/SPS/PPS prefixes. Exactly one base-layer TemporalId0 first-slice VCL
per original selected packet must reference the finite configuration PPS ID. Allowed NAL
types are0/1,6...9,16...21; TSA/STSA TemporalId0, reserved types, non-first/dependent slices,
missing/duplicate VCL, unsupported layer/temporal/header, invisible packets, mismatched PPS
and selected packet in-band VPS/SPS/PPS refuse this new subset. Common CodecState/unsupported
BlockGroup refusal remains; no universal update/activation policy follows. Older APIs retain
their narrower capabilities and original admission.

The first-slice flag, optional IRAP prior-picture flag and PPS ID occupy at most15 total bits.
Only up to two payload bytes after the existing two-byte NAL header are read. No complete
picture is sent through the whole-parameter-NAL RBSP unescaper. The leading first-slice bit
is one, so an emulation-prevention sequence cannot occur in this prefix. Remaining slice
bytes are opaque; malformed suffix/escape or shape-valid changed contents can pass this
partial readback. Prefix vectors are not valid complete slices or parameter sets.

Primary [ITU-T H.265 V11 January2026](https://www.itu.int/rec/dologin_pub.asp?id=T-REC-H.265-202601-I%21%21PDF-E&lang=e&type=items)
Table7-1,7.3.6.1,7.4.2.1 and7.4.2.4.2 were inspected for VCL types/header restrictions,
first/IRAP/PPS syntax, emulation prevention and parameter activation. PPS IDs are bounded
0...63; non-first/dependent addresses require SPS CTB-grid and later semantics outside this
prefix. Reference equality is insufficient to establish activation or valid complete picture
use. No implementation code copied. Opaque VPS/PPS/SPS/PTL suffix, SEI activation, complete
HEVC conformance, progressive/field/color/SAR and independently decoded values remain open.

Every original source/configuration hash, signed encoded packet offset/size/hash and exact
escaped RPU is reconstructed. Finite typed VCL observations retain one pending prefix and
stream a sequence hash; production holds no picture or all-row collection. Signed duplicate/
nonmonotonic encoded order and repeated RPUs are preserved without deduplication. Full
source/table counts, final source/spool identity/hash observations, qualified normal checked
SQLite/source closes and awaited owning worker precede return. Source-only counts do not
prove one decoded picture/RPU per packet or exact rational decoder coverage. The new path
launches zero decoders. Caller explicit source/spool access and retention on shared
uncertainty remain required; D149 joint controller does not automatically cover this entry.
No second worker/closed-store adoption/generic lease-receipt/Python runtime bridge/protocol/
action/default packaging/recovery or cleanup authority.

Five new tests cover every accepted NAL type/PPS ID0...63, optional prior-picture presence,
non-first/reserved/unsupported/truncated/overlong PPS and bounded storage refusal. A2MiB
opaque VCL fixture hashes in existing at-most1MiB chunks and reads only two additional prefix
bytes. An advertised1GiB payload with two-byte input demonstrates prefix buffer bounds, not
measured total memory/speed or parser/I/O preemption. Signed duplicate/nonmonotonic packets
and duplicate RPUs remain exact; missing/duplicate/mismatched references refuse while the
older framing path can accept those partial shapes. Stale configuration refuses; a freshly
repaired PPS/slice pair binds with activation false.

Five actual native-generated HEVC sources (single/BlockGroup/wide VINT/conformance/24-picture
open GOP) report four first-slice references/one IRAP for each first-four source and24/two
for the open GOP. No decoder is launched or new comparison claimed. Record cap, read-pass/
late task cancellation, same-byte final source substitution, extra spool member and actual
configured eight-page SQLite-full refuse with source bytes unchanged. SQLite-full is not
physical ENOSPC. Generated roots remain private without adoption/deletion/group/production
recovery authority. No owner media body/full-source repeat, captured runtime rebuild/copy,
C/sanitizer/pixel oracle/APFS/DeveloperID/UI qualification.

Initial compile-only12tests1suite1.628s passed; it preceded new VCL tests and the final
TSA/STSA exclusion. Final composed43tests3suites15.140s passed/no warnings, including the
new source-only tests1.690s and static prior companion host15.140s. Exact static closure
remains94 product sources: changed code compiles, execution is prior preservation/review,
not VCL/reference/SPS/crop/sample/decoder loading. No new compile/test failure in this unit.
Full ordinary/production/protection results follow completion.

Parent PR126 automatic37299445080 failed594tests577.400s34issues: zero60s,21unchanged120s/
seven180s bounds plus six other assertions (two decoder-surrogate absent-positive-child,
crop role-close/child and Fresh-analysis/Rendering-candidate EOF expectations). Exact shared
fixture preparation passed51s; SPS/reference83.625s/access306.776s/static291.490s passed.
Full failed log/summary retained and parent updated without retry or individual cause
attribution. Local passes do not resolve hosted failures. D136 supported cold duplicated
compilation correction does not explain every residual or exclude defects. No historical
observer/assertion/deadline/CI margin/skip/global suite-job scheduling/concurrency workaround.

Only originalFirstSlicePPSPrefixesBoundToSource, sourceFirstSlicePPSReferencesAgree and
selectedPacketParameterSetNALsAbsent become true after complete source-only settlement.
Active picture selection/full slice-parameter conformance/source-frame/ROI provenance/
independent values/rendered/edited flags remain false. Full joint original configuration/
packet/RPU/exact rational timing/one-picture coverage/final fixed decoder-tool-library-spool
observations and qualified ownership remain separate prerequisites before geometry or origin
upgrades. No independent HEVC/pixels/PQ-linear/color/EL/resize/Dolby conversion inference.
Other resource/deinit/retirement/recovery/distribution gates remain open; no whole-program
completion or all-useful-work blockage claim.


Final ordinary599reported tests/105suites214.228s PASSED38 unchanged explicit opt-in skips/
no emitted warnings; combined SPS/reference/VCL14.587s/access33.804s/static33.379s. Explicit
production21.48s/current strict ad-hoc app/read-only helper signatures/minima14.0/11.0
pass; writer/decoder/sample/crop absent. Seven-file privacy zero/positive sentinel, protected
owner metadata/journal/original sample-prefix-frozen-D130/D142/D143 artifacts unchanged,
planning findings empty. New generated roots retained privately; no new compile/test failure
or ordinary retry. New narrow entry still requires explicit caller access/retention; full
parameter/slice/activation, source origins/values/rendered/edited and other finite ownership/
retirement/recovery/distribution gates remain open.
