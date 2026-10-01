# Caption playback choices evidence
Date: 2026-10-01. Scope: Slice 042 / D-080 / R-052.

## Baseline and authority

Product baseline 22b4dea. Plan a4a585b precedes all experiments and implementation. Owner delegated autonomous non-audio completion; no merge or release. Existing original-caption, cancellation, scheduling and protected-publication contracts remain mandatory.

## M1 container feasibility

Verified observed_behavior, user_data scope: FFmpeg 9.0.2 generated two-second 160x96 24 fps H.264, two silent FLAC audio streams with no input default and one default/forced/hearing-impaired SubRip track. Two distinct external SRTs were added. Ordinary baseline remux and explicit default/forced or optional cases were compared with and without the embedded track. All six output files passed in 0.544 seconds under the ten-minute bound. Local script/log: work/caption-flags/feasibility.py and feasibility.log, outside Git.

Both audio/video default and forced bits match the ordinary remux. First audio default is restored explicitly when multiple mapped audio streams lack one. Selecting the last caption as default clears the embedded default but preserves its forced and hearing-impaired flags. First added Forced produces only the forced bit. Explicit Optional clears both bits without assigning a replacement. Every output subtitle fully decodes to its baseline SRT bytes. Source SHA-256 remains 2a6401ad172b51d84f3d3867009859c1f1cabde89122951bb5729df74e6effc0.

References: https://ffmpeg.org/ffmpeg.html (disposition incremental updates and automatic default rules), https://ffmpeg.org/ffmpeg-formats.html#matroska (passthrough default handling). The experiment establishes configured container flags only, not player behavior. MP4, arbitrary source metadata and heard accessibility remain unqualified.

## Implementation and remaining gates

M2 implemented: optional typed choice, MKV-only validation, version 9 sessions/version 8 recovery, preserved replacement/equality intent, incremental flag plan and pre-publication checks. No new flags or flag contract when all choices are Automatic. Added native picker labels/hints explain selection and player limits.

Focused local run: 19 reported tests in five suites passed in 0.574 seconds, including seven actual-controller cases (embedded copy/encode, removed embedded, trim, optional and two corrupted-output refusals). Copied silent audio decoded hashes remain equal; every caption decodes completely; retained hearing-impaired/forced metadata survives; source/prior/caption bytes and staging are protected. Four typed-contract tests cover legacy, malformed, duplicate/default, MP4, stale picker, reorder/undo and changed/missing output bits. Existing three persistence/list suites remain passing. Log: work/caption-flags/focused.log. Initial test compilation required an inner try inside two require macros; fixed only those expressions, retained focused-compile-error.log. No production repair or weakened test.

S42-001 through S42-004 have scoped local evidence. Native, optimized build and ordinary full local/hosted regression remain pending. No acceptance claim yet.


## Native and ordinary local verification

Native generated walkthrough at ba5ba2c on macOS 27.0.1 / Apple M5, FFmpeg 9.0.2. The initial 8cbda9a view showed redundant visible filenames in Playback labels; ba5ba2c changes only that label to Playback and retains the full track name in its accessibility label. Picker keyboard Up/Down/Return and accessible descriptions were observed. Duplicate-default and MP4 remedies retained the chosen values. No heard VoiceOver or third-party player claim.

Native session save/reopen preserves French Default and forced before English Forced after reorder. Explicit matching source and caption-file review preserves the saved choices. The reviewed queue completed a 35,310-byte silent H.264 MKV with 48 decoded frames at 160x96, duration 1.999 seconds. Complete embedded/French/English captions match their originals. Output default/forced pairs are (0,1), (1,1), (0,1); the embedded hearing-impaired flag remains one. Video flags remain zero. The app's expanded completed result reports playback and caption verification.

Local native receipts: work/caption-flags/native/verify.py, verify.log and verified-output.json. Original source, both SRTs, original session and prior output hashes remain unchanged; owned staging is absent. After normal app quit and process-absence confirmation, the generated completed journal was saved privately, matched to its sole owned job and output, and the prior journal was restored byte-for-byte (SHA-256 91270f017e715a3bd1a0240c07039ecc3242fa022517c84b39e76c3dbdea8603). No owner media or paths committed.

Ordinary local swift test at 8cbda9a passed 275 reported tests in 66 suites in 212.177 seconds, with 25 existing opt-in skips (work/caption-flags/full-local.log). Final ba5ba2c differs only in the native picker label/accessibility modifier; all algorithms, saved data, tests and workflow match that full run. Optimized builds passed: 18.28 seconds at 8cbda9a and 18.04 at ba5ba2c (build-release.log and build-final.log). The preview is ad-hoc signed, not a distribution candidate.

S42-005 passed within the observed native boundary. Final-head ordinary hosted run 36911094620 passed at ba5ba2c: 275 reported tests in 462.787 seconds, 72.02-second build, 25 existing opt-in skips. The earlier pre-label run 36910605965 also passed at 8cbda9a: 275 tests in 476.547 seconds, 71.77-second build, 25 skips. Logs: hosted-final.log and hosted-before-label.log. The unresolved historical mastering cancellation delays remain a reopen trigger.


## Acceptance and limits

All six S42 gates passed within scope at ba5ba2ce078d671a2d68682be3b60c08b43bba6c; draft PR 59. Selected planning audit: zero findings across 45 documents; diff whitespace check passed. This is not a clean global historical audit. Hosted compilation retains existing Swift 6 language-mode warnings for AVAssetExportSession capture and the ChapterPersistenceTests thread check; this package uses Swift language mode 5. These files' warned behavior was not introduced here.

No audio DSP, deadline or ordinary test-scheduling changes. Historical mastering cancellation delays remain unexplained and a recurrence reopens qualification. Explicit MP4 flags, independent embedded flag editing, heard VoiceOver, player certification, broader platforms, merge and release remain excluded. A written flag check establishes file metadata, not what any player will choose.
