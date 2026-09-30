# StaxRip Mac Slice 014: Responsive batch publication and file-access review
Version: 0.1. Date: 2026-09-30. Status: In progress.

SLICE STATE
Milestone: M1 through M3 local and native checks passed; hosted regression pending.
Blocked by: None external.
Evidence so far: PUBLICATION-RESPONSIVENESS-EVIDENCE.md records worker/cancellation/collision tests and native access/encode acceptance, with actual blocked-native-call reproduction not claimed.
Last audit: 2026-09-30.

## 1. What the slice proves

An advanced batch's potentially blocking publication syscall does not occupy the UI thread. While publication is in flight, the user can understand the finishing state, request that later jobs stop and review access to the intended destination through the native picker. Published media is never relabelled cancelled merely because cancellation arrived during publication.

## 2. The walkthrough

Load a generated session pointing at a new test folder. Review source or destination access using per-job native pickers, without changing intent or starting a job. Start the batch. During finishing, UI remains responsive; Stop after current publication requests cancellation of later work while the current result settles. A successful publication remains Completed. Failure publishes nothing and cleans owned staging only after the operation has returned.

## 3. In scope, with build order

M1: Add an asynchronous wrapper for the existing exclusive no-overwrite publication operation, dispatched away from the main thread; keep its primitive unchanged. M2: Use it in BatchController with an ephemeral publication identity, truthful cancellation/detail and per-job native source/destination access review. M3: Held-operation concurrency/cancellation/failure tests, real publication tests, journal restoration checks, regression, native walkthrough and hosted check.

## 4. Out of scope

Rewriting every filesystem call, arbitrary permission management, Full Disk Access, security-scoped bookmark storage, automatic path relinking, stale staging cleanup, timing out a still-running syscall, force-killing the writer as a normal cancellation feature, Quick Export or audio publication migration, signing, merge and release.

## 5. Stubs and debts

A blocked kernel filesystem call may not be cancellable. The wrapper waits for its result before cleanup and does not promise a hard timeout. A cancellation during publication stops later jobs after the current publication settles; a successful output remains completed and preserved. Other synchronous filesystem calls and non-batch exporters remain separate work. Picker selection does not guarantee every OS or remote-filesystem access issue is resolved.

## 6. Modules touched

ExportPublication wrapper, BatchController publication/cancellation seams, QueueView per-job access actions and finishing labels, targeted tests and evidence. Keep persisted phase Verifying during publication, with ephemeral UI state only, so existing recovery validation/restoration remains unchanged.

## 7. Data subset

Existing source/destination URLs, current publishing job ID, transient access messages and cancellation intent. Native panels only review the selected existing source or destination parent; a different selection does not rewrite queue paths. No credentials, broad security settings, new session fields or recovery version.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S14-001 | Publication work is off the main thread and UI work can run while it is held | Controlled blocking worker and main-actor heartbeat | publication-responsive |
| S14-002 | Cancellation during eventual success keeps Completed output, stops later jobs and waits before cleanup | Real queued fixture with held publication | publication-cancel-success |
| S14-003 | Publication failure preserves source/prior outputs and cleanup ownership | Held failure and existing exclusive publication tests | publication-failure |
| S14-004 | Native access panels preserve configured paths, finishing controls are understandable and ordinary encode completes | Generated native session and panel cancel/selection | publication-access-ui |

## 9. Verification evidence required

Focused worker/main-actor and queue outcome tests, no-overwrite and journal checks, ordinary regression, optimized build, native access/encode walkthrough and hosted result. Actual native blocked-call reproduction is reported separately from deterministic held-operation evidence.

## 10. Guardrails

No replacement publication and no cleanup until the in-flight publication resolves. No post-success cancellation check that hides a published output. Keep batch journal lease held until final outcome. Native pickers do not alter source/destination intent. Do not claim the observed OS wait is fully diagnosed or all I/O now asynchronous.

## 11. Definition of done

S14-001 through S14-004 have scoped local/native/hosted evidence; remaining OS and other-call-site limits are recorded. No whole-app completion or audio acceptance claim.

## 12. What this unlocks

Later filesystem responsiveness work can migrate other call sites with their own lifecycle evidence; explicit bookmark persistence needs a separate saved-data design.

Approved for build by: Owner autonomous non-audio delegation; activated under D-027 after Slice 013 closure.
