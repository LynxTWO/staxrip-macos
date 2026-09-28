# StaxRip for Mac — GUI prototype

A standalone SwiftUI design prototype. Open `Preview/StaxRip.app` on this Mac.

## Working interactions

- Open a local video with Open source or Command-O, or drop it onto the preview.
- Preview AVFoundation-compatible video with native playback controls. Source dimensions, frame rate and duration are read from the file.
- Choose AV1, HEVC or H.264; adjust quality, speed preference, output size, crop, audio, subtitle handling and container.
- Apply the three quick presets (video codec, encoder, CRF and container).
- Choose a destination, add configuration snapshots with Command-J, remove queue entries, and export the queue as JSON.
- The app follows the Mac's light/dark appearance.

## Prototype boundaries

The initial landscape is an illustration, with clearly labeled synthetic source metadata. No encoder, filter, muxer, track discovery, compatibility validation, or tool downloading is connected. Picture settings do not modify playback. Speed is a conceptual preference, not a backend command-line setting. Some files, especially MKV, may not preview through AVFoundation.

The queue is held in memory and clears on quit. Export is an explicit save-panel action. Its JSON is a prototype format, not compatible with Windows StaxRip project files. Output names are proposed only; no media is created or overwritten. The app does not alter the existing Windows StaxRip repository.

## Build and iterate

Requires Xcode / Swift 6 and macOS 14 or newer. This version was built locally using Swift 6.4 on Apple Silicon; older OS versions and Intel Macs are untested.

1. Open `Package.swift` in Xcode, or edit `Sources/StaxRipMac/` in Codex.
2. Run `./build.command` from Terminal (or double-click it).
3. Quit and reopen `Preview/StaxRip.app` to see the build. This is rebuild/relaunch iteration, not hot reload.

The local app is ad-hoc signed for development and is not a notarized distribution.

## Structure

- `WorkspaceModel.swift`: source loading, editable settings and queue snapshots.
- `WorkspaceView.swift`: workspace, sidebar, settings and output inspector.
- `QueueView.swift`: session queue and export action.
- `NativeVideoPreview.swift`: AppKit playback bridge.
- `AlpinePreview.swift`: synthetic demo artwork drawn in SwiftUI.
- `StaxRipMacApp.swift`: app entry and keyboard commands.

Next implementation decision: agree on the GUI and encoding backend boundary before connecting real processing or persistent project files.

## Verified on this Mac

- Swift debug build and local app signing succeeded.
- The native window was visually reviewed; preview height was reduced to expose the encoding controls.
- Selecting Everyday HEVC changed codec, encoder, CRF and container together.
- Adding, viewing, exporting and removing a queue configuration succeeded. The exported JSON was parsed and its HEVC settings and demo flag checked.
- A generated 640 × 360 H.264 MOV loaded as 30 fps and two seconds; playback reached the end.
- Picture, audio and subtitle tabs opened with the imported video present.
- The initial SwiftUI VideoPlayer caused a runtime metadata crash on this machine. The final AppKit AVPlayerView bridge passed the same import and playback check.

Drag-and-drop, every codec/container combination, older macOS versions, and distribution signing remain unverified. Encoding is deliberately unimplemented.

## Second GUI pass

Output names are now editable; the extension follows the selected container. Empty names, path separators, exact source/output collisions and exact duplicate queue destinations are rejected. This is configuration validation, not a filesystem overwrite guarantee; the eventual encoding backend must check existing files, aliases and volume case sensitivity.

Queue items support Edit, Duplicate, Move up and Move down. Editing uses an isolated draft, and Cancel discards it. Duplicate generates a distinct destination name. The workspace and other queue items retain their settings. A return-to-demo button appears beside an imported source and also cancels pending source loading.

Verification: four Swift Testing tests passed for destination conflicts, independent copies and edits, queue ordering boundaries, invalid filenames/source collisions, and demo reset preservation. Native UI checks confirmed the disabled Add button on duplicate destination, duplicate naming, the edit sheet's conflict warning and disabled Save button, independent CRF editing, and reordered queue rows. The queue editor and queue were visually reviewed. The final app is left open with two clearly marked demo configurations for exploration.

Run the focused tests with `swift test` from this directory.
