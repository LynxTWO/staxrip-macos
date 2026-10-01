# Native Quick Export duration evidence
Date: 2026-10-01. Scope: Slice 044 / D-082 / R-054.

## Baseline and need

Approved plan 31b4a74 precedes implementation; baseline 959e35c has accepted track-role inspection. NativeExportService previously checked that source/result contained readable video, but did not compare their duration. This is a runtime verification gap, not evidence of spontaneous AVFoundation truncation.

Apple documents asynchronous duration loading in https://developer.apple.com/documentation/avfoundation/loading-media-data-asynchronously . The value is aggregate asset timing. This change cannot certify every decoded frame, individual-track timing, audio/video sync, source stability or HDR.

## Negative control

M1 added only a DEBUG-only pre-verification boundary after the native writer completed, plus one parameterized regression. Generated silent three-second source video went through the real native export/controller. The test replaced only its settled owned staged result with a real one-second or five-second MP4, then allowed ordinary verification/publication to proceed. AVFoundation read one video track and the independently authored replacement duration in each case.

The original readable-video policy published both replacements: expected 3 seconds, actual 1 and 5 seconds. The regression failed with six assertions across its two cases in 0.143 seconds. Source/prior output, unrelated staging and explicit normal retry checks did not fail. This is the intended old-policy negative control, preserved in private work/native-duration/negative-control.log; no test was weakened to pass it.

## Implementation and focused checks

NativeExportDuration requires finite positive source seconds before staging. NativeExportService loads source duration asynchronously, keeps the immutable contract through the export, reads staged duration after the completed writer callback and applies the existing unchanged strict OutputDurationCheck before finishing/publication. Cancellation, lifetime and cleanup ownership remain. The generated replacement hook exists only in DEBUG builds and cannot bypass verification. Quick Export states the total-duration check and its limits.

Fifteen tests in three suites passed in 1.473 seconds: NativeOutputDurationTests, ExportTests and OutputDurationTests, with no skips in this selection. These include invalid source values, strict 250-millisecond boundaries from one second through one day, real shorter/longer staged refusal, controller failure state, explicit successful retry, original/prior-output/unrelated-staging preservation, all three native presets and existing cancellation/cleanup/publication outcomes. Private log: work/native-duration/focused.log. Existing ChapterPersistenceTests asynchronous Thread.isMainThread build warnings remain.

## Native optimized walkthrough

Optimized build f385cec completed in 18.27 seconds. In the actual app, opened a generated six-second silent source, selected H.264 720p, chose a new MP4 name in the attached save sheet and received Export complete. Visible text and the accessibility tree both explained the strict total-duration check and the frame/sync limitations. No heard VoiceOver claim is made.

Independent ffprobe decoded-frame counting found 144 H.264 frames, 160 by 96, exactly 6.000 seconds and no audio; output size was 210201 bytes. Whole-file source/prior-output hashes remained unchanged, no owned staging remained, and the owner's recovery journal stayed byte-identical. The app was quit normally. Private receipt: work/native-duration/native/verified.json. This single native fixture does not expand the runtime check into a decoded-completeness guarantee.

## Ordinary regression

Full local swift test at f385cec passed 280 tests across 68 suites in 214.202 seconds, with 25 existing opt-in/tool-dependent skips. Private log: work/native-duration/full-local.log.

Hosted macOS 15 run [36916404356](https://github.com/LynxTWO/staxrip-macos/actions/runs/36916404356), exact product f385cec925f0683d5eaa5bb6799e9beb6a349c8e, passed 280 tests in 497.150 seconds after a 116.13-second build, with the same 25 existing skips. Private log: work/native-duration/hosted-final.log. Existing asynchronous/Sendable compiler warnings remain; the historical mastering cancellation failure did not recur.

## Scoped acceptance

All four S44 gates passed: strict policy, real shorter/longer refusal and explicit retry, optimized native guidance/output, and ordinary local/hosted regression. Selected planning audit and diff checks pass. No decoded completeness, A/V sync or production-ready claim. A repeat of the historical hosted mastering cancellation failure reopens qualification without blind retry or diagnostic expansion.
