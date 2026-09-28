# Developer preview validation

## Local evidence

- macOS 27, Apple Silicon, Swift 6.4, Homebrew FFmpeg 9.0.2.
- All 30 tests pass in debug and optimized release builds. The recovery update adds seven tests for interrupted state, controller restart after an actual encode, output preservation, untrusted records, write failures and lock ownership. Parameterized cases include three AVFoundation presets, three FFmpeg video encoders and four audio output formats.
- Real synthetic-media checks cover video/audio codecs, crop dimensions, track count, duration, sample rate, channels, selected-track loudness, literal filename arguments, source preservation, output conflicts, cancellation and cleanup.
- Native UI checks completed for workspace import/playback, queue editing, session round-trip, appearance, media inspection and an actual AV1 queue encode.
- Audio Lab initial screen and source picker were observed. Its engine passes tests. The complete audio UI workflow is not yet verified.

- Optimized local app and ZIP packaging passed strict ad-hoc signature verification. Dynamic dependencies resolve to Apple system frameworks/libraries; FFmpeg is external.

## External limitations and earlier inspection failure

The native UI automation service returned `Sky Computer Use native pipe closed before response` while opening the generated audio fixture. The app remained running, with no new app crash report found. Subsequent reads, a tool-session reset and reconnection all failed with the same service error. Do not mark the full Audio Lab UI workflow as passed until the service is restored and the import, analysis, export and cancellation controls are exercised.

GitHub Actions jobs have been rejected before startup by the account's billing/spending-limit restriction. Local tests are not evidence of a hosted CI pass.

Local signing identity inspection found an Apple Development identity but no Developer ID Application identity. The preview uses an ad-hoc signature. No notarization or public release has been performed.

## Next checks after UI control returns

1. Import a generated WAV and multitrack MKA into Audio Lab.
2. Switch selected tracks, analyze each, and confirm the measurement changes.
3. Export each format through the Save dialog; verify the chosen destination and Finder reveal.
4. Cancel a long audio operation, then retry; check that source controls and Quit protection recover.
5. Test the full app at minimum window size in light and dark appearance.
6. Exercise the new Restore previous queue control after a normal relaunch and forced interruption. Automated checks cover persisted states and controller recreation; a full app crash/relaunch UI test is still pending. No silent restart or blanket temporary-directory cleanup.

Long-form and damaged media, VFR/A-V sync, HDR, multichannel routing, older macOS, Intel hardware, network filesystems and distribution signing are not fully validated. Synthetic checks do not establish production readiness or superiority to other encoders.

## Recovery follow-up

Native control was retried by full app path and still returned the native-pipe error. Recovery implementation and automated tests proceeded independently; its new restore banner has not been visually verified. The running v0.4 preview was preserved. A separate optimized v0.5 developer artifact can be built without replacing that running bundle.

## v0.6 inspection workaround and follow-through

The helper crash was reproduced in an isolated populated Audio Lab without any file picker. Simple GroupBox/picker probes did not fail, so the evidence identifies the combined populated layout rather than GroupBox universally. Replacing its three GroupBox containers with labeled VStack panels makes the full view inspectable while retaining accessible headers and controls. This works around the helper failure; it does not patch the helper itself.

The real v0.6 app passed native WAV import, loudness analysis (-21.75 LUFS / -18.06 dBTP on the generated tone), and Save-dialog FLAC export. ffprobe independently verified 24-bit FLAC, 48 kHz, mono, five seconds. A real H.264 queue job completed, then normal Quit/relaunch offered the previous batch; explicit restoration retained Completed and did not resume processing. The prior native-inspection blocker is resolved for these workflows. All 27 automated tests still pass; local release packaging passed signature verification.

## v0.7 normalization

Thirty automated tests pass in debug and optimized release, including normalized AAC/Opus/FLAC/WAV exports, selected-track and channel-conversion behavior, silence refusal, and peak/level verification rejection. The native UI passed enabling normalization, selecting its default −16 LUFS target and exporting through the Save dialog. A separate full-file measurement of that FLAC returned −15.95 LUFS and −12.24 dBTP. The dark-mode layout was visually inspected with all controls exposed. Exhaustive program-material/true-peak stress tests and long-run operation remain broader validation work.

## v0.8 picture/timeline

Generated 4-second interlaced H.264/AAC input → trim 1–2.5 seconds, four-edge crop, BWDIF → verified 306×174 progressive 24 fps output, duration within 0.15 seconds. Native controls accepted trim values, crop and All frames selection; Add to queue → Edit preserved those exact settings. Queue editor scrolls to fit its enlarged form. Legacy configuration decoding and invalid trim/crop validation covered. No claim of subtitle-retiming support.

Implementation references: [FFmpeg options](https://ffmpeg.org/ffmpeg.html#Main-options) for output-side seeking/duration, [BWDIF](https://ffmpeg.org/ffmpeg-filters.html#bwdif) for frame mode and interlace selection.

## Track routing

33 local tests pass. A synthetic source with English/French audio and French subtitles verifies selected French-only output and preserved language tags. Tests cover absent/wrong-type IDs, None/All, duplicate IDs and configuration round-trip. Native UI import → uncheck English → Apply → reopen retained only French; the dark sheet was visually inspected. New journals use version 2 to prevent older applications replaying jobs without the new settings.
