# StaxRip Mac Slice 009: Report batch staging cleanup
Version: 0.1. Date: 2026-09-30. Status: Done with evidence.

SLICE STATE
Milestone: M1 and M2 implemented; M3 automated, native and hosted checks passed.
Blocked by: None external.
Evidence so far: BATCH-CLEANUP-EVIDENCE.md records ten focused tests and the 109-test regression.
Hosted: run 36711323507 passed at 8eef657 in 8 minutes 35 seconds.
Last audit: 2026-09-30.

## 1. What the slice proves

An advanced queue operation removes only its owned temporary directory after its writer finishes. If cleanup fails, the user sees the remaining directory and original operation outcome. A successfully published file stays Completed, including in recovery, and the batch stops instead of silently accumulating leftovers.

## 2. The walkthrough

1. Encode generated video through the queue and verify output and staging removal.
2. Inject a permanent cleanup error after successful publication. The result remains Completed with a clear cleanup warning and path; later jobs remain pending.
3. Inject cleanup failure after an encoder failure or cancellation. Preserve the original failure/cancellation and show the cleanup error. No output is claimed.
4. Read the saved recovery record and verify the same outcome/warning survives.

## 3. In scope, with build order

M1: Share the existing bounded cleanup primitive between native and advanced exports; name it for both callers. Add a test seam for batch removal, keeping production defaults fixed.
M2: Replace best-effort defer with awaited cleanup after ToolRunner settles. Carry published destination and original error independently; preserve Completed state and stop on cleanup warning.
M3: Deterministic failure/cancellation/publication and journal tests, existing bounded retry tests, regression, native successful batch and hosted check.

## 4. Out of scope

Searching or deleting stale directories from older runs, automatic recovery deletion, disk-space estimation, network-filesystem guarantees, audio cleanup changes, new persisted fields, release or merge.

## 5. Stubs and debts

No pretend cleanup success. Reuse six-attempt transient retry bound (1.55 seconds total backoff) and immediate permanent failure. Blocked filesystem calls remain outside the timing guarantee. Stale directories after a process crash still require separate recovery design.

## 6. Modules touched

Shared export cleanup in NativeExport.swift, BatchController outcome handling, focused batch tests, mechanical preset reference rename, and evidence documentation. Existing QueueView status detail renders the warning without a new status schema.

## 7. Data subset

Only the directory created by the current batch job is passed to cleanup. Existing source, final destination and unrelated siblings are never removal targets. Existing BatchStatus detail retains the warning in version 4 recovery without adding fields.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S9-001 | Successful ordinary batch leaves no owned staging and preserves source and prior unrelated files | Generated actual encode plus native smoke | batch-cleanup-success |
| S9-002 | Cleanup failure after publication retains a readable Completed output and warning, stops later jobs, and persists the outcome | Injected removal failure with real encode and journal restoration | batch-cleanup-published |
| S9-003 | Cleanup failure after encoder failure or cancellation preserves primary outcome and reports retained path; no output exists | Deterministic process fixtures and removal injection | batch-cleanup-failed |
| S9-004 | Cleanup is bounded and settles despite cancelled task; only owned directory is removed | Shared existing retry tests and targeted regression | batch-cleanup-lifecycle |

## 9. Verification evidence required

Focused deterministic error injection around real generated media, source/output bytes, owned/unrelated paths, later-job status, valid journal round trip, existing cleanup retry/cancel tests, full regression, optimized build, native successful batch and hosted status. Native fault injection is not claimed.

## 10. Guardrails

Never downgrade already-published media to Failed because of cleanup. Never report Cancelled as Completed if publication did not happen. Never resume the queue after a cleanup warning in the same run. Do not automatically remove leftovers from other operations. The owner parked audio listening and this slice does not reopen it.

## 11. Definition of done

S9-001 through S9-004 have bounded local evidence, native normal-path evidence and hosted result. Remaining filesystem/platform and forced-crash recovery limits are recorded. No production-complete claim.

## 12. What this unlocks

Future explicit stale-staging inspection can present accurate historical warnings without conflating cleanup with media success.

Approved for build by: Owner autonomous non-audio delegation on 2026-09-29, reaffirmed 2026-09-30; activated under D-022 after Slice 008 closure.
