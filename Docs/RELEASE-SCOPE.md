# Release acceptance ledger

This ledger defines a finite first production release. It does not call the current preview complete. A checked local fixture is narrower evidence than compatibility with arbitrary media.

| Area | Implemented evidence | Required before production |
| --- | --- | --- |
| Native workspace | SwiftUI/AppKit playback, dark/light appearance, source import, inspector, independent queue editing, bounded SDR filtered still comparison (Planning/PICTURE-PREVIEW-EVIDENCE.md) | Keyboard/accessibility audit across supported OS versions; motion preview and exact frame stepping |
| Video encoding | Software AV1/H.264/HEVC CRF and bitrate; actual hardware H.264/HEVC on development Mac; explicit verified static PQ HDR10 to software HEVC/MKV (see Planning/HDR10-EVIDENCE.md) | Capability checks across machines; calibrated HDR and real-film validation, broader HDR/10-bit workflows, rotation and remux |
| Picture and timeline | Four-edge crop, resize, BWDIF, precise output trim; synthetic duration/dimension checks | VFR, anamorphic, unusual timestamps and long-film A/V sync matrix; subtitle retiming |
| Track routing | Selected audio/subtitle streams; copied subtitle/audio container checks; multilingual fixture | Per-track recipes, external subtitles, chapter editor and attachment verification |
| Audio mastering | FLAC/WAV/AAC/Opus; custom LUFS/LRA; measured Smart/Night foundation; per-channel audit; manual dialogue passage measurement | Original adaptive planner, automatic dialogue classification, validated multichannel export, independent metering and listening comparisons; see LOUDNESS-DESIGN.md |
| Session and presets | Validated versioned video sessions, built-in presets, explicit queue recovery; source-independent custom presets and bounded settings undo have automated and local native evidence | Audio session persistence, broader preset accessibility/platform coverage, forced-crash and multi-instance long-run checks |
| Output safety | Staging, exclusive no-overwrite publication, cancellation, bounded logs, codec/track/duration checks | Network/removable filesystems, disk-full tests, stale staging recovery and long-running process ownership |
| Evaluation | Generated-media integration tests, debug/release tests, native UI checks | Representative licensed film/audio corpus, objective visual metrics and reproducible quality/speed comparisons |
| Distribution | Local optimized ad-hoc app/ZIP; FFmpeg installed separately | Signed/notarized candidate and clean-machine validation, external-tool license/provenance review, supported OS/hardware coverage |

## Research-informed priorities

Modern codec availability is only part of a powerful encoder. Explicit stream selection, preserved color/timing semantics, observable failures, and measured audio outcomes are equally necessary. FFmpeg's [stream-selection documentation](https://ffmpeg.org/ffmpeg.html#Stream-selection) informs routing. Apple's [VideoToolbox framework](https://developer.apple.com/documentation/videotoolbox) supplies the hardware path. EBU metering and cinematic guidance inform the audio acceptance plan.

## External dependencies

The repository became public on 2026-09-28 and the previously blocked hosted macOS workflow passed on retry: [run 36378725531](https://github.com/LynxTWO/staxrip-macos/actions/runs/36378725531). Local checks also remain usable. The owner completed Developer ID Application setup and the staxrip-notary Keychain profile authenticated successfully. Signing credentials are ready; signing, notarization, ticket validation and clean-machine installation of a release candidate are still outstanding. No repository merge or public release has been performed.

## Completion planning

[Scaffold Kit v0.4 planning index](Planning/README.md) records the proposed slices, SignalForge reuse assessment, acceptance gates and owner signing setup. These documents are proposals, not evidence that outstanding features are implemented.
