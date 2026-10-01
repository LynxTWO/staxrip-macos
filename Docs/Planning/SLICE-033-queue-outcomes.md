# StaxRip Mac Slice 033: Queue outcomes and compact review
Version: 0.1. Date: 2026-10-01. Status: Approved for build under D-059 / R-041.

SLICE STATE
Milestone: Native presentation defect mapped; implementation not started.
Blocked by: None. Slice 032 accepted at 5e9effa, hosted run 36845548454.
Evidence so far: QueueView, BatchController, BatchJournal and prior native multi-job observations.
Last audit: 2026-10-01.

## 1. What the slice proves

Users can tell what the queue accomplished and what needs attention, then inspect or correct a job without routine detail obscuring the remaining jobs. The current static Ready when you are heading is misleading after completion.

## 2. The walkthrough

Open a generated multi-job session. Review compact output/source/recipe rows, expand paths and checks, and start through the existing destination review. Observe real running and completed summaries, reveal an output, then remove its configuration without deleting the output. Cause an existing-output collision and see the failure/remedy without opening a disclosure. Inspect cleanup-warning behavior through real injected cleanup-failure tests, preserving the saved output and visible warning. Check keyboard controls and light/dark presentation.

## 3. In scope, with build order

M1: A read-only presentation adapter for current job IDs and actual statuses, with state counterexamples. M2: Truthful header/counts and compact native job rows. Routine details use a disclosure; active state, failures, interrupted/cancelled outcomes, preliminary issues and cleanup warnings remain visible. M3: Native success/failure/correction/removal walkthrough, existing cleanup/recovery protections and full regression.

## 4. Out of scope

Execution scheduling, retries without user action, aggregate ETA, source compatibility claims, new processing features, audio, saved schema changes, historical staging cleanup, release and merges. Workspace preview sizing and chapter grammar remain later presentation work.

## 5. Stubs and debts

No stub inside the queue path. Historical cleanup warnings live in BatchStatus.detail with a stable Cleanup warning: marker. The adapter recognizes that existing marker, including restored records, without interpreting paths or commands. It does not claim structured historical error classification. Current Completed means a recorded publication outcome, not a fresh filesystem existence check.

## 6. Modules touched

QueueView, a read-only queue presentation helper, scoped tests and evidence. BatchController/BatchJournal remain authoritative and their execution/serialization contracts stay unchanged. Existing file-access controls and destination review remain available.

## 7. Data subset

Current QueueJob IDs, source/destination names, requested recipe, BatchStatus, preliminary QueueCheck and controller running/review/publication flags. Ignore orphan status records. Counts distinguish completed, remaining and needs-attention; attention may overlap completed when cleanup warned. No new persisted state or files beyond generated verification fixtures.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S33-001 | Empty, pending, active, complete, partial failure, interrupted and cleanup-warning summaries reflect current jobs without false readiness or success | State counterexamples and real controller outcomes | queue-outcomes |
| S33-002 | Completed rows are compact; active/failure/cleanup information stays visible and detailed verification/paths remain accessible | Native light/dark and keyboard/disclosure walkthrough | queue-presentation |
| S33-003 | Editing, duplication, reordering, access review and output reveal remain available under existing guards | Native action walkthrough and existing queue tests | queue-actions |
| S33-004 | Removing a configuration does not remove its saved output; cleanup warnings retain the publication outcome and retry semantics | Native protected bytes and real cleanup/recovery tests | queue-ownership |
| S33-005 | Prior behavior remains qualified | Full local/hosted tests, ad-hoc build, audit | queue-regression |

## 9. Verification evidence required

Use generated sources and isolated output folders. Preserve the current journal and verify any restoration. Require actual encoded output metadata and bytes, not only a Completed label. Verify error text without expansion and ordinary detail expansion through native accessibility. Exercise missing/orphan/mixed statuses and completed-with-cleanup so visual simplification cannot conceal an unresolved outcome. Existing publication and source assertions stay unchanged. Tests target truthful state/ownership, not view structure or pixel snapshots.

## 10. Guardrails

Never remove media through queue removal. No automatic processing when a session opens. No inferred success from queue emptiness or file names. Keep publication waiting language and explicit cancellation behavior. Text and icons convey state independently of color. Source/destination paths remain selectable in details; standard native controls retain accessibility labels and hints.

## 11. Definition of done

All five gates have scoped evidence at the final product head, with failures and limitations recorded. No merge/release or broader production-completion claim.

## 12. What this unlocks

A queue that serves as a clear execution record and correction surface for the existing encoder.

Approved for build by: Owner overnight autonomous non-audio and design delegation, 2026-10-01; D-059 / R-041.
