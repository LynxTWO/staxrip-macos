# Hosted qualification reframe
Version: 0.1. Date: 2026-10-03. Status: existing recurrence stop reached; proposed focused investigation only.

Need: cancelling owned media work must settle promptly, preserve source/existing output and avoid publishing an unfinished candidate; generated preservation checks must complete at their existing bound.
Authority: owner's autonomous program-completion request excluding listening, R-004 cancellation/publication protection, D-077's recorded recurrence rule, and Slice 047's D-087 unchanged matrix bound.
Worst case: users wait on cancelled work or receive a premature settlement claim; weakening preservation checks hides incomplete verification. Consequence class: user_data for production cancellation/export, local_only for generated qualification files.

## Observed failure and retained successes

- Original mastering cancellation had failed hosted runs 36895508537 and 36897429716 at 6.796 and 6.248 seconds against five seconds. The single bounded D-077 trace at 36899766961 passed: cancellation/task exit/result observation were prompt. It did not reproduce or explain the original delay. The observer was removed and ordinary 36901339753 passed. The record explicitly stops further diagnostic expansion after a recurrence.
- AV1 initial hosted run 37111085056 passed its eight-case matrix in 95.723 seconds but failed an unrelated shell-start-dependent inspector state check. D-086 replaced that state-only scheduling dependency with explicit completions while retaining actual process coverage.
- Hosted repair 37111867733 passed inspector cases but exceeded the AV1 unchanged two-minute bound, 126.646 seconds. D-087 moved independent test/reference work off MainActor without changing cases/assertions/default parallelism/deadlines.
- At 356337b, local 291 tests/72 suites passed in 205.284 seconds; native reviewed AV1 output was independently verified; hosted 37113569693 passed 291 in 560.623 seconds, matrix 111.546 seconds. This passing receipt remains scoped to its source/head.
- Last-window product repair c435e6dd470ee27f37776bf06b6afbbf523678ee passed native four-destination close/reopen and normal Quit, and 291 local tests in 205.218 seconds. Hosted [37115174217](https://github.com/LynxTWO/staxrip-macos/actions/runs/37115174217) failed in 608.097 seconds with two issues: Fresh analysis cancellation 5.450137972831726 seconds versus five; AV1 matrix 135.628 seconds after its two-minute time limit. The fallback build was skipped. No DSP, mastering/copy executor, fixture/assertion/deadline or suite scheduling changed in this repair.

AV1 and last-window hosted qualification are reopened. Do not classify the cancellation as fixed or dismiss it as runner load. Native/local success does not erase the failures. No further ordinary rerun, new observer or inflated guard has been executed after this recurrence.

## Existing control and missing evidence

The boring option is the current real generated-media cancellation test, source/prior-output hashes, process/pipeline settlement and ordinary Swift Testing workflow. Keep them. Existing DEBUG ToolRunner boundaries are available but are not active in this ordinary failed run. The log distinguishes the request notification from the final elapsed assertion only incompletely; it does not identify cancel-handler entry, source-reader/process launch, child exit, pipe drain or result-observation delay. MainActor contention, shared worker backlog, child behavior and test observation remain hypotheses. The matrix failure similarly lacks per-case phase timing.

Source inspection finds dedicated process-control/pipe queues and owned source-fingerprint work; no proven production fault yet supports a patch. Serializing the whole suite, reducing exports/frames, skipping mastering, enlarging deadlines or blind reruns are rejected.

## Concrete proposed next action

With owner decision, perform one bounded investigation of these existing lifecycle boundaries, using generated media and existing DEBUG/process hooks. Maximum 32 in-memory generic phase/time records per affected case; no paths/payloads, audio DSP/listening, credentials, dependency or product scheduling changes. No suite-wide serialization, fixture reduction or deadline change. Run the affected generated cases with the ordinary regression workload once, retain exit/count/skips and full redacted result, with a 20-minute watch cap. The purpose is to distinguish where requested cancellation and preservation-test execution wait, not obtain another green run. If evidence still cannot locate a repair, stop and reframe rather than extend observation. A proven fault would receive a separate focused repair and regression case; any contract change remains an explicit owner decision.

Owner question: approve this single bounded lifecycle investigation while keeping all current assertions and timing requirements?

Independent read-only container configuration work may finish its focused/native/build receipts; its ordinary qualification and original-signal admission remain pending. No merge or release.
