# Quick Export final publication evidence

Date: 2026-09-30. Slice 021, D-034 / R-024. Status: focused checks passed; direct-call negative control failed as required; full local regression/build passed; native and hosted gates pending.

## Behavior

NativeExportService reuses ExportPublication.publishAsync for the completed MP4. The service checks cancellation before dispatch, then retains ownership until the filesystem result returns. A successful save remains successful across late cancellation; a collision or other publication error remains a failure. Owned staging cleanup follows the result, and cleanup failure still carries the published output when present.

ExportController exposes runtime-only finishing state. Final saving stops estimated encoding progress, displays waiting text, and disables the obsolete Cancel action. Late cancellation through the controller keeps the waiting message and does not turn a completed save into a cancelled export. Success records complete progress; cleanup warnings preserve the saved result. No preset, saved schema, native source preparation or audio behavior changes.

## Focused verification

Ten native export test functions passed in 0.710 seconds on the development Mac. Two new functions cover cancellation immediately before final dispatch, plus four real-native-export cases with a held filesystem operation: success, competing output, permanent publication refusal and cleanup refusal. The held cases require MainActor to run before releasing the worker, active service/controller and retained staging during cancellation, preserved source/prior-output bytes and correct final result. The collision case also retries with a new destination and confirms the competing file is unchanged.

Initial implementation diagnostics were resolved before this focused pass: actor-isolated service creation moved inside the controller initializer, and completed progress is explicitly recorded after the finishing guard. An initial dispatch-removal experiment did not fail: Swift's nonisolated async helper still ran away from MainActor. That is not evidence for the intended regression. The test seam was narrowed to the synchronous filesystem operation so a direct service call can reproduce the relevant main-actor blocking regression.

## Limits and pending evidence

No arbitrary filesystem latency bound is claimed. Native source preparation, destination prechecks, save-panel modality and cleanup I/O remain separate. The held operation is deterministic test infrastructure after a real AVFoundation export; it does not establish every network/removable filesystem behavior. Native normal/refusal/retry checks and final local/hosted receipts remain pending. Audio and production distribution stay outside this slice.

The direct-call negative control replaced the service’s awaited helper call with the synchronous filesystem operation. All four cases failed after 120.263 seconds with eight issues: mainThread was true and the UI continuation could not observe/release the still-active held operation. Each independent 30-second gate timed out, preventing an indefinitely hung test. The asynchronous service call was restored before regression/build.

Final local release regression passed 186 tests in 36 suites in 37.064 seconds. The ad-hoc app built in 13.81 seconds. These runs used the restored asynchronous publication implementation.
