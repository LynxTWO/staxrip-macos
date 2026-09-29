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
