# Release acceptance ledger

This ledger defines a finite first production release. It does not call the current preview complete. A checked local fixture is narrower evidence than compatibility with arbitrary media.

| Area | Implemented evidence | Required before production |
| --- | --- | --- |
| Native workspace | SwiftUI/AppKit playback, dark/light appearance, source import, inspector, independent queue editing, bounded SDR filtered still comparison (Planning/PICTURE-PREVIEW-EVIDENCE.md) with decoded-timestamp frame stepping (Planning/FRAME-STEPPING-EVIDENCE.md) | Keyboard/accessibility audit across supported OS versions; motion preview and broader frame-stepping/media qualification |
| Video encoding | Software AV1/H.264/HEVC CRF and bitrate; actual hardware H.264/HEVC on development Mac; explicit verified static PQ HDR10 to software HEVC/MKV (see Planning/HDR10-EVIDENCE.md); validated progressive square-pixel SDR right-angle orientation (Planning/ORIENTATION-EVIDENCE.md) | Capability checks across machines; calibrated HDR and real-film validation, broader HDR/10-bit workflows, broader source transforms and remux |
| Picture and timeline | Four-edge crop, resize, BWDIF, precise output trim; original-size and resized raster verification (Planning/PICTURE-GEOMETRY-EVIDENCE.md), scoped declared display-proportion verification with explicit unknown/rounding limits (Planning/DISPLAY-ASPECT-EVIDENCE.md) | VFR, anamorphic, unusual timestamps and long-film A/V sync matrix; subtitle retiming |
| Track routing | Selected audio/subtitle streams; copied subtitle/audio container checks; multilingual fixture; read-only chapter/attachment inspection and scoped pre-publication verification (Planning/CONTAINER-PRESERVATION-EVIDENCE.md); native flat chapter authoring/removal with verified literal titles/ranges (Planning/CHAPTER-EDITOR-EVIDENCE.md); one plain external SRT with exact added cue verification in MKV/MP4, local/native/hosted acceptance passed (Planning/EXTERNAL-SUBTITLE-EVIDENCE.md) | Per-track recipes, broader external subtitle formats/retiming/multiple tracks, broader chapter/player and metadata corpus |
| Audio mastering | FLAC/WAV/AAC/Opus; custom LUFS/LRA; measured Smart/Night foundation; per-channel audit; manual dialogue passage measurement | Original adaptive planner, automatic dialogue classification, validated multichannel export, independent metering and listening comparisons; see LOUDNESS-DESIGN.md |
| Session and presets | Validated versioned video sessions, built-in presets, explicit queue recovery; source-independent custom presets and bounded settings undo have automated and local native evidence | Audio session persistence, broader preset accessibility/platform coverage, forced-crash and multi-instance long-run checks |
| Output safety | Owned staging cleanup with bounded retries and preserved outcome warnings, exclusive no-overwrite publication, local HFS+ full-destination failure/retry (Planning/DESTINATION-CAPACITY-EVIDENCE.md), cancellation, bounded logs, codec/track/duration checks; optional read-only queue preflight with stale-result invalidation (Planning/QUEUE-PREFLIGHT-EVIDENCE.md) | Network/removable and APFS capacity failures, full journal/source volumes, stale staging recovery, durable restored-session file access, responsiveness outside batch publication and long-running process ownership |
| Evaluation | Generated-media integration tests, debug/release tests, native UI checks | Representative licensed film/audio corpus, objective visual metrics and reproducible quality/speed comparisons |
| Distribution | Local optimized ad-hoc app/ZIP; FFmpeg installed separately | Signed/notarized candidate and clean-machine validation, external-tool license/provenance review, supported OS/hardware coverage |

## Research-informed priorities

