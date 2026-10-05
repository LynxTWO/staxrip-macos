# Explicit decoded base-plane crop sample evidence

D142 adds a separate unbundled DEVELOPMENT C crop probe/core under
Tools/DolbyPictureCrops. It measures an explicit rectangle in coded or codec-visible
coordinates using actual progressive yuv420p10le FFmpeg plane buffer extents and
positive byte strides. Codec-visible origin is the decoded codec window. Container
crop/display metadata and user-session provenance are unsupported. Source reconstruction,
native profile/access integration and independent sample-value verification remain open.
No product Swift, original sample/reference tool, frozen or previously retained runtime
object changes. No app action/default packaging/release factory or proof flag upgrade.

Requests must be nonempty, bounded, even-phase 4:2:0 rectangles. Subtraction checks precede
bounded coordinate additions. Chroma coordinates/dimensions divide by two; full active-plane
storage extent is checked even for small ROIs. Canonical little-endian hashes, sample counts,
extrema, sums and squares stream without extra full-picture copies or pixel output. Results
are returned only after all three planes pass; late refusal leaves caller outputs untouched.
8192 dimension/16M sample/64MiB storage and per-allocation caps are configured limits, not
measured total memory or film-speed guarantees. Only requested code values are measured.

Distinct crop-begin/crop-packet/crop-frame/crop-complete version-one rows keep existing
metadata/sample protocols narrower. Emitted container-crop/source-ROI-provenance/independent-
sample-value/edited flags are false. Packet/frame/RPU/color declarations are observations,
not independent source binding, rendering, linear/PQ luminance, colorimetry, EL reconstruction,
resize or dynamic metadata conversion. All rendered/edited flags remain false. Complete
requires drain/final source observations/normal checked source close/zero exit and direct
child join. Inherited partial/error cleanup resource closes, group/escaped descendants and
mapped-image/distribution authenticity are not newly qualified.

Four generated test groups passed with installed libraries (3.377s) and a separately owned
compatible minimal LGPL macOS14 artifact (3.260s). Added explicit live deadline coverage
and prevented test-import bytecode output; final four-group runs passed installed3.211s and
compatible2.356s. Each run executes 24 accepted crop trials: five generated B-frame/BlockGroup/
VINT/conformance/open-GOP sources, both one/four threads and both coordinate spaces, plus
full conformance coded176x112 versus codec-visible162x98 rectangles. Three-plane hashes and
all statistics equal a raw-row-streamed FFmpeg CLI oracle with automatic cropping disabled
and the exact coded ROI applied. Coded/visible hashes differ. The oracle shares FFmpeg's
HEVC implementation; no independent decoder or production pixel-verification flag follows.

ASan/UBSan native AVFrame cases check known offset values/hashes, padded strides, actual
buffer extents, atomic late-plane refusal, unsupported format/interlace, even phase,
nonempty/in-bounds geometry and offset/overflow refusal. Malformed/unsupported arguments,
nonregular/symlink input, malformed source and broken stdout refuse completion. Repeated
2000-cluster generated production acknowledges an actual crop-frame and a live non-zombie
child before owned cancellation, a parent read deadline and same-content path substitution.
Direct joins are checked; substituted original/new source bytes remain unchanged. Existing/
symlink output builder refusal preserves prior output. Compiler deadline is configured but
not induced. Generated roots and new artifact copies remain retained privately.

The test-only native flock covers the same fixed D136 development Cargo feature/profile
and exact compiled named source generation. Shared outputs are not signed/mutated/deleted;
actual processing remains concurrent. Python only orchestrates generated C/oracle tests,
never an app runtime bridge. Installed compiler/explicit library identities and minimum14.0
are retained privately; original D129 probe/prefix, five D097 objects and D130 copies unchanged.
CI adds this exact generated crop suite without deadline/assertion/skip/job concurrency changes.

Ordinary543reported tests/101suites210.770s passed33unchanged opt-in skips/no emitted warnings.
Product unchanged: reuse D141 explicit production20.77s, not a new optimized execution.
New current strict ad-hoc app/read-only helper signatures pass, minima14.0/11.0; writer,
decoder/sample/crop absent. Static93-source hardened host runs its prior companion pipeline,
not sample/crop loading. Ten-file privacy/protected metadata/journal/runtime/planning checks
are recorded separately. No UI walkthrough/owner media/full-source/APFS/signing trial.

PR116 automatic37267245058 failed543tests529.299s9issues: two unchanged120s limits,
three metadata/two sample absent-positive-child assertions and two mastering phase EOF
expectations. Staging15.755s/fixture46.444s/static252.771s/access263.619s passed. Full failed
log retained/PR116 updated without retry. Individual causes remain unestablished; no
all-starvation or exclusion-of-logic-defects claim, historical observer or relaxed checks.

Next assess a distinct native crop role/profile using the existing concrete owning decoder
worker and bounded typed admission. Do not silently normalize crop rows into existing sample
rows or make provenance/source/edited flags true from shape. Independent source/ROI/config/
packet/RPU binding, concrete access/resource settlement and container/user origin remain
separate gates. D137-D141 retained stage pins/deinit/standalone error-drop and other helper/
disk resource gates remain unqualified; retention/energy expiry grants no recovery authority.
