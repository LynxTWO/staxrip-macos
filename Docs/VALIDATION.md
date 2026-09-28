# Developer preview validation

## Local evidence

- macOS 27, Apple Silicon, Swift 6.4, Homebrew FFmpeg 9.0.2.
- 20 Swift Testing tests pass in both debug and optimized release builds. Parameterized cases include three AVFoundation presets, three FFmpeg video encoders and four audio output formats.
- Real synthetic-media checks cover video/audio codecs, crop dimensions, track count, duration, sample rate, channels, selected-track loudness, literal filename arguments, source preservation, output conflicts, cancellation and cleanup.
- Native UI checks completed for workspace import/playback, queue editing, session round-trip, appearance, media inspection and an actual AV1 queue encode.
- Audio Lab initial screen and source picker were observed. Its engine passes tests. The complete audio UI workflow is not yet verified.

- Optimized local app and ZIP packaging passed strict ad-hoc signature verification. Dynamic dependencies resolve to Apple system frameworks/libraries; FFmpeg is external.

## Current external blockers

The native UI automation service returned `Sky Computer Use native pipe closed before response` while opening the generated audio fixture. The app remained running, with no new app crash report found. Subsequent reads, a tool-session reset and reconnection all failed with the same service error. Do not mark the full Audio Lab UI workflow as passed until the service is restored and the import, analysis, export and cancellation controls are exercised.

GitHub Actions jobs have been rejected before startup by the account's billing/spending-limit restriction. Local tests are not evidence of a hosted CI pass.

Local signing identity inspection found an Apple Development identity but no Developer ID Application identity. The preview uses an ad-hoc signature. No notarization or public release has been performed.

## Next checks after UI control returns

1. Import a generated WAV and multitrack MKA into Audio Lab.
2. Switch selected tracks, analyze each, and confirm the measurement changes.
3. Export each format through the Save dialog; verify the chosen destination and Finder reveal.
4. Cancel a long audio operation, then retry; check that source controls and Quit protection recover.
5. Test the full app at minimum window size in light and dark appearance.
6. Continue queue restart recovery with an atomic journal and explicit interrupted-job review. No silent restart or blanket temporary-directory cleanup.

Long-form and damaged media, VFR/A-V sync, HDR, multichannel routing, older macOS, Intel hardware, network filesystems and distribution signing are not fully validated. Synthetic checks do not establish production readiness or superiority to other encoders.
