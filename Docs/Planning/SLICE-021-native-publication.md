# StaxRip Mac Slice 021: Responsive Quick Export publication
Version: 0.1. Date: 2026-09-30. Status: Approved for build under D-034 / R-024.

SLICE STATE
Milestone: Plan committed before implementation.
Blocked by: None; Slice 020 closed at 1933bee with hosted run 36799453765.
Evidence so far: NativeExportService calls synchronous publication on MainActor; advanced batch already uses the asynchronous helper. This is a source finding, not a reproduced native filesystem stall.
Last audit: 2026-09-30.

## 1. What the slice proves

Quick Export keeps the UI executor available while publishing a completed MP4 and reports the actual save outcome before cleaning its owned staging. A cancellation arriving during the filesystem operation cannot erase a successful save or hide a publication failure.

## 2. The walkthrough

Open generated native media, choose Quick Export and a new MP4 destination, and run an Apple preset. Encoding retains Cancel export. Final saving shows an explicit finishing state; after the filesystem operation and cleanup settle, the user sees a saved result or an actionable failure. A failed publication can be retried with a new destination. Existing outputs and source bytes are retained.

## 3. In scope, with build order

M1: Reuse ExportPublication.publishAsync in NativeExportService, with an injectable publication seam and explicit finishing notification. Preserve filesystem errors and successful publication across late cancellation. M2: ExportController and QuickExportView show truthful final-save status, suppress obsolete encoding progress, and distinguish the point where publication cannot be recalled. M3: Deterministic held-publication tests through a real native export, success/collision/error/cleanup cases and a negative control. M4: Full regression, app build, native preset export/refusal/retry walkthrough and hosted validation.

## 4. Out of scope

Native source preparation cancellation, source fingerprints, save-panel conversion, broader native output verification, new presets, media transforms, audio mastering, persistent schemas, merge, signing and release. Synchronous filesystem calls outside final publication remain separate.

## 5. Stubs and debts

No early timeout abandons an in-flight filesystem operation. Finishing may wait on a stalled destination. This slice makes that wait owned and keeps the UI executor available; it does not bound filesystem latency. Native presets keep their existing documented media behavior.

## 6. Modules touched

NativeExportService, ExportController, QuickExportView, native export tests and scoped evidence. Reuse the shared ExportPublication utility worker and existing cleanup routine.

## 7. Data subset

Runtime-only finishing state and owned staged/destination URLs. One native export remains active until publication and cleanup settle. No serialized format change, automatic queue execution, overwriting or historical staging deletion.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S21-001 | A held final publication does not occupy MainActor, and its stage stays owned until the true result | Real native export plus held worker, main-actor assertion and negative control | native-publication-responsive |
| S21-002 | Cancellation during publication preserves successful output and filesystem failure; cleanup follows settlement | Success, competing output, permanent failure and cleanup warning cases | native-publication-outcome |
| S21-003 | Final-save UI is explicit and obsolete progress cannot replace it; retry remains possible | Controller test and native normal export/refusal/retry | native-publication-ui |
| S21-004 | Existing native presets, cancellation and source/output protection remain intact | Full local and hosted regression, native generated fixture hashes | native-publication-regression |

## 9. Verification evidence required

Held publication begins after actual native writer completion and validation. Tests must prove main-actor availability before releasing the worker, retained stage and active ownership during cancellation, source/prior-output byte equality, true success/collision/error outcomes, cleanup warnings and fresh retry. Omission of asynchronous dispatch must fail a bounded negative control. Native generated MP4 export and existing-output refusal/retry provide UI evidence; arbitrary filesystem stalls and spoken VoiceOver remain separate.

## 10. Guardrails

Only publish the current operation's completed staged output. Await filesystem outcome before cleanup. Never delete or relabel a saved result as cancelled. Never suppress a publication error because cancellation arrived later. Finishing state stays distinct from estimated encoding progress. No user media in fixtures.

## 11. Definition of done

S21-001 through S21-004 have scoped local/native/hosted receipts. The planning audit passes and remaining synchronous I/O limits are recorded.

## 12. What this unlocks

Consistent final-save ownership across the native and advanced engines, with a clear seam for future native validation and file-access work.

Approved for build by: Owner autonomous non-audio delegation under D-034 / R-024, 2026-09-30, after Slice 020 closure.
