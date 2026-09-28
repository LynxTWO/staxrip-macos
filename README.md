# StaxRip Mac — working title

A native SwiftUI media workspace with real AVFoundation MP4 export. StaxRip is an inspiration, not a compatibility promise or a limit on the product. The long-term direction is a deeply capable Mac video and audio workstation; see [the roadmap](Docs/ROADMAP.md).

## Try it locally

Requires Xcode / Swift 6 and macOS 14 or newer. Run `./build.command`, then open `Preview/StaxRip.app`. Quit the previous app before rebuilding. The development app is ad-hoc signed, not notarized. Binaries and personal media are excluded from Git.

- **Workspace:** import local video, preview it, explore advanced settings, and create independent queue configurations.
- **Quick Export:** export a real MP4 using Apple's H.264 1080p, H.264 720p or HEVC 1080p preset. Choose a new destination. Progress, cancellation, result preview and Finder reveal are available.
- **Queue:** edit, duplicate, reorder and remove configurations. These advanced jobs do not execute yet.
- **Session:** explicitly save and reopen source references, workspace settings, output naming and queue. Source media is not copied. Queue-only JSON export is a reference format, not a session.
- **Appearance:** Auto, Light and Dark modes apply to this app only.

Keyboard shortcuts: Command-O opens media, Command-J adds a configuration, Command-Shift-S saves a session, and Command-Shift-O opens a session.

## What actually runs

Quick Export uses system AVFoundation presets, without downloading external tools. It does **not** apply the workspace's CRF, speed preference, cropping, audio selection, subtitle selection or advanced queue settings. Native presets control the output according to Apple's capabilities. They are not a precision archival or HDR metadata preservation guarantee. Frame size may remain smaller than the preset maximum.

AV1/SVT-AV1, x264/x265 command execution, external filters, batch processing, audio-only export, stream selection and subtitle management are not implemented. The illustrative alpine demo is synthetic. MKV and other formats may not preview through AVFoundation.

## File handling

Real exports are written in an operation-owned temporary directory beside the destination, checked for a readable video track, then published using an exclusive hard link. An existing destination, including a symlink, is never replaced. Cancellation and ordinary failures remove only the current operation's staging directory. Filesystems without hard-link support fail with an explanation; there is no destructive fallback. A forced app termination can leave its staging directory behind. Normal Quit is blocked during an active export until it finishes or is cancelled.

Sessions use a versioned `staxrip-mac-session` JSON envelope. Unsupported versions/settings, invalid local paths, duplicate queue IDs and exact output conflicts are rejected before replacing the workspace. Missing media retains its identity with a locate-source prompt. Opening a session never starts processing. Sessions are explicitly saved, not autosaved; save before quitting. Neither session nor queue JSON is a Windows StaxRip project file.

## Verification

Run `swift test`. Twelve Swift Testing tests pass locally, including a parameterized media test covering all three presets. Generated video plus a synthetic audio tone verifies H.264/HEVC video, AAC audio, duration and source preservation. Other checks cover active/pre-start cancellation, staging cleanup, existing files and dangling symlinks, malformed sessions, document round-trip and queue isolation/reordering.

Native UI checks on the development Mac cover import/playback, preset changes, queue edits and JSON export, output conflict feedback, actual export → preview, session save → change settings → restore, and light/dark rendering. The SwiftUI VideoPlayer wrapper crashed on the original runtime; the AppKit AVPlayerView bridge passed the same playback check.

Local verification used Apple Silicon and Swift 6.4. Older macOS versions, Intel hardware, long media, HDR, multitrack audio, network destinations and distribution signing remain unverified. GitHub Actions is configured for macOS 15, but jobs are currently blocked before startup by an account billing/spending-limit restriction. No hosted CI pass is claimed.

## Structure

- `WorkspaceModel.swift`: source loading, editable settings and queue operations.
- `SessionDocument.swift`: versioned documents and validation.
- `WorkspaceView.swift`, `QueueView.swift`, `QueueEditor.swift`: native workspace and configuration UI.
- `NativeExport.swift`: system preset export, progress, cancellation and exclusive publication.
- `QuickExportView.swift`: real export workflow.
- `NativeVideoPreview.swift`: AppKit playback bridge.
- `AlpinePreview.swift`: synthetic artwork drawn in SwiftUI.
- `Resources/Info.plist`: local app bundle metadata.

See [development guidance](AGENTS.md), [architecture](Docs/ARCHITECTURE.md), and [roadmap](Docs/ROADMAP.md).
