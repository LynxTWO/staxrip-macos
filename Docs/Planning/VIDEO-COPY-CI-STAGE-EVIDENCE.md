# D161: Locate the two video-copy timeout stages

M5 consumes concrete reached-stage records before a behavior repair. PR135 leaves only
AV1/TenBit120s timeout cases without operation context. The shared chapter-metadata write
on a utility queue is a source dependency candidate, not an observed stalled operation.

## Changed discriminator

ChapterPlan has a finite DEBUG event callback captured from TaskLocal before the existing
utility queue closure. Body entry/no metadata/submission/worker entry/write API return or
refusal/successful caller resumption are distinct. The same guard, cancellation checks,
exclusive write, queue, continuation success/error and thrown error remain. Production
code issues no new logs; selected tests supply the fixed categorical observer.

The two historical generated video-copy tests print fixed stages at their original awaited
operations, with numeric fixture/batch ordinals. Only their existing batch-start calls are
wrapped with the selected TaskLocal; the same BatchController Task inherits it. No added
worker, clock, sleep, poll, timer or task; same case bodies, order, assertions,120s bounds,
10ms polling and cancellation/wait cleanup. No arbitrary path/error/status/body/command.
Locks/printing add work and do not prove timing equivalence or a scheduling root cause.

writeReturned means Foundation's write API returned, not durability or descriptor/access
settlement. bodyResumed follows successful continuation return before the final cancellation
check; it is absent after writeRefused. batchWaitEnded is the original polling wait ending,
not an awaited task/group/resource receipt. Reached stage alone is not the underlying cause.
No callback/event authorizes cleanup while actual ownership is uncertain.

## Actual qualification

One new actual generated test observes a successful exclusive write, then refusal to
replace its existing bytes, plus the no-metadata branch. It preserves the first file and
checks the distinct event sequences. No controlled/spontaneous OS close fault is involved.
Focused8tests/3suites2.969s passed. Both historical tests observe all five successful write
boundaries for their eight AV1 and four Main10 batch cases. The existing async
Thread.isMainThread warning at AV1CopyTests.swift40 was emitted; no new warning site.
Independent review was source-only, finite approval/no execution/full milestone exit proof.

## Actual hosted failure retained

PR135 exactfda620e35295f749d2222e4a1d6abf5a6fa746de run37334321502/attempt1/
job111845100293 FAILED625tests542.626s5issues: two unchanged120s AV1/TenBit bounds,
Fresh-analysis5.165524vs<5 and Rendering/Measuring phase EOF. All37 categorical decoder
records appear; all22 sample/crop calls launched/emitted callbacks and passed unchanged
assertions in this run. Earlier failed invocation causes remain unknown. Fresh receives
its phase and cancels, but duration fails; both EOFs have matchedready/candidateReturned/
receivedfalse, not hidden preparation errors. Delayed notification execution order and the
two video timeout stages remain unknown. Writer104.849s/source107.587s/access258.145s/
static242.217s/shared fixture46s passed; preview skipped. Full log retained/parent updated
without rerun. Local success does not resolve hosted failures.

## Next and limits

Correlate this changed head's actual stage/write events with each timeout before repair.
Do not infer a blocked utility write from shared source dependency or delayed log timestamps.
No more phase telemetry is needed just to establish the separate mastering notification gap.
Faithful live-work cancellation gates/timer-arm/actual-close-result repair remains pending
owner approval; this slice changes none of it. No phase-entry replacement of active work.
No CI margin/assertion/deadline/skip/global concurrency/serialization/cache workaround.
No Claude metadata pipe-holder duplication/new audio feature/listening/owner media/runtime
rebuild/signing-loading/UI/default packaging/recovery-release or full completion claim.
All M1-M5 remain open; stage findings confer no syntax/activation/origin/value/rendered-edit
or process/group/access/cleanup authority.

Final ordinary626reported tests/105suites215.871s PASSED40 unchanged opt-in skips/no emitted
warnings. Access39.569s/source-prefix20.592s/static34.969s/Recovery49.353s
pass. No ordinary retry/new compile-test failure. Focus retains one existing AV1asyncThread
warning site; no new warning site. Product96of97files unchanged; only ChapterEdits DEBUG
observer addition/control-text after conditional/whitespace/statement-separator normalization
unchanged, a source check not compiler/timing equivalence. OriginalMastering bytes unchanged.
Static exact94-source host compiles changed file but executes prior companion preservation/
review, not the new video-case context/decoder/sample/crop/SPS/VCL loading. Seven-file privacy
zero/positive sentinel/protected owner metadata-journal-original-frozen-D130/D142/D143
unchanged; planning audit empty. No owner body/runtime build-copy/C/sanitizer/pixel oracle/
APFS/DeveloperID/UI qualification, new default packaging/cleanup/release. Private fixed-log
record/DEBUG-indent/statement-separator regex corrections retained without test rerun or
product mutation; initial downstream parent-body edit had no file and made no remote write.

Explicit production22.75s compiler-reported and current strict ad-hoc app/read-only helper
signatures/minima14.0/11.0 pass, writer/decoder/sample/crop absent. This is a new release
compilation/ordinary bundle check, not DeveloperID/hardened loading/clean-machine/UI release
qualification or a cold/elapsed benchmark. No runtime artifact was recreated/copied.
