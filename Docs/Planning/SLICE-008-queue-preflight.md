# StaxRip Mac Slice 008: Queue preflight
Version: 0.1. Date: 2026-09-30. Status: Done with evidence.

SLICE STATE
Milestone: M1 and M2 implemented; M3 automated, native and hosted checks passed.
Blocked by: None. Slice 007 native and hosted checks passed.
Evidence so far: QUEUE-PREFLIGHT-EVIDENCE.md records four focused checks, a 107-test release regression and the native correction/recheck with unchanged source/recovery bytes.
Hosted: run 36709148929 passed at 852306f in 8 minutes 20 seconds.
Last audit: 2026-09-30.

## 1. What the slice proves

A user can check the queued jobs before starting an overnight encode, see missing sources, output conflicts and unsupported settings together, correct an item and check again. The check reads files and tool metadata but never encodes, creates staging, changes queue status, overwrites recovery or publishes output. D-021 records the delegated scope.

## 2. The walkthrough

1. Queue two generated sources with one deliberately invalid configuration.
2. Choose Check queue. Each item shows a preliminary result; the overall result lists counts.
3. Correct the item using the existing editor. Results are invalidated rather than showing a stale success.
4. Check again, then choose Start queue explicitly. Execution still performs its own authoritative checks.
5. Cancel a running check or open a queue with a missing source. The check stops or reports a repairable issue without losing queued settings.

## 3. In scope, with build order

| Milestone | Scope |
| --- | --- |
| M1 | Read-only typed preflight service; at most 1000 jobs; existing configuration/plan validation; source and destination inspection; conservative duplicate destination detection |
| M2 | Observable controller state, cancellation and stale-result protection; native Check queue and per-item results; existing app quit guard covers active checks |
| M3 | Generated valid/invalid queue cases, no-write evidence, stale/cancel/timeout tests, native correction walkthrough and hosted regression |

## 4. Out of scope

Automatic queue start, scheduling, resource estimation, guaranteed disk capacity, full HDR frame audit, hardware capability certification, new audio processing, filesystem write probes, new saved-session fields, recovery migration, merge and release. Review results are an explicitly time-limited observation, not an execution permit or promise of successful output.

## 5. Stubs and debts

No fake Ready for checks that did not execute. HDR performs only preliminary metadata/settings/tool checks and reports that the full audit is still required at execution. Hardware configurations report that runtime encoder availability remains unverified. Completed queue entries are reported as already completed and are not probed or selected to execute. No preflight result is persisted.

## 6. Modules touched

New QueuePreflight service and result model; BatchController review lifecycle; QueueView review controls/results; StaxRipMacApp quit guard. Reuse MediaProbe, EncodePlan, SessionDocument, HDR10Audit preliminary validators and ToolRunner cancellation. Execution and publication invariants remain unchanged.

## 7. Data subset

An in-memory snapshot of current jobs, completed IDs and discovered tools/encoders, bounded per-item messages and check time. No settings mutation or schema change. Canonical destination collisions, including conservative case-folded collisions, are reported for correction. Reject existing destination entries including dangling links, invalid/missing parent folders, unreadable/nonregular sources and invalid configuration. Do not create a directory or file to test writability. Actual execution retains exclusive publication and independent validation.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S8-001 | A mixed queue reports all preliminary issues and valid items without encoding or filesystem writes | Generated source/destination snapshots, malformed settings, duplicate paths, missing files and links | queue-review |
| S8-002 | HDR/hardware/completed items have truthful limited-check states | Typed result assertions with named deferred checks | queue-review-scope |
| S8-003 | Cancelling or changing queued intent prevents late results from being accepted; each probe has a 15-second limit | Controller state tests and cancellable slow probe fixture | queue-review-lifecycle |
| S8-004 | User can check, inspect an issue, correct it and recheck with clear keyboard/accessibility status | Native generated queue walkthrough | queue-review-ui |

## 9. Verification evidence required

Focused generated-media tests with before/after directory and source checks, explicit no encoder invocation, lifecycle/error cases, regression, native check/correction and hosted status. No performance campaign, real user media or new audio acceptance. Existing audio regression is not new listening evidence.

## 10. Guardrails

The check must not alter processing statuses or recovery state, create staging/output, invoke encoding, or start work automatically. Keep prior review clearly invalidated when intent changes. Avoid claiming a read-only check proves destination free space, hard-link support, hardware availability or full HDR validity. Keep path details local to the app; public receipts use generated data only.

## 11. Definition of done

S8-001 through S8-004 have local evidence; hosted status is recorded; decisions and architecture are current. Owner spoken VoiceOver and broader platform checks remain separate. This does not close the production ledger.

## 12. What this unlocks

Later disk-space/resource planning and explicit scheduling can consume the same review model. Remux, motion preview and per-track recipes remain separate choices.

Approved for build by: Owner autonomous non-audio delegation on 2026-09-29, reaffirmed 2026-09-30. D-021 records the scope chosen under that delegation.
