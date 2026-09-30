# StaxRip Mac — working title

A native SwiftUI media workspace with native AVFoundation export and a real FFmpeg batch engine. StaxRip is an inspiration, not a compatibility promise or a limit on the product. The long-term direction is a deeply capable Mac video and audio workstation; see [the roadmap](Docs/ROADMAP.md).

## Try it locally

Requires Xcode / Swift 6 and macOS 14 or newer. Run `./build.command`, then open `Preview/StaxRip.app`. Quit the previous app before rebuilding. The development app is ad-hoc signed, not notarized. Binaries and personal media are excluded from Git.

- **Workspace:** import local video, preview it, explore advanced settings, and create independent queue configurations.
- **Quick Export:** export a real MP4 using Apple's H.264 1080p, H.264 720p or HEVC 1080p preset. Choose a new destination. Progress, cancellation, result preview and Finder reveal are available.
- **Audio Lab:** open audio or video separately, select one audio track, measure integrated loudness/true peak/range, and export AAC, Opus, 24-bit FLAC or WAV. Explicit sample rate and mono/stereo conversion, plus optional measured loudness normalization. Audio Lab state is not included in video sessions.
- **Queue:** edit, duplicate, reorder and remove configurations. Run sequential FFmpeg encodes with progress, cancellation, verification and Finder reveal.
- **Session:** explicitly save and reopen source references, workspace settings, output naming and queue. Source media is not copied. Queue-only JSON export is a reference format, not a session.
- **Appearance:** Auto, Light and Dark modes apply to this app only.

Keyboard shortcuts: Command-O opens media, Command-J adds a configuration, Command-Shift-S saves a session, and Command-Shift-O opens a session.

## What actually runs

Quick Export uses system AVFoundation presets, without downloading external tools. It does **not** apply the workspace's CRF, speed preference, cropping, audio selection, subtitle selection or advanced queue settings. Native presets control the output according to Apple's capabilities. They are not a precision archival or HDR metadata preservation guarantee. Frame size may remain smaller than the preset maximum.

The advanced queue discovers FFmpeg and ffprobe in the standard Apple Silicon or Intel Homebrew locations. Install the optional tools with `brew install ffmpeg`; they are not bundled or downloaded by the app. The queue applies SVT-AV1/x264/x265, CRF, speed, crop, fit-to-size scaling, AAC/Opus/audio passthrough, subtitle passthrough and container settings. It encodes the first non-cover video and the selected audio/subtitle tracks (all tracks by default). Incompatible container/codec combinations fail explicitly. The media inspector shows probed track details.

The default advanced pipeline accepts 8-bit SDR 4:2:0. Supported right-angle display matrices on progressive square-pixel sources are applied before crop, with deinterlacing Off; mirrored or ambiguous transforms are refused. The separate static HDR10 workflow has a strict source/output audit and narrower settings contract; see Docs/Planning/HDR10-EVIDENCE.md. Queue execution stops on the first failure; completed jobs are skipped in the current session. Execution status is not saved in session documents. The last started batch is recorded separately in a local recovery journal. The illustrative alpine demo is synthetic. MKV and other formats may not preview through AVFoundation.

## File handling

Real exports are written in an operation-owned temporary directory beside the destination, checked for a readable video track, then published using an exclusive hard link. An existing destination, including a symlink, is never replaced. Cancellation and ordinary failures remove only the current operation's staging directory. Filesystems without hard-link support fail with an explanation; there is no destructive fallback. A forced app termination can leave its staging directory behind. Normal Quit is blocked during an active export until it finishes or is cancelled.

Sessions use a versioned `staxrip-mac-session` JSON envelope. Unsupported versions/settings, invalid local paths, duplicate queue IDs and exact output conflicts are rejected before replacing the workspace. Missing media retains its identity with a locate-source prompt. Opening a session never starts processing. Sessions are explicitly saved, not autosaved; save before quitting. Neither session nor queue JSON is a Windows StaxRip project file.

## Verification

Run `swift test`. Automated Swift Testing coverage includes a parameterized media test covering all three native presets. Current test receipts and opt-in skips are recorded in Docs/Planning evidence ledgers. Generated video plus a synthetic audio tone verifies H.264/HEVC video, AAC audio, duration and source preservation. Real FFmpeg tests cover AV1/H.264/HEVC, Opus, crop dimensions, literal path arguments, cancellation of an active encode followed by retry, HDR rejection and stop-on-failure. Audio tests exercise all four output formats, channel/sample-rate/duration checks, source preservation and overwrite refusal. A two-track fixture verifies a measured 6 dB difference and that exported signal levels follow the selected track. Other checks cover active/pre-start cancellation, staging cleanup, existing files and dangling symlinks, malformed sessions, document round-trip and queue isolation/reordering.

