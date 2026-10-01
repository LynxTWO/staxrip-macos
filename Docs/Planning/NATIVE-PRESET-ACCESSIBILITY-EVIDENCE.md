# Native preset accessibility evidence

Date: 2026-09-30. Slice 023, D-036 / R-026. Status: existing regression passed; app build passed in 14.82 seconds; native passed; hosted pending.

Quick Export derives a short native-preset label through the shared spokenCodecs helper, so H.264 becomes H two six four. A Selected or Not selected value follows the actual NativePreset selection. Visible preset names remain input aliases for voice control. Optional hints retain the Apple-preset explanation, expand AVC/HEVC, and explain that workspace encoding settings do not apply. Visible text, native preset identifiers and encoder behavior are unchanged.

No new tests mirror the text literals. The release framework reported 189 tests in 37 suites passed in 37.420 seconds, with 16 existing opt-in test entries skipped. The debug run has the same 16 opt-in skips; these include listening/long-resource, hardware and owned-volume checks and are not new coverage for this slice. Native accessibility-tree inspection verified exported names, hints and selection transitions in the rebuilt app. That is not a spoken VoiceOver or voice-control recognition test; owner listening and broader platform/keyboard qualification remain separate. No system accessibility preference is changed. Audio mastering/listening remains parked.

## Native receipt

The rebuilt app exposed Native H two six four 1080p and 720p preset names and Native HEVC 1080p, with the size separator retained. H.264 hints use digit-by-digit codec text and expand AVC; the HEVC hint expands High Efficiency Video Coding. All hints explain the independent Quick Export behavior. Starting at H.264 1080p, activation of 720p, HEVC and then 1080p left exactly one Selected accessibility value each time; the other two were Not selected. A native screenshot confirmed unchanged visible titles, descriptions and selected-card styling. No source or export was needed for this semantics check, and no system accessibility setting was changed.

S23-001 and S23-002 have direct native accessibility evidence; S23-003 has local regression/build and visible layout evidence. Hosted run 36804013683 at e2a543f has not passed; attempt 2 is pending. Voice-control input aliases are configured in source; actual voice recognition and spoken VoiceOver remain separate owner checks.

## Hosted gate investigation

Attempt 1 ran from 02:03:35 to 02:24:15 UTC on 2026-10-01 and was cancelled after exceeding 20 minutes. Its retrieved log contains a container-inspection fixture marker deadline failure, multiple 60-second test limits and two 120-second limits, then no later test progress before cancellation. It is not acceptance evidence. No label assertion or compilation failure was reported. The underlying cause is unknown; simultaneous process-heavy tests and worker contention are hypotheses, not a verified diagnosis.

One unchanged-commit retry, attempt 2, started at 02:25:00 UTC. A separate local debug regression passed all 189 tests in 37 suites in 214.521 seconds. A process sample confirmed active metering computation and an idle main event loop at 02:25 UTC. The hosted attempt recorded 30 issue records across multiple suites; no root cause is established. Existing audio regression executes without changing the parked audio feature scope. Preserve the failed receipt even if the retry passes. No additional tests were disabled, assertions relaxed, or limits increased.
