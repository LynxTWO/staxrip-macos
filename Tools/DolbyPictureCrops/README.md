# Development explicit base-plane crop probe

A separate unbundled C artifact measures an explicit half-open luma rectangle in
progressive `yuv420p10le` base planes. Requests name `coded` or `codec-visible`
coordinates, then x/y/width/height. Codec-visible origin is the current decoded
frame's codec window; container crop/display metadata and user-session crop
provenance are unsupported. Values are raw 10-bit codes, never linear luminance,
colorimetric rendering, EL reconstruction, resize or Dolby metadata conversion.

```sh
python3 Tools/DolbyPictureCrops/build.py --output /explicit/new/crop-probe
/explicit/new/crop-probe /explicit/generated/source.mkv --threads 1 --coded-roi 2 2 16 10
/explicit/new/crop-probe /explicit/generated/source.mkv --threads 4 --codec-visible-roi 0 0 162 98
python3 Tools/DolbyPictureCrops/test_crops.py -v
```

Only installed compiler/system frameworks and explicitly selected installed FFmpeg
libraries are used; `PKG_CONFIG_PATH` can select a trusted development prefix.
The builder refuses an existing/symlink output and publishes exclusively. Failed or
unsettled compiler stages are retained. No default app packaging or release capability.
Artifact and dependency identities/deployment targets need separate admission.
Ordinary development execution is not hardened/Developer ID distribution trust.

`roi.h` resolves requested geometry using subtraction before bounded addition. It
requires even x/y/width/height and codec offsets on the 4:2:0 grid, nonempty in-bounds
rectangles, supported progressive format and bounded geometry. It reads each actual
FFmpeg plane buffer/positive byte stride through the existing sample measurement
core. Full active-plane storage extent is checked even for a small ROI; only requested
sample values are measured. Chroma coordinates/dimensions divide by two. Padding is
excluded from canonical little-endian hashes. Three-plane summaries/absolute rectangle
are returned only if every plane succeeds. No extra full-picture copy/pixel payload.
Existing 8192 dimension/16M sample/64MiB storage/per-allocation caps are not total-memory,
physical-I/O preemption or whole-film performance guarantees.

Distinct crop-begin/crop-packet/crop-frame/crop-complete JSONL is not the existing
metadata or sample profile. No native admission/controller/association/access factory
is added. Packet/frame/RPU rows and color declarations are observations, not independent
source reconstruction, ROI provenance or independently remeasured samples. The emitted
provenance/sample-value/edited flags remain false. EOF/zero exit/final selected-source
observations/normal checked source close/owned direct join are still required; partial
rows are not completion. Inherited partial/error cleanup resource closes and all mapped
image/process-group/escaped-descendant assurance remain separate unqualified concerns.

Tests use actual generated sources with B-frame reorder, BlockGroup, wider VINT,
codec conformance and open GOP across one/four threads, both coordinate spaces, and
full coded-versus-visible conformance rectangles. A separate FFmpeg CLI oracle disables
automatic cropping, applies the exact coded ROI and streams one raw row at a time.
It shares FFmpeg's decoder, not an independent HEVC implementation. Sanitizer checks
cover known offsets/plane values, atomic late-plane refusal, format/interlace/phase/
storage/overflow bounds. Finite test-only native flock coordinates the same development
Cargo profile and exact named source generator used by D136; no shared artifact mutation.
Python orchestrates generated tests only, never an app runtime bridge. Generated roots
remain retained; test direct joins do not grant cleanup or universal descendant authority.
