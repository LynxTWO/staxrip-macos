# StaxRip Mac Slice 016: Attached workspace file dialogs
Version: 0.1. Date: 2026-09-30. Status: In progress.

SLICE STATE
Milestone: M1 through M3 local implementation, regression and native walkthrough passed; hosted pending.
Blocked by: None external. Slice 015 closed with run 36785205441.
Evidence so far: Six callback/document tests, 149-test optimized regression, all five native sheet flows and cancellation, session replacement cancel/confirm, identical session round-trip and exact queue-array readback. See WORKSPACE-FILE-PANEL-EVIDENCE.md.
Last audit: 2026-09-30.

## 1. What the slice proves

The workspace's source, destination, session and queue-reference file pickers remain attached to the app window and finish through a completion handler. Cancelling does not mutate workspace intent or write a file. Session replacement retains an explicit confirmation, and delayed callbacks cannot overwrite a workspace changed since the request.

## 2. The walkthrough

Open a generated source from the native source sheet. Select its destination folder. Save a generated session, modify settings, open the saved session, cancel replacement and verify the edits remain. Repeat and confirm replacement; jobs are restored but no encoding starts. Cancel each picker without changing intent. Export a queue-only reference file and verify it is not a session or an automatic execution request.

## 3. In scope, with build order

M1: A small window-attached file-panel presenter with one in-flight request and an explicit missing-window refusal, plus a native confirmation sheet. M2: Migrate only WorkspaceModel source, destination, Save session, Open session and Export JSON flows to callbacks with captured snapshots and stale-workspace checks. M3: Controlled callback tests for cancel, duplicate request, replacement cancellation/confirmation, stale completion and saved snapshot contents; existing session validation, regression, optimized build, native walkthrough and hosted check.

## 4. Out of scope

Audio or preset file pickers, Quick Export dialogs, general file I/O migration, persistent bookmarks, saved format changes, new overwrite policy, broader OS accessibility qualification, signing, merge and release. This does not claim every standalone modal is broken.

## 5. Stubs and debts

Panel interaction becomes completion-driven, but existing bounded session read/write operations remain synchronous. User-authorized Save-panel replacement behavior remains unchanged. No single file-picker selection guarantees durable filesystem access. In-flight presentation is transient, not stored in sessions.

## 6. Modules touched

Workspace file-panel presenter, WorkspaceModel file commands, relevant command/button availability, focused model/presenter tests and evidence. Reuse current SessionDocument validation and queue encoding.

## 7. Data subset

One active request token, captured SessionDocument or queue snapshot, optional selected URL and replacement response. No new persisted fields or credentials. A cancelled or stale request clears its presentation state without loading media or executing a job.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S16-001 | File sheets attach to the workspace and all five actions finish or cancel visibly | Native source/folder/session/reference walkthrough | workspace-panels-ui |
| S16-002 | Cancellation and delayed/repeated callbacks do not overwrite current workspace intent | Controlled presenter callbacks and snapshot checks | workspace-panels-lifecycle |
| S16-003 | Session replacement requires confirmation, validates input and never starts processing | Model tests and native cancel/confirm round trip | workspace-session-replacement |
| S16-004 | Saved session and queue reference contain the captured intended data | Generated file readback plus existing validation regression | workspace-panel-save |

## 9. Verification evidence required

Focused callback and real document tests, ordinary regression, optimized ad-hoc build, native panel cancel/confirm walkthrough and hosted result. Report only tested OS/CPU. Any native automation limitation remains explicit.

## 10. Guardrails

No automatic queue execution, silent relinking, new broad permissions or stale callback application. Preserve validation and replacement confirmation. Close/order out the file sheet before presenting a follow-up alert, as Apple's completion-handler documentation recommends.

## 11. Definition of done

S16-001 through S16-004 have scoped local/native/hosted evidence and outstanding platform/filesystem limits are recorded. No whole-program completion claim.

## 12. What this unlocks

Later migration of other native dialogs can use the established lifecycle contract within separate audio or exporter scope.

Approved for build by: Owner autonomous non-audio delegation, activated under D-029 / R-019 after Slice 015 closure.

## Implementation notes

Use a small injectable presenter so model tests can return delayed, cancelled and duplicate callbacks without opening native windows. A single model request token spans file selection and session replacement confirmation. Source/folder/session-load results must refuse stale workspace intent or source-load identity; successful save records the captured document as the saved baseline so intervening changes remain dirty. Queue export stores only the queue array, not a session envelope. Release the presenter before invoking callbacks and order out the file sheet before alert presentation. Existing file validation and atomic save behavior remain unchanged.

Primary references checked 2026-09-30: Apple's NSSavePanel beginSheetModal(for:completionHandler:) documentation says callbacks can run while the sheet is still onscreen and recommends orderOut(nil) before a follow-up alert. NSWindow beginSheet documentation says ordinary sheets queue when another sheet is attached, so explicitly refuse duplicate requests rather than relying on implicit queuing.

- https://developer.apple.com/documentation/appkit/nssavepanel/beginsheetmodal(for:completionhandler:)
- https://developer.apple.com/documentation/appkit/nswindow/beginsheet(_:completionhandler:)

The proposal excludes general audio, preset, Quick Export or termination-alert migration. No claim that all standalone dialogs fail.
