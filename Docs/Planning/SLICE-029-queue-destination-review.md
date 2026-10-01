# StaxRip Mac Slice 029: Review batch destinations before starting
Version: 0.2. Date: 2026-10-01. Status: Accepted within evidence limits under D-043 / R-033.

SLICE STATE
Milestone: Local/native/hosted checks passed at 485ea85; hosted run 36818937608.
Blocked by: None.
Evidence so far: QUEUE-DESTINATION-REVIEW-EVIDENCE.md records ordered review, protected cancellation, actual/native batches and regression. Earlier filesystem waits remain unresolved.
Last audit: 2026-10-01.

## 1. What the slice proves

Starting a queue from the native interface reviews each distinct pending destination folder before the batch controller starts. No encoding or recovery-record replacement occurs until every configured folder matches and the captured queue remains current.

## 2. The walkthrough

Open a generated three-job queue using two output folders. Start queue opens an attached folder review that explains when execution starts. Review the first folder and cancel the second; the queue, existing recovery record and outputs remain untouched. Retry and match both folders; the three jobs complete, each shared folder having appeared once. No destination path is silently changed.

## 3. In scope, with build order

M1: Reuse workspace dialog request ownership for sequential folder selection, capturing queue intent and pending job identities. M2: Deduplicate standardized folder paths, refuse cancellation/mismatch/stale/busy/duplicate callbacks, and disable competing native controls. M3: Generated callback counterexamples and real batch execution, native two-folder cancellation/completion, full local/build/hosted regression.

## 4. Out of scope

Persistent permissions or bookmarks, broad folder grants, a claimed filesystem-wait fix, source relinking, automatic path correction, new batch execution policy, audio, stored schemas, merge and release. The existing read-only Check queue remains independent.

## 5. Stubs and debts

Selection is a current user review, not proof of durable access, capacity or bounded filesystem latency. All independent batch checks, source fingerprints and exclusive publication remain mandatory. No stub inside the reviewed-start lifecycle.

## 6. Modules touched

WorkspaceModel, WorkspaceFilePanels, QueueView and a shared pending-jobs query in BatchController. Reuse the established presenter protocol and existing batch execution without a second dialog owner or new persistence.

## 7. Data subset

Process-local full session snapshot, current source-load identity, pending job IDs and deduplicated standardized destination folder URLs. Each sheet owns a fresh request identity so an earlier callback cannot consume a later selection. No filesystem writes before the existing batch start.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S29-001 | Each distinct pending folder is reviewed once; completed-only queues do not open a dialog | Controlled presenter tests | queue-destination-sequence |
| S29-002 | Cancel, wrong location, stale intent/availability and duplicate/old callbacks cannot start or replace recovery state | Generated lifecycle counterexamples and unchanged bytes | queue-destination-protection |
| S29-003 | Native attached reviews explain the start boundary; second-folder cancel and corrected retry work | Generated native three-job walkthrough and output inspection | queue-destination-native |
| S29-004 | Real execution, all prior protections and other dialogs remain intact | Focused actual batch, full local/hosted tests, build and audit | queue-destination-regression |

## 9. Verification evidence required

Use generated media and isolated recovery journals. Native testing backs up the current recovery record before a generated batch and restores it only after the preview app exits. Record earlier waits honestly. No timeout relaxation, added opt-in exclusions or lowered verification thresholds.

## 10. Guardrails

The final folder button must clearly say it starts the queue. Earlier reviews must state that cancellation starts nothing. Match the selected standardized path exactly, without resolving symlinks or changing saved jobs. Check pending identities and execution availability at every transition. A refused sheet must release request ownership. Duplicate callbacks must not advance the sequence or initiate another batch.

## 11. Definition of done

All four criteria have scoped local/native/hosted evidence at the final product/test head. Existing filesystem and audio acceptance limits remain explicit.

## 12. What this unlocks

A visible destination decision before expensive batch work and recovery-record replacement.

Approved for build by: Owner overnight autonomous non-audio delegation, 2026-10-01; D-043 / R-033.
