# Original configuration SPS geometry prefix

D150 adds an unused source-only SPS prefix finding on the existing pinned synchronous
source/open SQLite worker. It reconstructs the selected original TrackEntry/configuration
and compares number, offset, payload size/hash, configuration size/hash and NAL width before
reading the same CodecPrivate bytes. Existing hvcC framing admission precedes exactly one
SPS occurrence; missing, multiple and byte-identical duplicates refuse. No first-SPS choice.
Original source hash, signed encoded packet offsets/bytes/hashes, escaped RPUs, source/table
counts, final source/spool identity/hash observations, normal checked SQLite/source closes
and awaited worker precede return. The new path refuses selected packet VPS/SPS/PPS NALs;
older source/frame/sample/crop paths keep their existing admission. This absence check does
not prove active picture selection. No decoder is launched by the new source-only path.

The bounded base-layer 10-bit 4:2:0 subset reads VPS/SPS IDs, sublayer count, profile IDC,
raster, conformance-window offsets and depths. Entire bounded NAL payload receives strict
emulation-prevention removal; PTL constraint bits and the SPS suffix remain opaque. Finite
bit reads and bounded Exp-Golomb values precede subtraction-based crop bounds; configured
raster range is 2...16384 with even dimensions and 4:2:0 offsets scaled by two. This is a
prefix readback, not a complete SPS validator, VPS/PPS relation or slice selection parser.
Arbitrary shape-valid suffix can pass while completeSPSConformanceVerified stays false.
No source picture, codec-origin, progressive, color or SAR facts are inferred.

Primary source inspected: [ITU-T H.265 V11, January 2026](https://www.itu.int/rec/dologin_pub.asp?id=T-REC-H.265-202601-I%21%21PDF-E&lang=e&type=items),
sections 6.2, 7.3.1, 7.3.2.2.1, 7.3.3, 7.4.2.1 and 7.4.3.2.1. SPS syntax places the geometry
prefix after profile-tier-level; sublayer presence controls fixed-width regions. The chroma
format determines window units. Emulation-prevention bytes are removed before RBSP bit
interpretation. We preserve unparsed constraints/suffix as explicit limits. Also inspected
[FFmpeg's HEVC parameter-set implementation](https://ffmpeg.org/doxygen/8.1/hevc_2ps_8c_source.html)
for the distinction between parsed SPS window facts and PPS/SPS activation. No implementation
code is copied. The privately retained official PDF/selected-page/source receipt records
what was inspected, not validation of every standard field or independent HEVC decoding.

Seven new tests cover all four NAL widths and sublayer counts 0...6, finite known prefix
geometry, no-window readback, reserved/header/escape/truncation/duplicate/missing/unsupported
chroma/depth/raster/window/overlong-Golomb refusal, checkpoint cancellation and opaque suffix
acceptance with false complete-validation flag. Seven forged selected Track facts and stale
configuration refuse; a freshly reconstructed changed source can bind its new prefix.
Synthetic prefix vectors are not valid complete SPS streams. Opt-in in-band VPS/SPS/PPS
refusals leave the older source API narrower and preserve source bytes. Source record cap,
actual eight-page SQLite-full, read-pass and late task cancellation refuse after worker
settlement; configured SQLite-full is not physical ENOSPC. No helper launches in these cases.

Five actual generated HEVC configurations from the existing native Rust fixture generator
(single, BlockGroup, wide VINT, conformance and 24-picture open GOP) bind original source
and packet/RPU counts. Conformance reports coded176x112/window right-bottom14/visible162x98;
other generated fixtures report160x96. This is source syntax, not a new decoder comparison,
full SPS conformance, one-picture coverage or independently measured pixels. Final same-byte
source substitution and extra spool member refuse. Generated review roots remain private;
source/prior captured runtimes are preserved. No new C probe/build, decoder runtime copying,
pixel oracle, sanitizer, APFS, DeveloperID, owner media body/full-source or UI qualification.

Initial composed32tests3suites14.426s failed two NEW fixture admissions: newly created spool
folders lacked required private permissions. Failed log retained, fixture permissions
corrected without product policy change. Three existing warning sites emitted on broad
recompilation (AV1CopyTests/ChapterPersistenceTests async Thread.isMainThread and unused
DolbyAssociationSpoolTests result), not newly introduced warning sites. Corrected new-only
6tests0.679s and expanded composed33tests3suites14.207s pass. Static host exact closure now
94 product Swift sources, deliberately adding the new parser. It compiles this code but
executes prior preservation/review, not the new SPS path or decoder/crop loading.
Full ordinary/production/protection outcomes follow after completion.

Only originalConfigurationSPSPrefixBoundToSource and selectedPacketParameterSetNALsAbsent
become true after complete source-only settlement. Active picture parameter selection,
complete SPS conformance, source-frame/ROI provenance, independent values and rendered/edited
semantics remain false. Full source/config/packet/RPU/exact rational timing/one-picture
coverage/final counts/observations/qualified closes/owned joins remain required for a later
joint upgrade. D149 explicit grants/pins/activity/retained policy still applies to concrete
controller integration; the new narrow entry requires caller-owned access and retention on
shared uncertainty. No new controller, generic wrapper, second worker, closed-store adoption,
protocol, default packaging, app action or recovery/cleanup authority. Other resource/deinit/
retirement/recovery/distribution and container/user origin gates remain separate and open.

PR124 automatic37293266414 failed582tests537.544s38issues: 21 unchanged120s/seven180s bounds
and ten other assertions (five metadata/one sample absent-positive-child assertions, two crop
role/child assertions and Fresh-analysis/Rendering-candidate EOF expectations). Full log and
summary retained, PR124 updated without retry or per-issue cause attribution. D136 addresses
a supported cold duplicate compilation mechanism; it does not explain every residual or
exclude logic defects. No historical observer, deadline/assertion relaxation, CI margin,
new skip workaround or global suite/job scheduling/concurrency change.


Final ordinary589reported tests/105suites213.417s PASSED38 unchanged explicit opt-in skips,
no emitted warnings. New SPS suite10.952s/access33.906s/static prior companion32.025s passed.
Explicit production21.61s/current strict ad-hoc app/read-only helper signatures/minima14.0/
11.0 pass; writer/decoder/sample/crop absent. Eight-file privacy zero/positive sentinel,
owner source metadata/current journal/original D142/sample-prefix-frozen-D130/D143 runtime
unchanged; planning findings empty. New generated source-prefix review/bounds roots retained
privately without cleanup/adoption/recovery authority. No ordinary retry or new C/runtime/
pixel oracle/sanitizer/APFS/DeveloperID/owner body/full-source/UI execution. Active VPS/PPS/
slice selection, complete SPS conformance and concrete controller integration remain next
prerequisites before any joint geometry/origin upgrade. No whole-program completion claim.
