# Video inspection evidence

Date: 2026-09-29. Scope: SLICE-003-video-inspection.md.

## Implemented

MediaProbe retains optional profile, color primaries/matrix/range, average/base frame rates, sample/display aspect ratios and field order. Existing transfer, pixel format, reported raw bit depth and rotation fields feed grouped picture, color and timing rows. Every row has its own accessible label, value and explanation. Recognized color names retain raw tags. Missing values remain unspecified. Raw bit depth is not inferred from arbitrary pixel-format strings, and stream rates do not establish VFR or CFR.

Encoding arguments, native Apple preset behavior, stream selection, queue/session data and audio processing are unchanged. HDR preservation and tone mapping are not implemented by this slice.

## Automated checks

`swift test -c release`: 75 reported tests in 14 suites passed in 8.201 seconds; 12 opt-in research/resource tests skipped. This includes the native export start-notification fix from PR 17 and existing encode/audio/session regressions. VideoInspectionTests covers missing/partial/unrecognized tags, separate rotation sources, PQ/HLG labels, invalid and non-finite ratios, overflow/underflow, source immutability and unchanged SDR acceptance/HDR rejection.

Three generated one-second 160x90 fixtures use rate 30000/1001, sample aspect 4:3, display aspect 64:27, and limited range. SDR is yuv420p/libx264 with bt709; PQ/HLG are yuv420p10le/libx265 with bt2020/bt2020nc and smpte2084/arib-std-b67. Fixture filters explicitly set frame color metadata using setparams before encoding. On local FFmpeg 9.0.2, the initial recipe using output flags alone did not retain transfer/primaries, and the tests correctly failed; the recipe was corrected rather than relaxing assertions. Synthetic tags establish probe/presentation behavior only, not HDR picture correctness.

The final view-only layout adjustment compiled and the release preview rebuilt using build.command. The preview is ad-hoc signed, not a notarized release. No new dependency or media entered Git.

## Native check

A generated 10-bit PQ-tagged HEVC MP4 opened in Workspace and the actual Inspect media tracks sheet. Color rows showed Rec.2020, PQ, non-constant-luminance matrix and limited signal range. Missing reported raw bit depth remained unspecified despite the known pixel-format string. Distinct average/base rates were displayed without a VFR diagnosis.

An initial max-height-only scroll area collapsed in the real sheet, hiding rows and truncating the footer. A stable 340-point scroll area and vertically fixed explanatory text corrected that. Screenshots verified both the upper color rows and lower timing/rotation rows, with Done visible. Escape dismissed the sheet. Accessibility inspection verified each row's individual label, value and explanatory hint. Static-text traits that coalesced neighboring rows were removed. Owner spoken VoiceOver validation is still separate; no headphone listening was required or performed.

Hosted macOS validation passed at 7b51fc8 in run 36600485460 (8m52s). Owner visual review was positive on 2026-09-29. A complete owner keyboard/spoken walkthrough is not claimed. Local evidence is macOS 27 on the development Mac; it is not the full platform matrix.
