# Export idle-sleep lifetime evidence
Date: 2026-10-01. Status: Scoped acceptance at c54f915; all five gates passed.

## Need, references and boundary

R-051 / D-079 covers temporary local energy policy for existing video-export lifetimes. The two relevant owners are BatchController.start and NativeExportService.export. No automatic-sleep activity calls were found in those two examined files; this says nothing about external tools, frameworks or other processes. [Apple activity options](https://developer.apple.com/documentation/Foundation/ProcessInfo/ActivityOptions) distinguishes idle system sleep from idle display sleep. [Apple's activity guidance](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/PrioritizeWorkAtTheAppLevel.html) documents matched begin/end calls and pmset inspection. Use only idleSystemSleepDisabled; no QoS, display, lock, persistent preference or audio changes.

## M1 actual system request

A local Swift/Foundation experiment on macOS 27.0.1 creates two uniquely named activity tokens. pmset -g assertions identifies both as PreventUserIdleSystemSleep owned by the experiment PID. Ending the first removes only its named assertion; the second remains. Ending the second removes both. No matching display-sleep assertion appears. The successful experiment completed in under one second within the five-minute bound. A preceding Swift autoclosure syntax error executed no experiment and is retained separately; correcting it changed no runtime assertion.

Claim: observed_behavior, verified within these two named process-local tokens. Consequence: local_only. Evidence: private export-sleep/feasibility.swift and feasibility.log. This is not forced-sleep, power-exhaustion, screen-lock, lid-close or platform-matrix qualification. M2 may proceed; actual application lifetimes and native UI remain pending.


## Implementation and local qualification

Product/test head c54f9156111a0aeb7ed57c936eac61a31d855874. ExportActivity requests only idleSystemSleepDisabled with constant names that contain no source paths. BatchController acquires one token after accepted recovery setup and ends it from its task's settlement defer. NativeExportService does the same for an accepted call. Existing cancellation, publication, cleanup, scheduling and timeout paths remain unchanged. Active Queue and Quick Export guidance exposes the temporary behavior.

Focused local regression passed 13 tests in three suites in 16.399 seconds. A preceding test-build error incorrectly observed MainActor test state from a Sendable source-reader callback; the observer now explicitly hops to MainActor. No product dispatch, assertion or time limit changed. Tests prove one activity across two actual queue jobs, active state during source reads/publication/cleanup, no tokens for unavailable/empty/duplicate/completed-only/recovery-rejected starts, and balanced ends across native actual preset exports, invalid media, existing output, cancellation and cleanup errors. Existing delayed-publication and writer-settlement guards remain. These injected observations prove owner lifetime, not OS behavior.

Ordinary local swift test at the same head reported 270 tests in 64 suites passed in 216.024 seconds, with 25 opt-in checks skipped. Optimized build passed in 17.80 seconds with an ad-hoc signature. A preceding default debug build is retained but is not the optimized-build receipt. The existing ChapterPersistenceTests isMainThread Swift-6-language-mode warning remains; the package uses Swift language mode 5. No new warning was introduced by the final tests.

## Native operation and independent output

The optimized app used a generated silent two-minute 1280 by 720, 24 fps source in a private owned folder. It explicitly reviewed the session source and destination. A real software HEVC queue entered Encoding, showed the readable/spoken automatic-sleep message, and had a PID-specific PreventUserIdleSystemSleep assertion named StaxRip advanced video queue. Cancellation settled to Cancelled / No output published; its named activity and owned staging disappeared. The same item was explicitly edited to a new output name and Copy original, then completed with all 2,880 encoded packets verified. No activity remained after completion.

Native HEVC Quick Export completed twice to distinct new names. The first post-start OS snapshot ran after this fast export had already completed and found no activity; that timing observation is retained and is not evidence of an absent active request. A bounded 45-second per-PID observation started before the next export and captured StaxRip native video export as PreventUserIdleSystemSleep. After completion the named request was absent. The active AX explanation was present; actual heard VoiceOver and a forced-sleep/lock experiment were not performed.

Independent ffprobe full-frame decoding counted 2,880 frames in each of the two HEVC MP4s and the copied H.264 MKV; all were 1280 by 720, approximately 120 seconds and silent. The cancelled queue destination remained absent. Original source, original session and prior-output sentinel hashes were unchanged; both owned staging types were absent. Normal app quit was confirmed before guarding the owned completed journal and restoring the previous recovery bytes. Local before/output/assertion/cancelled/completed/journal receipts remain in export-sleep/native outside Git. This is native macOS 27 evidence, not broader player/color/sleep-policy certification.

Ordinary hosted [run 36907486989](https://github.com/LynxTWO/staxrip-macos/actions/runs/36907486989) passed at c54f915: 270 tests in 413.269 seconds after a 66.97-second build, with 25 opt-in skips. Selected planning audit reports zero findings across 44 documents; this does not replace an all-history audit. S41-001 through S41-005 have scoped acceptance. Earlier unexplained hosted mastering cancellation delays remain an independent qualification trigger; no repair is claimed. No merge, release, owner listening or whole-program acceptance follows.
