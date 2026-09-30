# Non-audio resumption checkpoint

Date: 2026-09-29. Owner request: pause listening review while headphones are unavailable and pivot to the rest of StaxRip.

## Preserved audio state

Slice 002 is paused, not complete or accepted. Keep the independently verified v2 local listening pack, blank owner ratings, full-master receipts and concealed comparison key. Resume from LISTENING-MANIFEST.md when headphones are available. Wider comparison settings do not close the stricter real-film failures or establish 3 LU performance. No DSP settings, defaults or tolerances changed for this pivot.

## First priority: existing native export reliability

The latest hosted run at 8fc901a failed one existing cancellation test on macOS 15.7.9: cancellationOfActiveSessionCleansItsStagingDirectory, iteration 5, ExportTests.swift:94. A .staxrip-export- directory remained after return. Run: https://github.com/LynxTWO/staxrip-macos/actions/runs/36480653924/job/109125167447

A fresh local `swift test --filter ExportTests` on 2026-09-29 passed all five tests, including eight active-cancellation cases and three native presets, in 0.586 seconds after build. This does not clear the hosted failure. Root cause is unknown. NativeExportService currently waits for the AVFoundation completion callback but silently ignores staging removal errors. Next investigation should capture the actual cleanup error and directory state, distinguish callback/writer timing from filesystem failure, and retain the no-publication invariant. Do not suppress the test or claim the race fixed from a local pass.

## Next capability: explicit video color information

Source inspection shows MediaProbe currently retains transfer and pixel format, but not primaries, matrix, range, frame timing or sample aspect ratio. MediaInspectorView only displays transfer when present. EncodePlan accepts yuv420p/nv12 and rejects PQ/HLG; this is an SDR restriction, not HDR support. A focused next brief should expose known and unknown color/timing information with understandable VoiceOver labels, then define an explicit output color verification contract.

Keep actual HDR preservation and SDR tone mapping as separate follow-on contracts. Synthetic metadata checks alone cannot establish correct HDR pictures. Dynamic HDR metadata, calibrated visual evaluation and supported hardware coverage require explicit boundaries before implementation. Existing Quick Export uses Apple presets and needs a separate assessment; advanced-pipeline restrictions must not be described as universal app guarantees.

## Following priorities

Filtered preview and frame stepping; rotation and timestamp/remux handling; per-track recipes and subtitle/chapter handling; session persistence, custom presets and undo; production qualification. RELEASE-SCOPE.md remains the acceptance ledger. This order is a working priority, not a claim of completed implementation or an expansion of the parked audio brief.

No merge, signing submission or public release was performed as part of this pivot.

## Native cleanup hardening, 2026-09-29

NativeExportService no longer discards removal errors. After the AVFoundation completion callback, cleanup retries only EBUSY/ENOTEMPTY (including wrapped POSIX errors), at most six attempts with 1.55 seconds of total delay. The wait remains effective when the export task is cancelled. A missing directory is accepted only if the owned root is absent. A permanent failure reports the directory and error, preserves the operation error, and states whether output was already published. The controller retains the saved result when cleanup alone failed.

The original hosted failure did not record its underlying error, so its cause remains unknown. This change fixes silent cleanup failure and handles specific transient errors; it does not establish that the original race was reproduced or eliminated.

Validation: release regression reported 71 tests in 13 suites passed in 8.897 seconds (12 opt-in tests skipped). Final focused ExportTests passed eight tests in 0.603 seconds, including eight real active-cancellation cases, three native presets, cancelled-task retry, bounded persistent busy failure, immediate permission failure, a missing-child error with a remaining root, and saved-versus-unpublished error outcomes. Native release preview built with the local ad-hoc signature. A generated video completed through Quick Export; a separate longer generated source was cancelled through the native button. The UI restored source/export controls and stated no output was published. Filesystem checks confirmed no cancelled output or staging directories, while the completed output remained. This is local macOS 27 evidence; hosted macOS 15 remains a separate check.

Hosted follow-up: PR 17's first run failed the cancellation test differently: one export published before the cancellation callback ran. The callback was driven by a separately scheduled progress task, which can lose the scheduling race to a short export. NativeExportService now sends its initial progress notification synchronously after submitting exportAsynchronously and before suspension. The active-cancellation test requires that first notification to be zero, then cancels the submitted session. This addresses callback ordering; it does not retrospectively identify the earlier staging-removal error. Hosted confirmation remains required.
The concrete next proposal is SLICE-003-video-inspection.md. Its numbering supersedes the original proposed ordering: multichannel stays deferred while audio is parked. No video color implementation is included in the native cleanup PR.

## Current checkpoint, 2026-09-29

The earlier pending-hosted notes are historical. Native cleanup PR 17 passed run 36599311645; video inspection PR 18 passed run 36600485460; static HDR10 PR 20 passed run 36607764563 at product commit 16a889c. HDR10-EVIDENCE.md records the local native walkthrough and remaining production qualification. The next proposed capability is filtered picture preview. Audio listening stays paused. No PR has been merged or release published.

## Autonomous continuation checkpoint, 2026-09-29 evening

Owner approved the presented preview brief and delegated subsequent reasonable non-audio work. Slice 005 is implemented with local native comparison and hosted evidence (PR 22, run 36660799747, passed 8m44s). Slice 006 reusable presets and settings history is implemented with six focused checks and a 99-test release regression; its native walkthrough is blocked because the Mac locked and the UI tool requires manual unlock. CUSTOM-PRESET-EVIDENCE.md contains the resume checklist. Do not bypass the lock or declare program completion. Audio listening remains parked. All work stays in draft PRs; no merge or release.

## 2026-09-30 unlocked continuation

Slice 006 native preset save/restart/apply/undo and import/export checks passed. The walkthrough found an extra observer-generated settings history entry, repaired with atomic codec/engine control bindings. Eight focused tests and a 101-test release regression passed (14 opt-in skips); final queue-binding build and native transition check passed. Earlier hosted run 36661841249 passed at 1d17698; follow-up hosted check pending. Continue autonomous non-audio work under existing delegation. Audio listening remains parked; no merge or release.

## Slice 007 checkpoint

Slice 006 hosted follow-up passed in 8m53s at 0b4f96a (run 36703925176). Source orientation is implemented under D-020. Right-angle transforms, independent pixels, preview and eight real queue outputs pass; a reflected source is refused without publication. Full release regression: 103 tests/18 suites, 14 opt-in skips, 9.565 seconds. Native upright crop comparison and refusal passed. A minor idle-close status fix passed focused tests; final rebuild/reopen and hosted checks remain. See ORIENTATION-EVIDENCE.md. Audio listening remains parked.

2026-09-30: Slice 008 adds optional read-only queue preflight under D-021. Four focused tests, the 107-test regression and native invalid-trim correction/recheck passed. Source/recovery hashes stayed identical and outputs remained absent. Hosted check pending; audio listening stays parked. See QUEUE-PREFLIGHT-EVIDENCE.md.

Slice 008 hosted run 36709148929 passed at 852306f in 8 minutes 20 seconds. PR 25 remains draft and unmerged. Local and hosted queue preflight criteria are closed within the evidence limits.

Slice 009 local cleanup reporting passed ten focused tests, a 109-test regression and a native two-job generated-video batch. No staging remained and source bytes were preserved. Injected errors preserve published/cancelled/failed outcomes in recovery and stop later jobs. Hosted check pending; see BATCH-CLEANUP-EVIDENCE.md.
