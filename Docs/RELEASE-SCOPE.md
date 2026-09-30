# Release acceptance ledger

This ledger defines a finite first production release. It does not call the current preview complete. A checked local fixture is narrower evidence than compatibility with arbitrary media.

| Area | Implemented evidence | Required before production |
| --- | --- | --- |
| Native workspace | SwiftUI/AppKit playback, dark/light appearance, source import, inspector, independent queue editing, bounded SDR filtered still comparison (Planning/PICTURE-PREVIEW-EVIDENCE.md) with decoded-timestamp frame stepping (Planning/FRAME-STEPPING-EVIDENCE.md) | Keyboard/accessibility audit across supported OS versions; motion preview and broader frame-stepping/media qualification |
| Video encoding | Software AV1/H.264/HEVC CRF and bitrate; actual hardware H.264/HEVC on development Mac; explicit verified static PQ HDR10 to software HEVC/MKV (see Planning/HDR10-EVIDENCE.md); validated progressive square-pixel SDR right-angle orientation (Planning/ORIENTATION-EVIDENCE.md) | Capability checks across machines; calibrated HDR and real-film validation, broader HDR/10-bit workflows, broader source transforms and remux |
| Picture and timeline | Four-edge crop, resize, BWDIF, precise output trim; original-size and resized raster verification (Planning/PICTURE-GEOMETRY-EVIDENCE.md), scoped declared display-proportion verification with explicit unknown/rounding limits (Planning/DISPLAY-ASPECT-EVIDENCE.md) | VFR, anamorphic, unusual timestamps and long-film A/V sync matrix; subtitle retiming |
| Track routing | Selected audio/subtitle streams; copied subtitle/audio container checks; multilingual fixture; read-only chapter/attachment inspection and scoped pre-publication verification (Planning/CONTAINER-PRESERVATION-EVIDENCE.md); one plain external SRT with exact added cue verification in MKV/MP4, local/native/hosted acceptance passed (Planning/EXTERNAL-SUBTITLE-EVIDENCE.md) | Per-track recipes, broader external subtitle formats/retiming/multiple tracks, chapter editor, broader metadata corpus |
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
