# D159: Expose the task result hidden by phase EOF

M5 consumes this bounded diagnostic before behavior repair. It adds no product capability.

## Source facts and unknowns

The generated recovery task always finishes its phase stream in defer. The matched-status
callback separately schedules the existing +0.02s block that yields the existing Date,
finishes the stream and requests cancellation. A nil next fails before task.value is
awaited. It can represent task refusal before the requested status, or completion after
matching but before delayed notification. Retained logs do not choose between them.
The separate duration assertion does not establish either cause. Native invalid errors
can embed FFprobe stderr, so arbitrary error descriptions would expose source paths.

## Changed diagnostic

A test-only locked state maps existing public status callbacks to fixed categories,
records whether the requested phase has matched, and records task success or a caught
terminal category before the unchanged finish defer runs. The same error is rethrown.
Only four exact static planner/PCM messages get named subcategories. Other native messages
stay opaque. Cocoa/POSIX retain only numeric code; unknown domain/detail/code is omitted.
No error, candidate, raw status, path, body, command or clock is retained.

The caller evaluates next once, prints a fixed record, then applies the same requirement.
The final record describes test-scope exit, not process/preparation settlement. It has
received=none, since it does not observe a second notification.
matched means observed by that snapshot, not inability to run later. terminal=pending at
phaseNext is normal while cancellation is still settling. Neither record confers resource,
process/group or access release authority.

Product/build tracked files are identical to D158. Historical Date/timer/yield/finish/cancel
and task-await assertions remain, with the same three generated fixtures and serialized
suite. Diagnostic locks/printing add work but no new timing claim, clock, delay or polling.
No relaxed deadline/assertion, skip, retry, task owner or global scheduling change.

## Qualification

One synthetic classifier/state test verifies opaque payload omission, known static
reference category, numeric POSIX, unknown domain omission, cancellation and returned
categories. Synthetic errors are not spontaneous OS/process or historical task failures.
The original three generated recovery cases actually reach their requested phases and
report terminal cancelled; no missing-phase refusal is newly induced. Focus2reported tests/
1suite25.763s passed with three historical parameter cases and no warnings. No audio
listening/new audio feature is involved. Final ordinary625reported tests/105suites218.065s passes40 unchanged explicit opt-in
skips/no warnings. Recovery50.129s/access39.879s/source-prefix20.558s/static36.358s pass.

## Hosted evidence retained

PR133 run37327344142/attempt1/job111821332161 at exact
b2fe745e48c2390ccc7b0b7c939f46948e67ee6c FAILED624tests483.546s32issues:21unchanged120s
and six180s bounds; one sample child-zero/two crop role-child assertions; Fresh-analysis
and Rendering phase EOF. All15 decoder categorical records appeared. All ten historical
loop cases launched/emitted settlement callbacks and passed in this run. Earlier failed
iterations/remaining causes are not identified by those successes. Callback is not reap or
universal descendant/group proof. Full failure evidence retained/parent updated without
rerun. Source76.975s/writer68.163s/access251.426s/static234.978s/shared fixture34s passed;
preview skipped. Local checks do not resolve hosted failures.

## Next discriminator and limits

Inspect this changed head's actual hosted phaseNext/finished records before a repair.
The sample/crop role-close tests still lack their own fixed case/entered-stage/check/spawn
context and are independent next candidates on existing DEBUG decoder facilities. AV1/
TenBit timeout-stage causes also remain unknown. Do not duplicate Claude metadata pipe-holder.
No historical timing observer, CI margin/cache removal/serialization/global concurrency
workaround or arbitrary error text. Product build reuse is identity-bound, not a new build.
No UI, trusted-release, owner body, captured runtime rebuild, syntax/activation/grouping/
origin/pixel/rendered/edit or full non-audio completion claim. All five milestones stay open.

Final product/build97 tracked files are byte-identical to D158. Reuse that actual22.29s
compiler receipt; no new production build. Current strict ad-hoc app/read-only helper
signatures/minima14.0/11.0 still pass; writer/decoder/sample/crop absent. Static exact94
sources executes prior preservation/review only. Four-file privacy zero/positive sentinel,
protected owner metadata-journal-original-frozen-D130/D142/D143 unchanged, planning empty.
No new compile/test failure/ordinary retry/C/runtime build-copy/sanitizer/pixel oracle/APFS/
DeveloperID/owner body/UI qualification. Two guessed analysis file reads and an initial
private-log parser cwd failed before mutation; actual paths/cwd corrected, no execution rerun.
Independent review is source-only, no tests or full milestone exit verification.
