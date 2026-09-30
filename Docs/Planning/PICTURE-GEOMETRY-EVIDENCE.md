# Resized raster verification evidence

Date: 2026-09-30. Slice 013 / D-026 / R-016. Complete within recorded geometry limits; separate native access findings remain open.

## Implemented contract

Previously, EncodePlan left expectedWidth and expectedHeight absent for both resized presets. BatchController therefore skipped those staged dimension checks. OutputGeometry now records upright cropped raster dimensions and the selected box, and checks the actual encoded size before publication. Completed detail reports verified frame dimensions. Existing filter arguments, HDR/orientation checks, audio/track/container checks and stored formats are unchanged.

Original size remains exact. Resized dimensions must be positive/even, inside the chosen 1280x720 or 1920x1080 raster box, touch one box edge and differ from the ideal proportional raster fit by strictly less than two pixels per axis. Bounded Int64 cross-products implement that strict inequality without floating-point boundary ambiguity. Source dimensions are positive even Int32-sized values; an ideal scaled edge below one pixel is refused. This is not verification of picture content, perceptual quality, sample aspect ratio or display size.

FFmpeg documents aspect/divisibility options separately from reset_sar in its [scale filter reference](https://ffmpeg.org/ffmpeg-filters.html#scale-1). Generated 9.0.2 fixtures showed 98x160 becoming 442x720 with SAR 441:442, and an anamorphic source retaining non-square pixels. The invariant tolerates even rounding without importing filter source or prescribing one version's rounding. Existing rotated-source SAR restrictions remain a separate limitation.

## Automated evidence

Three focused tests passed in 0.491 seconds. Pure tests cover exact Original size, landscape/portrait proportional fit, legitimate neighboring even rounding, missing/odd/zero/oversized dimensions, unsupported settings and unrepresentably thin output. The initial floating-point allowance accepted an exact two-pixel error; the boundary test caught it and the final exact integer comparison rejects it.

Actual H.264 queue exports produced 1200x720 landscape, 442x720 portrait, and 1792x1080 cropped landscape. A controlled encoder wrapper drops the requested resize filter but otherwise runs FFmpeg successfully; the queue then fails frame-size verification, publishes nothing and removes owned staging. Source and prior-output bytes stay unchanged. The full release regression passed 122 tests in 24 suites in 9.373 seconds, with 15 existing opt-in skips. The optimized ad-hoc app build passed in 13.12 seconds. No new audio listening or DSP acceptance.

## Native evidence and discovered access limitation

On macOS 27.0.1 / Apple M5, a generated two-job session loaded without execution. Initially, the newly created portrait source repeatedly hit the read-only preflight timeout. A live ffprobe sample showed it waiting in the operating system's open call; an identical direct probe succeeded. Selecting that generated source through the native Open source panel resolved its probe, and both queue checks passed. This supports a file-access inference; it does not establish the precise OS permission subsystem responsible.

The first encode then blocked during publication. A live app sample located the main thread in ExportPublication.publish's link syscall. No final output existed and both source hashes were unchanged. The generated app process was terminated; its single owned staging directory was preserved locally as diagnostic evidence. No historical staging sweep was performed.

After restarting and selecting the generated destination through the normal folder picker, both jobs completed: landscape 1800x1080 and portrait 442x720. Queue accessibility text reported those verified sizes. The output inspector independently showed portrait 442x720, SAR 441:442 and DAR 49:80. Direct probes agreed. Sources stayed unchanged; successful operations removed their own staging, with only the explicitly preserved interrupted staging remaining.

Restored-session file access and synchronous publication on the main thread are therefore open reliability findings. Successful explicit-picker validation qualifies this geometry slice only. The next reliability scope should prevent filesystem publication waits from freezing native controls and make required access review clear. No blanket folder permissions, signing credentials or system security settings were changed.

## Remaining gates

Hosted regression passed at 30b044b: run 36769620823 / job 110072394505, completed 2026-09-30 at 20:10:08 UTC in 9m19s. Broader raster/encoder corpus, display-aspect and anamorphic policies, restored-session access and blocked-publication responsiveness remain separate qualification. No merge or release.
