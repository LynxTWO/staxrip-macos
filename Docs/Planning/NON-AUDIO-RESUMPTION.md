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

Slice 009 hosted run 36711323507 passed at 8eef657 in 8 minutes 35 seconds. PR 26 remains draft and unmerged. Cleanup criteria are closed within the recorded scope.

Slice 010 adds read-only chapter/attachment inspector sections and stale-request protection. Four focused tests, the 113-test regression and native populated/cover-art/empty source walkthroughs passed. A native section-identity reuse issue was fixed and retested. Source/recovery bytes stayed unchanged. Hosted check pending; see CONTAINER-INSPECTION-EVIDENCE.md.

Slice 010 hosted product acceptance passed at 087adcc (run 36713752263, 9m37s). Slice 011 is active under D-024/R-014; scoped pre-publication chapter/attachment verification and local tests are implemented. Native acceptance is blocked by the locked Mac; see CONTAINER-PRESERVATION-EVIDENCE.md. Audio remains parked.

Slice 011 acceptance closed after native generated export/output inspection and hosted product success at d297f75, run 36716287551. See CONTAINER-PRESERVATION-EVIDENCE.md. Audio remains parked.

Slice 012 actual capacity exhaustion and native retry passed on a disposable 64 MiB HFS+ image, now detached. No product fix was needed; opt-in regression and scoped evidence are recorded in DESTINATION-CAPACITY-EVIDENCE.md. Hosted ordinary regression is next.

Slice 012 closed with hosted success at a995ab3, run 36766809385 (9m31s), after correcting and negatively testing the inherited cancellation startup gate. Capacity evidence remains the separate local opt-in run, not a hosted disk-image claim.

Slice 013 verifies resized raster output before publication. Focused, regression and explicit-picker native checks passed; hosted pending. Native investigation also found file-open waits for a restored source and a main-thread link syscall blocking publication until the destination had been selected through the native picker. These remain explicit reliability findings in PICTURE-GEOMETRY-EVIDENCE.md. Audio remains parked.

Slice 013 geometry acceptance closed with hosted success at 30b044b, run 36769620823 (9m19s). Restored-session access and blocked-publication responsiveness remain the next scoped reliability work.

Slice 014 moves advanced batch publication off the main thread while awaiting its true result before cleanup. Held-operation cancellation and collision tests, regression and native per-job access/encode checks passed; hosted pending. See PUBLICATION-RESPONSIVENESS-EVIDENCE.md. Audio remains parked.

Slice 014 scoped acceptance closed at f20998f with hosted run 36778465280 (9m05s). Final release/debug suites passed 125 tests; deliberate delayed-publication negative controls and isolated ENOSPC/retry also passed. Synchronous filesystem calls outside advanced batch publication and durable access remain open. Audio remains parked.

Slice 015 is active under D-028/R-018: one source-specific external plain UTF-8 SRT, fresh captured staging, MKV/MP4 cue verification, native controls and saved-data migration. Research shows overlap, styling and line-edge whitespace need explicit refusal. No new audio acceptance is included.

Slice 015 local acceptance passed: 142 tests / 28 suites, native independent MKV/MP4 caption exports, session round-trip and attached session dialog recovery. Hosted check pending; see EXTERNAL-SUBTITLE-EVIDENCE.md.

Slice 015 initial hosted run 36783897395 passed at bb9a765 (142 tests, 9m37s). Review then found canonical Unicode title equality could hide byte-distinct intent changes. A negative-control regression reproduced broken change detection/undo; the fix passes the final 143-test local regression. Final hosted follow-up pending.

Slice 015 scoped acceptance closed at b3027f2 with hosted run 36785205441: 143 tests, 9m46s. External plain SRT, exact added cue/metadata checks, session migration and native controls are covered within the evidence limits. Broader subtitles and owner audio listening remain open.

Slice 016 is active under D-029/R-019: attached workspace source/folder/session/queue-reference dialogs with one request lifecycle, captured saves and stale callback protection. Audio remains parked.

Slice 016 local acceptance passed: six focused functions, 149 tests / 29 suites, native source/folder/session/reference sheets and cancellation, replacement cancel/confirm, unchanged source and structurally identical saved-session readback. Hosted pending; see WORKSPACE-FILE-PANEL-EVIDENCE.md.

Slice 016 scoped acceptance closed at 42634d9 with hosted run 36787875488: 149 tests, 8m43s. Other app dialogs, synchronous filesystem I/O and durable access remain separate; audio remains parked.

Slice 017 is active under D-030/R-020: verify known declared display proportions after upright crop and resize, without inferring missing source pixel shape or changing filters. Audio remains parked.

Slice 017 local/native display-proportion verification passed, including 157 regression tests and exact versus unknown native outputs. A real near-square MKV rounding boundary remains a strict refusal; MP4 preserves that fixture. Hosted gate pending. See DISPLAY-ASPECT-EVIDENCE.md.

Slice 017 closed with hosted success at b177432, run 36790619197, 157 tests in 461.121 seconds and an 8m57s job. PR 34 stays draft and unmerged. Audio listening remains parked.

Slice 018 is active under D-031/R-021 after Slice 017 closure. Scope is decoded-timestamp stepping in the existing filtered still comparison, with explicit source identity, trim and lifecycle checks. Audio stays parked.

Slice 018 local/native frame stepping passed: 166 release tests, separate 4K resource check, exact VFR transitions and trim boundaries in the native comparison. Hosted regression pending. See FRAME-STEPPING-EVIDENCE.md.

Slice 018 closed with hosted success at fc1aa88, run 36792778159: 166 tests in 507.195 seconds, 9m53s job. Draft PR 35 remains unmerged; audio listening stays parked.

Slice 019 is active under D-032/R-022 after Slice 018 closure: export-only source byte fingerprints, regular-file checks, cooperative cancellation and protected progress. Audio stays parked.

Slice 019 local/native source stability passed: 173 release tests, before/after replacement negative control, held cancellation and a 4 GiB sparse native source export with byte progress and unchanged source receipt. Hosted run 36795072130 is pending at 1f552e9.
