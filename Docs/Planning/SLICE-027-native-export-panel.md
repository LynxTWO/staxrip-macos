# StaxRip Mac Slice 027: Attach native export destination selection
Version: 0.1. Date: 2026-10-01. Status: Approved for build under D-041 / R-031.

SLICE STATE
Milestone: Planning complete; implementation next.
Blocked by: None.
Evidence so far: ExportController.chooseDestination uses runModal; WorkspaceModel already owns attached requests with snapshot and load identity checks.
Last audit: 2026-10-01.

## 1. What the slice proves

Quick Export selects its destination through the existing attached workspace dialog lifecycle. Only a current source and preset with available execution may start one export. Cancelling or a stale callback preserves current work and previous results.

## 2. The walkthrough

Load a generated native-playable source, choose a native preset and open Export MP4. The destination sheet is attached to the workspace; file commands cannot open another request. Cancel and retain source/settings/result. Reopen, choose a new path and produce a native output through the existing service. An existing output remains protected. Changing source, preset or execution availability before a delayed callback refuses that callback with a correction message.

## 3. In scope, with build order

M1: Add a native export request to WorkspaceFilePanels and route it through WorkspaceModel ownership. M2: Capture preset and source intent, reject stale/duplicate callbacks and unavailable execution; remove the controller's nested save panel and update Quick Export controls. M3: injected lifecycle counterexamples, real native export/no-overwrite checks, native sheet cancellation and export walkthrough, full regression/build/hosted gate.

## 4. Out of scope

Changing AVFoundation presets or publication, suppressing the system existing-file Replace prompt, queue access policy, persistent file permissions, arbitrary filesystem latency, audio workflows, saved schemas, merge or distribution. Existing-file refusal remains in NativeExportService; panel wording is not a replacement guarantee.

## 5. Stubs and debts

No stub in the dialog/start path. Native source preparation and filesystem waits retain their existing limits. A future collision UI fix needs separate AppKit callback and extension-handling evidence.

## 6. Modules touched

WorkspaceFilePanels, WorkspaceModel, QuickExportView, ExportController's destination entry point, focused lifecycle tests. NativeExportService remains the real executor and is not changed.

## 7. Data subset

Process-local request ID, captured workspace snapshot, source-load identity and native preset. No stored format or source bytes change. A supplied availability predicate checks competing audio/batch work at selection and completion.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S27-001 | Cancel, refused presentation, repeated/old callbacks, changed source/preset and busy execution cannot start unintended exports | Injected presenter lifecycle tests | native-panel-lifecycle |
| S27-002 | Current selection starts exactly one real export and protects source/prior output | Generated native export and collision regression | native-panel-export |
| S27-003 | Attached sheet, disabled competing file commands, cancellation and export work in app | Native generated walkthrough | native-panel-ui |
| S27-004 | Existing exports, workspace dialogs and recovery stay intact | Full local/hosted suite, build and audit | native-panel-regression |

## 9. Verification evidence required

Generated files only; no user media. Test actual export publication through NativeExportService and compare bytes for source/existing destination. A stale callback must not change the controller's current result. No new broad timing harness or relaxed test limits.

## 10. Guardrails

Reuse existing one-request ownership and source-load identity. Capture the preset and require it to remain current. Missing parent windows refuse without silently queuing a panel. Preserve service no-overwrite checks and completion/cleanup semantics. The attached sheet itself does not establish durable file access.

## 11. Definition of done

All four criteria accepted within recorded scope, including final hosted head. Audio listening remains parked.

## 12. What this unlocks

Consistent native file selection and a reusable entry point for future destination UX improvements.

Approved for build by: Owner overnight autonomous non-audio delegation, 2026-10-01; D-041 / R-031.
