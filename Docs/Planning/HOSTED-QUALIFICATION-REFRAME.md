# Hosted qualification reframe
Version: 0.2. Date: 2026-10-03. Status: D-090 investigation completed; cause remains unknown and broader hosted qualification stays open.

Need: cancelling owned media work must settle promptly, preserve source/existing output and avoid publishing an unfinished candidate; generated preservation checks must complete at their existing bound.
Authority: owner's autonomous program-completion request excluding listening, R-004 cancellation/publication protection, D-077's recorded recurrence rule, and Slice 047's D-087 unchanged matrix bound.
Worst case: users wait on cancelled work or receive a premature settlement claim; weakening preservation checks hides incomplete verification. Consequence class: user_data for production cancellation/export, local_only for generated qualification files.

## Observed failure and retained successes

- Original mastering cancellation had failed hosted runs 36895508537 and 36897429716 at 6.796 and 6.248 seconds against five seconds. The single bounded D-077 trace at 36899766961 passed: cancellation/task exit/result observation were prompt. It did not reproduce or explain the original delay. The observer was removed and ordinary 36901339753 passed. The record explicitly stops further diagnostic expansion after a recurrence.
- AV1 initial hosted run 37111085056 passed its eight-case matrix in 95.723 seconds but failed an unrelated shell-start-dependent inspector state check. D-086 replaced that state-only scheduling dependency with explicit completions while retaining actual process coverage.
- Hosted repair 37111867733 passed inspector cases but exceeded the AV1 unchanged two-minute bound, 126.646 seconds. D-087 moved independent test/reference work off MainActor without changing cases/assertions/default parallelism/deadlines.
- At 356337b, local 291 tests/72 suites passed in 205.284 seconds; native reviewed AV1 output was independently verified; hosted 37113569693 passed 291 in 560.623 seconds, matrix 111.546 seconds. This passing receipt remains scoped to its source/head.
- Last-window product repair c435e6dd470ee27f37776bf06b6afbbf523678ee passed native four-destination close/reopen and normal Quit, and 291 local tests in 205.218 seconds. Hosted [37115174217](https://github.com/LynxTWO/staxrip-macos/actions/runs/37115174217) failed in 608.097 seconds with two issues: Fresh analysis cancellation 5.450137972831726 seconds versus five; AV1 matrix 135.628 seconds after its two-minute time limit. The fallback build was skipped. No DSP, mastering/copy executor, fixture/assertion/deadline or suite scheduling changed in this repair.

AV1 and last-window hosted qualification are reopened. Do not classify the cancellation as fixed or dismiss it as runner load. Native/local success does not erase the failures. The owner subsequently approved exactly one bounded observation under D-090. Its result below does not erase this failed ordinary qualification.

## Existing control and missing evidence

The boring option is the current real generated-media cancellation test, source/prior-output hashes, process/pipeline settlement and ordinary Swift Testing workflow. Keep them. Existing DEBUG ToolRunner boundaries are available but are not active in this ordinary failed run. The log distinguishes the request notification from the final elapsed assertion only incompletely; it does not identify cancel-handler entry, source-reader/process launch, child exit, pipe drain or result-observation delay. MainActor contention, shared worker backlog, child behavior and test observation remain hypotheses. The matrix failure similarly lacks per-case phase timing.

Source inspection finds dedicated process-control/pipe queues and owned source-fingerprint work; no proven production fault yet supports a patch. Serializing the whole suite, reducing exports/frames, skipping mastering, enlarging deadlines or blind reruns are rejected.

## Concrete proposed next action

With owner decision, perform one bounded investigation of these existing lifecycle boundaries, using generated media and existing DEBUG/process hooks. Maximum 32 in-memory generic phase/time records per affected case; no paths/payloads, audio DSP/listening, credentials, dependency or product scheduling changes. No suite-wide serialization, fixture reduction or deadline change. Run the affected generated cases with the ordinary regression workload once, retain exit/count/skips and full redacted result, with a 20-minute watch cap. The purpose is to distinguish where requested cancellation and preservation-test execution wait, not obtain another green run. If evidence still cannot locate a repair, stop and reframe rather than extend observation. A proven fault would receive a separate focused repair and regression case; any contract change remains an explicit owner decision.

Owner question: approve this single bounded lifecycle investigation while keeping all current assertions and timing requirements?

Independent read-only container configuration work may finish its focused/native/build receipts; its ordinary qualification and original-signal admission remain pending. No merge or release.

## Owner approval and exact execution binding

The owner explicitly answered yes to this proposal and requested autonomous logical decisions. D-090 authorizes one hosted observation against the unchanged 291-test workload at c435e6d, with generated fixtures, all assertions/time limits/default scheduling retained. At most 32 generic monotonic records per affected case; cancellation reserves 12 slots for task/request/result markers. The existing DEBUG ToolRunner hook observes cancel-handler entry/return, child launch/exit and reader close/join, without process IDs, arguments, paths or payloads. AV1 records fixture/reference readiness and prepare/publication/independent-verification stages for all eight unchanged cases. No DSP/listening or persistent security setting changes.

Local focused compilation/trace checks precede one hosted ordinary swift test run, watched for at most 20 minutes. Source/header implementation at 889a4c0 stays on its separate local branch, so the investigation does not add those tests to the failed hosted workload. After observation, retire the temporary trace and decide from evidence; success alone is not a diagnosed repair. A result without a located cause returns to this reframe instead of an extra attempt.

Local preparation passed the actual two affected tests/three cancellation cases in 24.719 seconds; AV1 matrix 2.738 seconds. Its cancellation trace retained all task/request/result markers but omitted four routine tool events at the reserved ordinary-slot cap. Before the single hosted attempt, omit redundant tool async-entry/submission labels and bind the hook only in Fresh analysis; this retains child/reader/join events within the same 32-event cap, without changing assertions or workload. The single hosted observation is completed below.


## D-090 result and retirement

Verified observed behavior, scoped to diagnostic head `0ab9d28ba73126106001be98cc1ed2c792c9169c`: [hosted run 37126143385](https://github.com/LynxTWO/staxrip-macos/actions/runs/37126143385) exited successfully. Swift Testing reported 291 tests in 450.956 seconds; the existing 25 opt-in test declarations were skipped. All three mastering cancellation phases and all eight AV1 export cases passed without changed assertions, deadlines or suite scheduling. Preview/fallback build succeeded. The full hosted log and exact-head watch receipt are retained privately; the maximum 20-minute watch completed in 367.534 seconds.

Fresh-analysis trace recorded 28 events, none omitted. Cancellation request at 10.462034 seconds reached the existing handler at 10.462043 and returned at 10.462071. Both readers closed by 10.467487; child exit and process/pipe join completed by 10.635190; task exit was 10.781824 and result observation 10.784092. Observed request-to-result settlement was 0.322058 seconds. This locates prompt settlement in this run; it does not reproduce or explain the earlier 5.450-second violation.

AV1 trace recorded all 32 planned events, none omitted. The matrix body took 111.244890 seconds and the test reported 115.182 seconds against its unchanged 120-second limit. Prepare-to-publication intervals varied from 0.274386 to 32.851701 seconds; independent post-publication checks varied from 0.139608 to 1.482360 seconds. Longest observed intervals precede publication, but these intentionally coarse boundaries cannot attribute the time to process scheduling, execution, controller observation or source/output verification. No production fault or causal scheduling repair is established.

Confidence: **verified** for these exact-run timings and passed checks; **unknown** for the cause of earlier failures and reliable hosted completion at the unchanged bounds. Repeated green/failed contrast is not a causal diagnosis. Do not classify this as a cancellation fix, AV1 performance guarantee or ordinary uninstrumented qualification.

The temporary helper and all trace calls are retired locally. ToolRunner and both affected tests are byte-identical to `c435e6d`; only planning/evidence documents differ. No second hosted attempt or ordinary rerun is initiated by retirement. PR 66 remains a draft investigation record, not a merge candidate; its observed head is retained remotely to bind the receipt. The local retirement checkpoint is deliberately not pushed, because a PR synchronization would start an unauthorized second hosted attempt under the current workflow.

## Concrete remaining decision

The existing full-workload hosted gate remains open. The next proposal must choose a qualification environment and state what it proves before another run: retain the current shared hosted environment with an explicitly bounded new discriminating question, or use an owned Mac runner for unchanged real process/cancellation/preservation checks and keep shared-hosted timing reliability separately unqualified. Neither option silently weakens the five-second settlement or two-minute matrix requirements, nor claims that local success repairs the prior hosted failure. A new observer or rerun is outside D-090's completed single-attempt scope and requires a new owner decision.

Independent container-header results remain usable at their exact source identity; integration, ordinary qualification and original HDR admission are still pending. Listening, rendered Dock appearance, broader player/platform validation, merge and release are excluded. Owner media/recovery state remains protected.


## Automatic regression recurrence during HDR prerequisites

Automatic ordinary run [37164120623](https://github.com/LynxTWO/staxrip-macos/actions/runs/37164120623), docs-only head `140861c185ad03f6d2df3ece639e268eb112582f`, failed the AV1 matrix's unchanged 120-second limit: 146.177 seconds. All 303 tests settled in 620.802 seconds with one issue; the subsequent preview build was skipped. Product/test sources were unchanged from the preceding passing code-head run 37163446273. No original-mastering cancellation issue was reported in this run. This is an automatic implementation PR workflow, not a newly authorized D-090 investigation; keep the failure and unknown cause. Do not rerun to obtain green, expand observation or relax assertions/deadlines. The separate Rust reader run 37164120576 passed.


PR 70 native inspector code head c830d89 and documentation head c205a88 ran ordinary
hosted checks automatically. Reader docs-head run 37172237376 passed (1m32s). App
docs-head run 37172237391 failed three existing timing assertions: AV1 matrix
128.883 s and ten-bit copy matrix 128.884 s exceeded their unchanged 120 s bounds;
Fresh analysis cancellation took 5.670801 s against the unchanged 5 s assertion.
All 311 tests finished in 592.932 s with three issues; preview packaging was skipped.
New Dolby core/lifecycle suites passed (102.608 s / 30.347 s), much slower than local,
without establishing a cause for the hosted failures. Code-head run 37172171872
also failed: HDR10 cancellation 5.063968 s, Fresh analysis cancellation 5.979875 s
against 5 s; AV1 matrix 122.239 s against 120 s. All 311 tests finished in
529.350 s with three issues; new Dolby suites passed (72.077 s / 30.277 s).
Its private log is retained with this separate result. No blind retry,
new diagnostic observer, deadline/assertion change or production qualification
follows. Native local 311-test/optimized/full-source evidence remains local scope.


PR 71 head 4d1b93f ordinary app run
[37177037602](https://github.com/LynxTWO/staxrip-macos/actions/runs/37177037602)
failed two existing timing checks. AV1 copy matrix exceeded its unchanged 120 s
limit and settled in 126.740 s. Fresh analysis cancellation took 6.863703 s against
five seconds. All 311 tests finished in 444.484 s with two issues; preview packaging
was skipped. Reader run 37177037607 passed in 1m5s. Private failure log retained;
no retry, new timing observer or assertion/deadline change. D-096 local full-source
and default app regression evidence remains scoped separately from hosted acceptance.