Native UI checks on the development Mac cover import/playback, preset changes, queue edits and JSON export, output conflict feedback, actual export → preview, session save → change settings → restore, light/dark rendering, media inspection and a completed AV1 queue job. The SwiftUI VideoPlayer wrapper crashed on the original runtime; the AppKit AVPlayerView bridge passed the same playback check.

The v0.6 labeled-panel layout avoids the native inspection helper crash reproduced with the populated GroupBox layout. Native UI checks now cover WAV import → loudness analysis → FLAC export and a completed H.264 batch → Quit → relaunch → explicit restoration. Full forced-crash UI and all audio-control combinations remain pending. See [validation notes](Docs/VALIDATION.md).

Local verification used Apple Silicon and Swift 6.4. Older macOS versions, Intel hardware, representative long media, calibrated HDR displays, multichannel mastering, network destinations and distribution signing remain production-validation gaps. GitHub Actions runs on macOS 15; the earlier billing block was resolved after the repository became public. Hosted passes and their exact scope are recorded in Docs/Planning evidence documents.

## Structure

- `WorkspaceModel.swift`: source loading, editable settings and queue operations.
- `SessionDocument.swift`: versioned documents and validation.
- `WorkspaceView.swift`, `QueueView.swift`, `QueueEditor.swift`: native workspace and configuration UI.
- `ToolRunner.swift`, `EncodePlan.swift`, `BatchController.swift`: discovered tools, bounded process execution, validated plans and sequential jobs.
- `MediaInspectorView.swift`: source track details.
- `AudioEngine.swift`, `AudioLabView.swift`: individual track export and source loudness measurement.
- `NativeExport.swift`: system preset export, progress, cancellation and exclusive publication.
- `QuickExportView.swift`: real export workflow.
- `NativeVideoPreview.swift`: AppKit playback bridge.
- `AlpinePreview.swift`: synthetic artwork drawn in SwiftUI.
- `Resources/Info.plist`: local app bundle metadata.

See [development guidance](AGENTS.md), [architecture](Docs/ARCHITECTURE.md), and [roadmap](Docs/ROADMAP.md).

## Local release-mode archive

Run `./package.command` to build an optimized, ad-hoc signed app and ZIP in a unique `Distribution/DeveloperPreview.*` directory. This is a local developer artifact, not a notarized public release. FFmpeg stays external. A Developer ID Application identity and notarization setup are still required for ordinary distribution outside the development Mac.

## Queue recovery

The app records the last started batch in `~/Library/Application Support/StaxRipMac/last-batch.json`. This local file contains source/output paths and configurations, with owner-only file permissions. It is separate from explicitly saved video sessions and does not autosave subsequent workspace edits. A new batch replaces the previous record.

After relaunch, Queue offers **Restore previous queue** when the current queue is empty. Active states become Interrupted; jobs never resume automatically. Completed jobs whose output still exists remain historical completions and are skipped. Missing outputs become reviewable failures. Existing output content is not revalidated on restore. If the app stopped between publication and recording completion, the job is Interrupted and a retry refuses to replace the existing output. Partial staging files are not automatically deleted.

A journal write failure before processing prevents that batch from starting; later failures stop processing before the next unsafe transition. If recording completion fails after output publication, the output stays Completed in memory and a recovery warning is shown. A process-held lock prevents simultaneous batch writers using the same journal. It is released by the OS when the process ends.

## Measured audio normalization

Audio Lab can target −23, −16 or −14 LUFS. It measures after resampling/channel conversion, then supplies those measurements to FFmpeg loudnorm for a second pass with a −1.5 dBTP target and 11 LU range setting. FFmpeg may use dynamic processing when linear gain cannot meet its constraints; this can change dynamics. The encoded output is measured again and published only within ±0.5 LU of the requested integrated loudness and at or below −1 dBTP. Silent/unmeasurable inputs and failed verification produce no published output. Analysis and verification require extra full-file passes. The separate Analyze loudness button always measures the unprocessed source track.

## Picture and timeline (v0.8)

Picture settings now support four-edge cropping, frame-rate-preserving BWDIF deinterlacing (flagged or all frames), and start/end times in seconds. End = 0 uses the source end. Trimmed jobs require AAC/Opus or no audio, and removed subtitles; chapters are omitted. Invalid ranges and crops fail before encoding. Output verification checks original-size cropped dimensions and duration. Resized dimensions, unusual timestamps and long/VFR inputs need broader validation. Native preview remains unfiltered.

New sessions use version 2 so older builds reject settings they cannot execute; this build still reads version 1 with neutral picture defaults.

## Track routing

Choose tracks in Workspace or a queue item to keep individual audio and subtitle streams by index, codec and language. All is the legacy default; None removes the category. Codec/handling settings still apply. New source imports reset selection; saved sessions and job copies preserve it. A changed or missing index fails preflight instead of silently substituting another track. Subtitle copying still depends on the target container. One common audio encoding recipe applies to every selected audio track.

