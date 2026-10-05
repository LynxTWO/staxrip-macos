# D160: Identify the sample/crop invocation before repair

M5 needs the caught category and admission stage for each failing sample/crop invocation.
This test-only diagnostic reuses D158's existing DEBUG boundary and finite collector.

Six historical sample bodies, five crop bodies and eleven normal/close-refusal trials now
have fixed case labels. Their reports capture the last entered stage/role, check refusal,
existing posix_spawn status, caught category, actual close outcomes and boolean launch/
settlement callback observations before the original assertions. The original bodies,
callbacks, order, timeouts, assertions, refusal injection and cleanup/retention decisions
remain. No new clock, wait, poll, task, retry, product observer or scheduling change.
The crop ledger records each actual close first, then the collector sees the same event.
Controlled refusal remains after successful real close; it is not a spontaneous OS fault.

Only fixed case/stage/role/check/reason categories and numeric syscall results are added.
No new arbitrary error/status description, path, body, command, PID or descriptor number
is printed. Existing generated-fixture retention messages remain unchanged. Product/build
files are unchanged. Added locks/printing are not timing equivalence evidence.

`settledEvent` means the existing callback was observed. Separate unchanged assertions
check direct reaping; neither is universal group/descendant or access cleanup authority.
A last stage is not every internal syscall or exact underlying cause. Fixture/tool setup
precedes capture; unexpected non-ownership errors in the close-role loop still escape
before its report. Separate prelaunch refusal tests are outside this added capture.

## Actual checks

The focused25tests/6suites5.087s passed with no warnings. All22 added invocation labels
appeared alongside15 existing D158 diagnostic records. All22 reported launch and callback
observations with the unchanged assertions passing. No new test or helper trial was
introduced: these are the existing actual generated surrogates/controlled close reports.
Independent read-only source review found no blocking issue, verified unchanged product
and original test behavior, and performed no execution or milestone exit verification.

## New hosted finding retained

Parent PR134 exact292bceb6d6caf58860ac6994e0742cffa0aa66ac run37330205810/attempt1/
job111831090036 FAILED625tests569.929s29issues:21unchanged120s/six180s bounds and two
phase EOFs. Fresh-analysis and Rendering records have matched=true, phase=ready,
terminal=candidateReturned and received=false. Both target callbacks occurred and
preparation returned a candidate without the test receiving its notification. These EOFs
did not hide preparation errors. Delayed block execution/yield result/cancel-request
ordering is not captured; no exact queue/starvation cause is established. Measuring
received its notification then cancelled. All ten historical decoder loop cases launched,
emitted callbacks and passed their assertions in this run; earlier failures remain distinct.

Writer101.789s/source-prefix104.288s/access310.660s/static293.841s/shared fixture42s
passed, preview skipped. Full log retained and parent updated without rerun. This run has
no sample/crop child/close assertion failure, so it does not identify the earlier PR133
invocations. Local success does not resolve hosted timeouts or earlier failures.

## Next and limits

Inspect this changed head's actual per-call records before a sample/crop repair. If those
cases pass, do not infer an older cause. A proposed synchronous phase-entry cancellation
would change the historical20ms schedule and qualify phase-entry rather than active-work
cancellation; it is future work, not implemented or authorized by this diagnostic unit.
Chapter-write and native publication fixture/controller source candidates still need
actual reach/terminal evidence, separately from the sample/crop and phase findings.
No deadline/assertion/skip/CI margin/cache/global scheduling or serial-CI workaround.
Do not duplicate Claude's metadata pipe-holder lane. All M1-M5 stay open; no UI, trusted
release, owner media, syntax/activation/grouping/origin/value/rendered/edit or whole-program
completion claim. Existing ownership/access retention and recovery limits remain.

Final ordinary625reported tests/105suites215.827s PASSED40 unchanged explicit opt-in skips/no
warnings. Access38.538s/source-prefix20.936s/static34.235s/Recovery48.311s pass.
Product/build97 tracked files byte-identical to D159/D158; actual D15822.29s build reused,
no new production compilation. Current strict ad-hoc app/read-only helper signatures and
minima14.0/11.0 pass; writer/decoder/sample/crop absent. Exact static94-source host runs prior
preservation/review, not decoder/sample/crop/SPS/VCL loading. Six-file privacy zero/positive
sentinel/protected owner metadata-journal-original-frozen-D130/D142/D143 unchanged; planning
audit empty. No new compile/test failure or ordinary retry/owner body/runtime rebuild/UI.
Private bounds-regex/cwd/repo lookup mistakes corrected before execution rerun or remote
mutation; actual retained logs parsed without changing tests. Source-only review, no full exit.