Modern codec availability is only part of a powerful encoder. Explicit stream selection, preserved color/timing semantics, observable failures, and measured audio outcomes are equally necessary. FFmpeg's [stream-selection documentation](https://ffmpeg.org/ffmpeg.html#Stream-selection) informs routing. Apple's [VideoToolbox framework](https://developer.apple.com/documentation/videotoolbox) supplies the hardware path. EBU metering and cinematic guidance inform the audio acceptance plan.

## External dependencies

The repository became public on 2026-09-28 and the previously blocked hosted macOS workflow passed on retry: [run 36378725531](https://github.com/LynxTWO/staxrip-macos/actions/runs/36378725531). Local checks also remain usable. The owner completed Developer ID Application setup and the staxrip-notary Keychain profile authenticated successfully. Signing credentials are ready; signing, notarization, ticket validation and clean-machine installation of a release candidate are still outstanding. No repository merge or public release has been performed.

## Completion planning

[Scaffold Kit v0.4 planning index](Planning/README.md) records the proposed slices, SignalForge reuse assessment, acceptance gates and owner signing setup. These documents are proposals, not evidence that outstanding features are implemented.

Advanced batch publication responsiveness and per-job native access review have scoped local/native/hosted evidence in [PUBLICATION-RESPONSIVENESS-EVIDENCE.md](Planning/PUBLICATION-RESPONSIVENESS-EVIDENCE.md). Other synchronous I/O, persistent access and broader filesystem qualification remain open.

Advanced export source stability now has scoped local/native/hosted acceptance: whole-source fingerprint observations before inspection and before publication, regular-file/change checks, cancellable background file work and byte progress. See [source stability evidence](Planning/SOURCE-STABILITY-EVIDENCE.md). This adds source I/O and does not create immutable snapshots or guarantee network-filesystem cancellation latency. Native Quick Export remains outside this check.

Workspace source imports now own native/fallback cancellation and latest-only replacement, with clear waiting state and regular-file refusal. Scoped local/native/hosted acceptance is recorded in [source import evidence](Planning/SOURCE-IMPORT-EVIDENCE.md). Arbitrary filesystem latency, durable access and spoken VoiceOver qualification remain open.

Native Quick Export final publication now awaits a background filesystem operation and preserves save outcomes across late cancellation, with scoped [native publication evidence](Planning/NATIVE-PUBLICATION-EVIDENCE.md). Native source preparation, other synchronous I/O and destination-dialog usability remain separate.

Advanced declared output-duration verification now uses a fixed strict 250-millisecond allowance for known plans, with explicit unknown-source reporting. [Duration evidence](Planning/OUTPUT-DURATION-EVIDENCE.md) includes real shortened/extended-output refusal and long/trim checks. Decoded completeness, per-track timing and audiovisual synchronization remain separate.

Native Quick Export preset accessibility and readiness-driven subprocess output draining have scoped [local/native/hosted evidence](Planning/NATIVE-PRESET-ACCESSIBILITY-EVIDENCE.md). The 96-child starvation reproduction now passes; arbitrary callback, descendant-pipe and filesystem latency guarantees remain outside this proof.

The workspace now has a live settings-only recipe with direct correction, keyboard section shortcuts and persistent destination/queue actions. [Recipe evidence](Planning/WORKSPACE-RECIPE-EVIDENCE.md) records local/native/hosted acceptance. This is requested intent, not a source compatibility or measured-output claim.

Restoring a session now defers media reads until explicit matching-source review, preserving its recipe and output name. [Restored source evidence](Planning/RESTORED-SOURCE-EVIDENCE.md) records complete native session round-trip equality and local/hosted acceptance. Matching paths do not establish unchanged bytes or durable access.

SDR video now requests timestamp passthrough with the filter time base. [Cadence evidence](Planning/SDR-CADENCE-EVIDENCE.md) records the actual-plan 18-19 ms quantization failure and corrected short software/hardware matrix. Runtime per-frame audit and long-film A/V sync remain open. Native destination publication also repeated the recorded filesystem wait before succeeding on a reviewed-destination retry; its root cause is unproven.

Quick Export destination selection now shares the attached workspace dialog lifecycle, refusing stale source/preset/availability and duplicate callbacks. [Native export dialog evidence](Planning/NATIVE-EXPORT-PANEL-EVIDENCE.md) records actual export, cancellation and existing-output protection. Known native MP4 name collisions now stay in the save sheet for correction before Replace; [name evidence](Planning/NATIVE-OUTPUT-NAME-EVIDENCE.md) records native correction, race protection and local/hosted checks. Filesystem latency and durable access remain separate.

Native queue start now reviews distinct pending destination folders before encoding or replacing recovery state. [Destination review evidence](Planning/QUEUE-DESTINATION-REVIEW-EVIDENCE.md) records safe cancellation, three-job native completion and local/hosted checks. Selection does not establish durable permission, capacity or the cause of earlier filesystem waits.

Chapter authoring has scoped feature evidence in [chapter editor evidence](Planning/CHAPTER-EDITOR-EVIDENCE.md). Full-suite timing qualification was subsequently reopened: hosted runs repeatedly exceeded existing video integration deadlines, while local full suites and the same hosted runner's focused video subset passed. The scoped owned-worker repair passed hosted run 36839378179 with all 227 tests, plus local/native export and capacity checks. After temporary tracing was removed, plain local tests passed and hosted run 36840667407 passed all 227 tests at a940665. Slice 031 is accepted within its documented capacity and dispatch bounds; [APFS capacity evidence](Planning/APFS-CAPACITY-EVIDENCE.md) records the actual failures and bounded diagnosis. No deadline, assertion or default test scheduling policy has been relaxed.
