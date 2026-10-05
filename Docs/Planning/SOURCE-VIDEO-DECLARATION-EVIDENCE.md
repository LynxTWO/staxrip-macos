# Selected original source Video declarations

D147 adds a distinct unused source-only declaration finding on the existing pinned
synchronous source/open SQLite worker. It reuses D112's bounded selected Video parser,
reconstructs D109's selected TrackEntry/configuration again and compares its original
offset, size, hash, track number, configuration size/hash and NAL width before parsing.
Original source hash, signed encoded packet locations/bytes/hashes and every escaped RPU
still come from independent source reconstruction. Source/table counts, final source and
spool observations, normal checked SQLite/source closes and awaited worker precede return.
No companion member, closed-spool adoption, decoder, second worker, generic receipt/lease
wrapper, Python runtime bridge, protocol change or app action is introduced. Existing
narrower source/decoder APIs retain their admission subset and false lower-level flags.

Recognized present fields distinguish omission from explicit zero. Raw crop defaults,
absent display fields, DisplayUnit and optional DefaultDuration remain separate. The new
effective display declaration applies width/height defaults only for pixel DisplayUnit 0;
physical, aspect-ratio and unknown units do not receive invented dimensions. Display values
remain declarations, not decoded dimensions, decoder origins, sample aspect ratio or edits.
The parser keeps its existing 2...16384 pixel subset rather than claiming the whole schema.

Primary sources inspected: [Matroska technical elements](https://www.matroska.org/technical/elements.html)
and [official element schema](https://raw.githubusercontent.com/Matroska-Org/matroska-specification/master/ebml_matroska.xml).
Pixel dimensions describe encoded frames; PixelCrop fields default to zero; display
dimensions apply after crop and have pixel-unit defaults only. Units 1/2/3/4 mean physical
centimetres/inches, aspect ratio and unknown. These declarations alone do not establish
their relation to a decoded SPS conformance window. The fixed crop probe disables automatic
cropping; [FFmpeg AVFrame](https://ffmpeg.org/doxygen/trunk/structAVFrame.html) and
[AVCodecContext](https://ffmpeg.org/doxygen/trunk/structAVCodecContext.html) document separate
coded/frame, display and crop behavior. D098 proposals require explicit independently bound
origins; no automatic source PixelWidth-to-codec-visible mapping is made here.

Six new tests cover all four NAL widths and finite/unknown Segments, signed duplicate and
nonmonotonic packet rows, default and explicit presence, all five display units, partial or
missing display dimensions, ignored unrelated Video fields, missing/duplicate/overflow/
invalid declarations, seven plausible forged Track facts and stale same-sized Video payload.
A repaired actual Track fact admits the changed source declaration; this is source-dependent
readback, not immutable provenance. The older narrow source pass still admits missing Video.
Configured record cap and actual eight-page SQLite-full refuse; not physical disk ENOSPC.
Source-pass/late task cancellation, extra spool member and same-content source substitution
refuse after the owning worker joins. No new early/source-only path launches a decoder.

Actual generated Rust original fixtures in both retention modes use the owned native writer,
native source-audit verifier and existing independent test-only Python semantic oracle.
After those helpers settle, the generated companion is removed and the new worker reads
original source alone. It observes explicit unit-3 16:9 declarations, four encoded packets,
five duplicate-preserving RPUs and one enhancement NAL; source bytes remain unchanged.
This is not one-picture coverage or independent decoded geometry. Test oracle is not an app
runtime bridge. Initial new fixture assertions incorrectly used a different generator's
zero-crop/pixel-unit declarations; six issues retained, exact selected fixture expectations
corrected. No product policy, historical assertion/deadline or scheduling change.

Initial unchanged28tests2suites2.136s and new32tests2suites2.270s passed. Corrected composed
35tests3suites14.130s passed/no warnings, including the prior93-source static hardened host.
That host compiles these changed files but executes prior preservation/review, not this new
source-only finding or decoder/crop loading. No new C probe/runtime/sanitizer/oracle pixels/
APFS/signing/owner media/full-source/UI qualification. Full regression/build/protection
outcomes follow after completion.

Only originalVideoDeclarationsBoundToSource becomes true. Source-frame, source ROI
provenance, independent sample values and edited flags remain false. D127/D144 exact rational
timing and one-picture/RPU coverage remain required for future source/decoder crop composition.
Container/user origins, SAR, independently remeasured pixels, HEVC implementation, PQ/linear
luminance, colorimetric rendering, enhancement reconstruction, resize and Dolby conversion
remain unqualified. D145 explicit access/retention and D146 finite admission contracts remain
in force; this narrower worker is not a new access controller or cleanup/recovery authority.
Other admitted components/directories/deinit, retired stage pins and distribution gates stay
open. No default packaging, release Tool, publication/import/adoption or whole-program claim.

PR121 automatic37283533521 failed566tests567.194s13issues: two unchanged120s/two180s bounds
and nine other assertions: two metadata/three sample absent-positive-child assertions, crop
close-role/child assertions and two mastering phase EOF expectations. Full log retained and
PR121 updated without retry. Individual residual causes remain unestablished; D136's supported
cold duplicated compilation correction does not prove all downstream starvation or exclude
logic defects. No historical observer, CI margin, deadline/assertion relaxation, new skip or
global suite/job scheduling/concurrency change.


Final ordinary572reported tests/104suites230.384s PASSED36 unchanged explicit opt-in skips
and no warnings, access32.313s/static prior companion32.038s. Explicit production21.22s/
current strict ad-hoc app/read-only helper signatures/minima14.0/11.0 pass; writer/decoder/
sample/crop absent. Six-file privacy zero/positive sentinel, owner source metadata/current
journal/original D142/sample-prefix-frozen-D130/D143 runtime unchanged. Missing decision index
row corrected; planning findings empty. No product UI change or native UI qualification.
Evidence-time regex corrected to observed whitespace before sec without build rerun or repo
mutation. Other source/component/directory/deinit/retired-stage/distribution/recovery gates
remain open. Next finite source Video plus actual fixed decoder geometry/caller agreement
must run on the same source/open-store worker and retain false ROI/value/rendered/edited
flags until exact independent coordinate provenance is qualified; never infer default SAR.
