# Quick Export final publication evidence

Date: 2026-09-30. Slice 021, D-034 / R-024. Status: focused checks passed; direct-call negative control failed as required; full local regression/build passed; native walkthrough passed; hosted gate passed at 3c56caa.

## Behavior

NativeExportService reuses ExportPublication.publishAsync for the completed MP4. The service checks cancellation before dispatch, then retains ownership until the filesystem result returns. A successful save remains successful across late cancellation; a collision or other publication error remains a failure. Owned staging cleanup follows the result, and cleanup failure still carries the published output when present.

ExportController exposes runtime-only finishing state. Final saving stops estimated encoding progress, displays waiting text, and disables the obsolete Cancel action. Late cancellation through the controller keeps the waiting message and does not turn a completed save into a cancelled export. Success records complete progress; cleanup warnings preserve the saved result. No preset, saved schema, native source preparation or audio behavior changes.

## Focused verification

Ten native export test functions passed in 0.710 seconds on the development Mac. Two new functions cover cancellation immediately before final dispatch, plus four real-native-export cases with a held filesystem operation: success, competing output, permanent publication refusal and cleanup refusal. The held cases require MainActor to run before releasing the worker, active service/controller and retained staging during cancellation, preserved source/prior-output bytes and correct final result. The collision case also retries with a new destination and confirms the competing file is unchanged.

Initial implementation diagnostics were resolved before this focused pass: actor-isolated service creation moved inside the controller initializer, and completed progress is explicitly recorded after the finishing guard. An initial dispatch-removal experiment did not fail: Swift's nonisolated async helper still ran away from MainActor. That is not evidence for the intended regression. The test seam was narrowed to the synchronous filesystem operation so a direct service call can reproduce the relevant main-actor blocking regression.

## Limits and pending evidence

No arbitrary filesystem latency bound is claimed. Native source preparation, destination prechecks, save-panel modality and cleanup I/O remain separate. The held operation is deterministic test infrastructure after a real AVFoundation export; it does not establish every network/removable filesystem behavior. Final hosted acceptance passed. Audio and production distribution stay outside this slice.

The direct-call negative control replaced the service’s awaited helper call with the synchronous filesystem operation. All four cases failed after 120.263 seconds with eight issues: mainThread was true and the UI continuation could not observe/release the still-active held operation. Each independent 30-second gate timed out, preventing an indefinitely hung test. The asynchronous service call was restored before regression/build.

Final local release regression passed 186 tests in 36 suites in 37.064 seconds. The ad-hoc app built in 13.81 seconds. These runs used the restored asynchronous publication implementation.

## Native walkthrough

The rebuilt app opened a generated 160 x 96, 24 fps, one-second MP4 through its native file chooser. Quick Export with the 720p H.264 preset saved first-native.mp4 and reported Export complete with reveal/preview controls. Selecting the pre-existing generated protected.mp4 reached macOS’s replacement prompt; after proceeding through that test-only prompt, the application refused with That output already exists and left the file unchanged. Choosing a new name and the HEVC preset saved retry-hevc.mp4 and reported Export complete. Opening another save dialog and pressing Escape retained the existing result and preset.

Independent FFprobe inspection found one H.264 or HEVC video stream respectively, both 160 x 96 and 1.000000 second. Source and protected-file SHA-256 values matched the before receipt; no owned staging directory remained. The normal completed layout was inspected without clipped controls. These fast local saves did not provide a sustained native finishing-screen observation; held service/controller tests establish that state and ownership. Spoken VoiceOver and a real slow destination remain separate coverage. The existing save dialog still offers a replacement prompt before the app refuses; destination-dialog usability is outside this publication slice.

Receipts and generated fixtures are ignored work/native-publication; hosted run 36801364346 passed at 3c56caa: Swift 6.1.2, 186 tests in 403.950 seconds, 8m11s job. No source media, binaries or local paths are committed.

## Acceptance mapping

S21-001: held real-native-export filesystem cases require an available MainActor and retained stage; direct-call negative control fails. S21-002: late-cancel success, collision, failure and cleanup-warning outcomes pass; pre-dispatch cancellation does not publish. S21-003: controller finishing/progress/retry checks pass, with scoped native normal/refusal/retry/Escape receipts. S21-004: final local and hosted 186-test regressions pass, with native source/prior-output hash protection. Broader filesystem and spoken accessibility limits remain as recorded above.
