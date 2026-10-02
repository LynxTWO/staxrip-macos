# StaxRip Mac icon source

`scripts/IconArtwork.swift` is the original editable vector geometry and palette source. It emits full-canvas SVG layers plus default, dark and monochrome PNG previews. The shared `scripts/build-icons.command` helper used by build.command and package.command creates the multi-resolution ICNS from those renders. Generated PNG/ICNS files live in the build directory and are not committed.

The clapperboard motif references the official [StaxRip project](https://github.com/staxrip/staxrip), inspected at 2283bfd0a892542feecdbb813b1fcda144f7d610. The new stacked frames, continuous S ribbon, geometry and palettes were independently drawn for this Mac app; no upstream bitmap or vector was copied. Upstream's License.txt is MIT, copyright 2002-2026 StaxRip Authors. This provenance note does not select the Mac project's still-open software license.

`StaxRip.icon` is the editable Icon Composer project: eight SVG layers in four depth groups, a teal default background and native system dark background. The system derives the monochrome material from the same layers. SVG rotations are flattened and the stripes fit inside the clapper without clipping, avoiding differences in Apple's SVG importer. The SVGs are generated from IconArtwork.swift; the build checks that the committed editable assets have not drifted from that source. Edit geometry/palettes in Swift, regenerate the default SVGs into StaxRip.icon/Assets, and edit native materials/groups in Icon Composer.

With a macOS 26 or newer SDK, the shared helper compiles the project using actool, installs Assets.car and sets CFBundleIconName. Compilation errors fail the build. Older SDKs install the multi-resolution ICNS without advertising a missing catalog. The full ten-resolution fallback is retained even in modern bundles; sidebar light/dark PNGs are separate app resources. Generated dark/mono PNG previews are design references, not the native system appearances. Dock badges use AppKit and leave the system icon intact.

Regenerate privately with `swift scripts/IconArtwork.swift .build/icon-review`, or build the ordinary app with `./build.command`.
