# StaxRip Mac Slice 025: Review restored source access
Version: 0.2. Date: 2026-10-01. Status: Accepted within evidence limits under D-039 / R-029.

SLICE STATE
Milestone: Local/native/hosted acceptance passed at 42c8c07; hosted run 36812490982.
Blocked by: None.
Evidence so far: RESTORED-SOURCE-EVIDENCE.md, including complete native session round-trip equality.
Last audit: 2026-10-01.

## 1. What the slice proves

A restored session retains its source reference and recipe without reading that media until a deliberate matching-source selection. The preview state describes the required action rather than claiming decoder failure. Existing evidence supports an explicit review path, not a diagnosis of macOS permissions.

## 2. The walkthrough

Open a generated saved session. Its settings, name and queue appear without starting source loading. Choose Review saved source, cancel, and verify all intent remains. Choose a different path and receive a useful refusal without replacement. Select the saved path; preview loading starts and succeeds while saved crop, trim, track choices, captions and output name remain. A failure leaves the review action available. Open source still supports deliberately choosing a new video with the established reset behavior.

## 3. In scope, with build order

M1: Process-local pending review state, no media-path fileExists or native read during restoration, and a matching-source selection method using the existing request identity/snapshot checks. M2: Attached source-review picker and explicit workspace/Quick Export entry points; source inspection, tracks and filtered preview wait for review. M3: lifecycle/refusal/retry regression, full suite, native generated session cancel/review and saved-intent check, app build and hosted gate.

## 4. Out of scope

Bookmarks, source relocation, source-content identity claims, session schema changes, queue path changes, encoder changes, audio work/listening, arbitrary filesystem deadlines, security preferences, merge and distribution. Queue preflight and execution remain separately deliberate operations with their existing checks.

## 5. Stubs and debts

No stub inside this path. A matching path does not prove unchanged bytes. Source identity checks before publication remain separate. External captions and queue paths keep their established access review. Uncooperative prior native reads still need actual settlement; this slice does not abandon them.

## 6. Modules touched

WorkspaceModel, WorkspaceFilePanels, WorkspaceView, QuickExportView, source lifecycle and focused restored-review tests. SessionDocument is read-only; no persisted data change.

## 7. Data subset

One process-local sourceNeedsReview state derived on session restoration, cleared by demo or successful explicit source load. Keep sourceURL so session snapshots and queue intent retain the saved path. Existing sourceUnavailable still prevents native export when preview is unavailable.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S25-001 | Restore never starts a media reader and retains full saved intent, including after an older read settles | Controlled reader and existing restoration lifecycle regression | restored-source-idle |
| S25-002 | Matching selection reads once and preserves intent; cancel, wrong path, stale/duplicate callbacks, failure and retry do not replace intent | Injected presenter/reader counterexamples | restored-source-review |
| S25-003 | Workspace and Quick Export explain pending review; native cancel and matching picker succeed with retained recipe/name | Generated native session walkthrough | restored-source-native |
| S25-004 | Existing source replacement, session validation and encoding remain intact | Full local/hosted suite, app build, planning audit | restored-source-regression |

## 9. Verification evidence required

Generated existing and missing paths only. Preserve the old test's ownership and stale-result assertions while changing its automatic-restore expectation through this explicit decision. Native evidence must distinguish cancellation of a picker from cancellation of a running reader. No new timeout claim or broad resource harness.

## 10. Guardrails

No media reads simply to display pending status. Match standardized path without resolving filesystem identity. Wrong-path refusal points to Open source for deliberate replacement. No saved settings, captions or queue mutation on review cancellation/failure. Source inspection controls cannot accidentally bypass the review state.

## 11. Definition of done

All four criteria have scoped evidence, final hosted head passes and audit is clean. Prior native-I/O limits remain recorded. No claim of durable access or production completion.

## 12. What this unlocks

A predictable session reopening path. Future source relocation and durable access can build on an explicit review state.

Approved for build by: Owner overnight autonomous non-audio delegation, 2026-09-30; D-039 / R-029.
