# StaxRip Mac icon source

`scripts/IconArtwork.swift` is the original editable vector geometry and palette source. It emits full-canvas SVG layers plus default, dark and monochrome PNG previews. The shared `scripts/build-icons.command` helper used by build.command and package.command creates the multi-resolution ICNS from those renders. Generated PNG/ICNS files live in the build directory and are not committed.

The clapperboard motif references the official [StaxRip project](https://github.com/staxrip/staxrip), inspected at 2283bfd0a892542feecdbb813b1fcda144f7d610. The new stacked frames, continuous S ribbon, geometry and palettes were independently drawn for this Mac app; no upstream bitmap or vector was copied. Upstream's License.txt is MIT, copyright 2002-2026 StaxRip Authors. This provenance note does not select the Mac project's still-open software license.

The ICNS is the older-system fallback. Native layered Icon Composer integration is pending first-run license consent and qualification; the generated dark/mono previews alone do not establish automatic OS appearance support. Dock badges use AppKit and leave the underlying system icon intact.

Regenerate privately with `swift scripts/IconArtwork.swift .build/icon-review`, or build the ordinary app with `./build.command`.