Current sessions use version 3 and recovery journals version 2; older files remain readable, while older builds reject these new versions rather than ignoring routing or picture settings.

## Video rate control (v0.9)

Software AV1/x265/x264 support constant quality or single-pass target bitrate (100–200,000 kb/s). H.264/HEVC also offer Apple hardware via VideoToolbox in target-bitrate mode. Hardware requests pass `-allow_sw 0`; unsupported systems fail explicitly. CRF and software presets are absent from hardware plans. The target is not a constant-bitrate or exact-file-size promise. Selecting a built-in preset resets the engine/rate mode to that preset’s software CRF defaults.

Run hardware integration checks explicitly with `STAXRIP_TEST_HARDWARE=1 swift test`. Both codecs passed on the development Apple Silicon Mac; hosted CI skips hardware tests by default. Current session/recovery versions are 4/3 and retain older-version read support.

## Mastering foundation (v0.10)

Audio Lab accepts decimal LUFS targets and a maximum LRA. Smart master prefers constant gain when feasible; experimental Night / Venue applies linked compression and dynamic normalization, starting at −18 LUFS / 3 LU. Final encoded measurements are shown and verified before publication. Per-channel audits and user-selected dialogue-passage measurements use actual decoded audio. Neither tags nor centre-channel presence establish dialogue loudness. Dialogue measurements do not yet control mastering gain.

This foundation uses FFmpeg; it is not the requested finished original or best-in-class normalizer. The [research and acceptance plan](Docs/LOUDNESS-DESIGN.md) identifies the independent meter, adaptive planner, dialogue detector, multichannel contract and listening tests still required. The [release ledger](Docs/RELEASE-SCOPE.md) tracks the broader product gaps.

### Picture comparisons and saved recipes

**Preview picture** renders original and filtered SDR BT.709 stills with matching source timestamps. It uses the queue's crop, resize and deinterlace plan, offers fit/100 percent views, and marks old results out of date. It does not preview compression quality or HDR display output. See [scope and evidence](Docs/Planning/PICTURE-PREVIEW-EVIDENCE.md).

**My presets** saves source-independent encoding recipes. Crop, trim, selected source tracks and paths are excluded; applying a recipe retains those values in the current workspace. **Undo settings** and **Redo** affect workspace configuration only, not queue jobs or text editing. Library writes detect conflicts from another app instance; Reload resolves a stale snapshot after review. Preset automated, native and hosted checks passed within [the documented scope](Docs/Planning/CUSTOM-PRESET-EVIDENCE.md).

**Check queue** reviews sources, destinations and settings before you start. It reports preliminary issues without encoding or writing output/recovery files. Editing a job or changing discovered tools invalidates the results. Hardware availability and full HDR checks remain deferred to execution; a pass does not guarantee disk capacity or future file availability. See [preflight evidence](Docs/Planning/QUEUE-PREFLIGHT-EVIDENCE.md).

Batch cleanup failures now stop the current run and identify the remaining temporary directory. A published output stays **Completed** and available through **Reveal output**; cancellation or encoder failure retains its original outcome. Recovery preserves the warning. Only the current operation’s staging is removed; older leftovers are not swept automatically. See [cleanup evidence](Docs/Planning/BATCH-CLEANUP-EVIDENCE.md).

**Inspect media contents** separates tracks, chapters and embedded attachments, including cover artwork. Chapter titles/times and declared file names/types are reported metadata; missing values stay explicit. The inspector bounds large lists and labels, does not extract attachments, and does not certify output preservation. See [container inspection evidence](Docs/Planning/CONTAINER-INSPECTION-EVIDENCE.md).

Advanced queue publication now verifies the retained flat chapter titles/times and embedded-file payload hashes, sizes, names and declared types. MP4 requires chapters starting at zero with no gaps; use MKV for gaps. Trimmed jobs omit chapters, and only MKV with Keep embedded tracks retains file attachments. Cover artwork, editions and arbitrary metadata are outside this check. See [container preservation evidence](Docs/Planning/CONTAINER-PRESERVATION-EVIDENCE.md) for limits and local/native/hosted validation.

Queue output verification now checks resized raster fit before publication and reports the encoded frame dimensions. Even rounding has a strict less-than-two-pixel allowance; this does not promise square pixels or validate picture content. See [geometry evidence and native access limits](Docs/Planning/PICTURE-GEOMETRY-EVIDENCE.md).

Advanced queue publication runs off the UI thread. During Finishing, Stop after current publication waits for the current result and preserves successful output before stopping later jobs. Per-job Review source/destination access opens native pickers without relinking or starting work. See [scope and evidence](Docs/Planning/PUBLICATION-RESPONSIVENESS-EVIDENCE.md).
