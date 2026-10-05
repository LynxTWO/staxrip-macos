# Original configuration parameter reference prefixes

D151 adds unused source-only configuration reference-prefix readback on the existing pinned
synchronous source/open SQLite worker. It reuses D150 fresh selected Track/configuration
binding, shared bounded hvcC array extraction, strict NAL-to-RBSP removal, bit reader and SPS
geometry prefix. No duplicated SPS/escape parser or second worker. Exactly one array with one
occurrence each of base-layer VPS/SPS/PPS is required; missing, duplicate, identical duplicate,
extra empty parameter array, reserved array bit, unsupported base header and mismatched IDs
refuse this distinct reference path. The existing SPS-only subset stays separate.

The VPS prefix reads ID, base flags, layer/sublayer counts, nesting and reserved prefix bits;
its finite subset requires an internal available single base layer. PPS prefix reads ID,
SPS reference, dependent-slice/output flags and extra header-bit count. PPS→SPS→VPS prefix
IDs must agree. hvcC completeness bits remain raw facts, accepted whether zero or one;
no Matroska-to-hvc1/hev1 assumption or update/activation authority follows. Full VPS/PPS/SPS,
PTL constraints and suffix semantics remain opaque. Shape-valid changed suffix can pass.
The finding is configuration reference syntax, not valid complete parameter sets or active
picture use. No slice, SEI activation, dependent-address or coded-picture parsing is added.

Primary sources inspected: [ITU-T H.265 V11 January2026](https://www.itu.int/rec/dologin_pub.asp?id=T-REC-H.265-202601-I%21%21PDF-E&lang=e&type=items),
VPS/PPS/slice syntax and parameter-set activation semantics (7.3.2.1, 7.3.2.3.1, 7.3.6.1,
7.4.2.4.2, 7.4.3.3.1). PPS begins with its own ID and referenced SPS ID; the SPS identifies
its VPS. Slice headers carry a PPS reference, with separate first/dependent-slice rules.
Reference declarations alone are insufficient to establish activation or picture use.
[Matroska codec mappings](https://www.matroska.org/technical/codec_specs.html) bind HEVC
CodecPrivate to hvcC and describe initialization updates via CodecState. Existing packet
admission already refuses CodecState/unsupported BlockGroup additions. The new source-only
reference path also refuses selected packet VPS/SPS/PPS; old source/frame/sample/crop behavior
is unchanged. [FFmpeg's hvcC implementation](https://ffmpeg.org/doxygen/8.1/hevc_8c_source.html)
was inspected for completeness serialization and hvc1/hev1 defaults. This is a primary
implementation, not independent access to the full ISO14496-15 normative contract; no such
contract or universal in-band update policy is newly qualified. No implementation code copied.

Fresh selected source hash/configuration, every signed encoded packet offset/size/hash and
escaped RPU, source/table counts, final source/spool identity/hash observations, qualified
normal checked database/source closes and awaited owning worker precede return. New source
path launches zero decoders. Source-only packet/RPU reconstruction is not one-picture or
exact rational decoder coverage. Explicit caller source/spool access and retained ownership
on shared uncertainty remain required; no new controller or automatic D149 integration.
No generic lease/receipt wrapper, closed-store adoption, Python runtime bridge, protocol,
app action, default packaging or recovery/cleanup authority.

Five new tests cover four NAL widths, raw completeness zero/one, finite maximum prefix IDs,
flags/sublayers, opaque suffix acceptance with false full-validation flag, missing/duplicate/
ambiguous/reserved/mismatched/unsupported/truncated/escape/overlong-ID refusal and cancellation.
Fresh source binding refuses stale configuration; freshly reconstructed changed PPS ID may
bind with activation false. Selected packet in-band parameter sets refuse. Five actual native
generated HEVC configurations (single/BlockGroup/wide VINT/conformance/24-picture open GOP)
report matching configuration prefix IDs and original packet/RPU counts. Conformance remains
coded176x112/visible162x98 syntax; no new decoder comparison. Record cap, read-pass/late task
cancellation, final same-byte source substitution, extra spool member and actual configured
eight-page SQLite-full refuse with source bytes unchanged. SQLite-full is not physical
ENOSPC. Synthetic prefix vectors are not valid complete parameter sets. Generated roots
remain private without adoption/deletion/group/production recovery authority.

Initial37tests3suites15.147s and expanded38tests3suites14.341s pass. A final reserved-array/base
header admission strengthening follows; no initial compiler/test failure was introduced.
Static host exact closure remains94 product Swift sources, compiling changed code but
executing prior companion preservation/review, not new references/SPS/crop/decoder loading.
Full final focus/ordinary/production/protection and parent hosted outcome follow completion.
No new C/runtime rebuild/copy, sanitizer/pixel oracle/APFS/DeveloperID/owner body/full-source/
UI execution, historical observer/assertion/deadline/skip workaround/global scheduling change.

Only originalParameterReferencePrefixesBoundToSource, configurationReferencePrefixesAgree and
selectedPacketParameterSetNALsAbsent become true after complete source-only settlement.
Full parameter-set conformance, active picture selection, source-frame/ROI provenance,
independent values and rendered/edited flags remain false. No progressive/SAR/color/HEVC
implementation/pixel/PQ-linear/EL/resize/Dolby conversion proof. Actual source VCL references,
first/dependent slice semantics, complete parameter-set interpretation and joint exact
source/config/packet/RPU/rational-clock/one-picture coverage/final settlement remain separate
prerequisites before coordinate-origin policy. Other resource/deinit/retirement/recovery/
distribution gates remain open; no whole-program completion or all-useful-work blockage claim.


Qualified focus38tests3suites14.590s PASSED/no warnings, including reserved critical-array and
base-layer header refusals. Final ordinary594reported tests/105suites211.401s PASSED38
unchanged explicit opt-in skips/no emitted warnings; new combined SPS/reference12.849s,
access33.552s/static prior companion32.041s. Explicit production21.30s/current strict ad-hoc
app/read-only helper signatures/minima14.0/11.0 pass; writer/decoder/sample/crop absent.
Six-file privacy zero/positive sentinel, owner metadata/journal/original sample-prefix-frozen-
D130/D142/D143 artifacts unchanged, planning findings empty. Generated new roots retained
privately, no new compiler/test failure in this unit or ordinary retry.

Parent PR125 automatic37297243724 failed589tests605.233s8issues: two unchanged120s bounds,
two metadata absent-positive-child assertions, missing generated pipe-holder marker,
Fresh-analysis cancellation8.160468vs5 and Rendering-candidate/Measuring-encoded-candidate
EOF expectations. SPS69.863s/fixture60.801s/access294.401s/static278.658s and exact shared
fixture preparation passed. Full failed log/summary retained and parent updated without
retry or individual cause attribution. D136's supported cold duplicated compilation
correction does not explain every residual or exclude defects. No historical observer,
assertion/deadline/CI margin/skip/global suite-job scheduling or concurrency workaround.
