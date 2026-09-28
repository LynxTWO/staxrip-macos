# Slice 002 research and boundary notes
Version: 0.1 Draft. Date: 2026-09-28.

## Source findings

- [ITU-R BS.1770](https://www.itu.int/rec/R-REC-BS.1770) defines programme loudness and true-peak measurement. It does not choose a comfortable Night preset for this app.
- [EBU Tech 3342, 2023](https://tech.ebu.ch/docs/tech/tech3342.pdf) defines LRA using the gated short-term distribution and its 10th/95th percentiles. Brief loud events may not materially affect a long programme's LRA. Very short programmes and isolated utterances can give misleading LRA. Implication for this design: use whole-programme LRA plus separate excursion/peak checks; do not treat each short speech passage's LRA as a comfort target.
- [EBU R 128 s4](https://tech.ebu.ch/files/live/sites/tech/files/shared/r/r128s4.pdf) treats cinematic programme loudness and dialogue loudness as different quantities. The proposed explicit target reference is a product design response. User-selected mixed passages are not certified dialogue isolation or a claim of compliance with this supplement.
- [FFmpeg loudnorm](https://ffmpeg.org/ffmpeg-filters.html#loudnorm) provides linear and dynamic normalization. The existing app uses it, adds linked compression for Night, then measures its output. That remains a useful named baseline; renaming it would not implement an original planner.

## Current source map, revision 96f1d38

AudioEngine.swift exports through FFmpeg loudnorm/acompressor and measures with FFmpeg again. AudioController stores the new AnalysisReport separately. AnalysisReport.swift runs a fresh decode, hashes the source and records programme/channel/manual-region results; imported reports are informational. StreamingLoudness.swift provides independent windowed measurement. MeasuredAnalysisView.swift presents reports but does not render from them. ExportPublication supplies no-replacement publication. These are inspected source facts, not a claim that an original gain planner exists.

The new plan must freshly analyze input rather than trust externally edited JSON. The current source hash confirms file identity, not authenticity of report numbers. Stereo gain linking must preserve channel relationships; separate per-channel loudness values are diagnostics, not additive programme measurements.

## Proposed choices and limits

D-014 proposes lossless output first to separate DSP/preview correctness from lossy encoder peak changes, source rate/layout preservation, an explicit programme/speech target, and full-candidate staging before preview. Alternatives are retaining only the existing FFmpeg mastering, or building original processing plus automatic speech and lossy/remux integration together. The latter has more unverified interacting components.

Targets, gain caps, Night excursion limits and iteration count in the brief are engineering proposals. No cited standard establishes them as optimal. D-015's bounded spike must register attack/release, look-ahead, noise-floor holds, limiter and latency behavior before renderer verification. D-016 must establish rights for the small listening corpus before use. Do not represent this planning research as algorithm comparison, measured quality improvement or a speech-model selection.

## Slice growth tally

Relative to manual-region gain planning, the brief adds (1) independent verification of actual encoded output, (2) full staged candidate preview with level matching, (3) a local processing receipt, and (4) bounded numerical/resource/listening gates. These make the result inspectable before publication. It deliberately excludes automatic speech, lossy output, video remux and session/queue integration. The complete cost is presented for owner approval in SLICE-002-dialogue-mastering.md.
