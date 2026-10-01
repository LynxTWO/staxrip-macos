# StaxRip Mac Slice 041: Keep active video exports awake
Version: 0.1. Date: 2026-10-01. Status: Approved for build under D-079 / R-051.

SLICE STATE
Milestone: M1 passed; M2 bounded implementation approved.
Blocked by: None within approved discovery.
Evidence so far: EXPORT-SLEEP-EVIDENCE.md records two real Foundation assertions, independent overlap and removal after both matching end calls. No product implementation or acceptance yet.
Last audit: 2026-10-01.

## 1. What the slice proves

A user can leave an advanced video queue or Quick Export running without ordinary idle system sleep interrupting that work. The temporary request ends only after work, publication and cleanup settle, on completion, failure or cancellation. This is a missing export-lifetime capability, not an audio or throughput repair.

## 2. The walkthrough

Start a generated silent queue export. See that automatic system sleep is prevented during processing. Observe the app-owned OS assertion while the job runs. Cancel and wait for settled cleanup; the assertion disappears and originals remain unchanged. Complete a second small export. Quick Export receives the same lifetime behavior. Display sleep, screen lock, manual sleep, lid closure and permanent system preferences are outside this control.

## 3. In scope, with build order

M1: A five-minute Foundation experiment confirms that idleSystemSleepDisabled alone creates a named PreventUserIdleSystemSleep assertion, overlapping tokens remain independent, and ending each removes its request. No forced system sleep or global setting changes.

M2: A small shared activity factory plus a lexical deferred end in BatchController's accepted run and NativeExportService's accepted call. Inject the factory for lifecycle observations. Retain existing task priority, deadline, cancellation, publication and cleanup semantics. Visible active-state guidance explains temporary automatic-sleep prevention.

M3: Extend existing actual export/cleanup tests with activity lifetime checks; add one small two-job success/no-start test where necessary. Inspect an actual native app assertion during generated work and its removal after cancellation/completion. Run ordinary local/hosted regression, optimized build and planning audit.

## 4. Out of scope

Audio Lab and DSP/listening, source preview/import/preflight activities, permanent sleep/lock changes, display wakefulness, lid/manual-sleep overrides, power-source policies, new settings/schema/dependencies, QoS or scheduling changes, any timing relaxation, automatic resume, merge and release.

## 5. Stubs and debts

No stub. An OS idle-sleep request does not guarantee execution through battery exhaustion, explicit sleep, logout, shutdown or arbitrary filesystem waits. Existing broader process/cancellation limits remain.

## 6. Modules touched

Shared ExportActivity helper; BatchController.start; NativeExportService.export; QueueView and the existing Quick Export view active-state explanation. Tests reuse actual generated native and queue exports and existing cleanup hooks. No new export engine or monitoring service.

## 7. Data subset

Only process-local Foundation activity tokens and a constant human-readable reason. No user media paths in activity names, saved fields, preferences or credentials. Each activity has exactly one matching end owned by its lexical asynchronous operation.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S41-001 | The specific OS request prevents idle system sleep and has independent overlap lifetime | M1 actual named OS assertion appears/remains/disappears; exclude display/system-setting APIs | export-sleep-system |
| S41-002 | Advanced queue owns one activity through accepted work and settled publication/cleanup | Actual two-job success and existing failure/cancellation/cleanup-warning checks; no activity for empty, unavailable, completed-only or recovery-rejected starts | export-sleep-queue |
| S41-003 | Native export releases exactly once on success, refusal, failure and cancellation | Existing actual native exports and cleanup hooks observe activity while active and zero after return | export-sleep-native-service |
| S41-004 | Native behavior and explanation match the active lifetime | Generated native queue start/cancel/completion plus PID/reason-specific pmset inspection; safe original and prior-journal protection | export-sleep-ui |
| S41-005 | Existing behavior remains qualified | Ordinary local/hosted regression, optimized build, selected audit and unchanged timing/scheduling guards | export-sleep-regression |

## 9. Verification evidence required

R-051 authorizes a bounded local OS-assertion experiment and lifecycle observations inside real existing export seams. Use a named per-process reason so unrelated caffeinate or system assertions do not become evidence. A fake factory proves balanced controller ownership only; actual Foundation and native pmset observations prove the OS request separately. Preserve original no-publication, output/source protection and cleanup checks. No actual sleep/lock test that interrupts owner work. Native fixture is silent, private and generated, with bounded duration; normal quit precedes journal restoration.

## 10. Guardrails

Use only idleSystemSleepDisabled; do not add latency/QoS, display, termination, security or preference flags. Never end at cancel-request time while owned work remains. Rejected/no-op queue starts must not leak a token. One matching end per begin; no global boolean that loses overlap ownership. If the historical hosted mastering cancellation failure recurs, reopen qualification without another blind retry or diagnostic expansion.

## 11. Definition of done

All five gates have scoped evidence and owner state is restored. Document the supported automatic-sleep boundary; no always-awake, cancellation repair, audio, platform-wide or production-completion claim.

## 12. What this unlocks

Long video work has explicit temporary energy-policy ownership. Broader crash recovery and platform/media qualification remain later boundaries.

Approved for build by: Owner standing autonomous non-audio completion delegation, 2026-10-01; D-079 / R-051. Delegated to AI recommendation.
