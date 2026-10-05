# D158: Diagnose decoder refusal before changing behavior

M5 consumes this finite diagnostic. Retained hosted failures must have a concrete cause
before repair. It does not complete a workflow or admit a new decoder capability.

## What the retained evidence establishes

PR131 at D156 head reported four identical decoder positive-child failures. PR132 at D157
head reported three. Both use one ten-case loop that discards ordinary caught error detail
and omits case labels. Those records cannot identify the failing iterations or causes.
Fixture compilation and tool construction precede the owning-call catch. The worker starts
its deadline before source/executable/library admission and hashes, pipe setup and spawn.
Generic public errors cover deadline, guards and syscall refusals. A prelaunch deadline is
possible. Filesystem, hash, descriptor and spawn refusal also fit. Existing timestamps do
not prove starvation, contention, a common cause or absence of a logic defect.

## What changed

The existing worker exposes DEBUG-only categorical admission and check-refusal callbacks.
It records the return status of the existing spawn syscall before its unchanged guard.
No new clock reads, elapsed timing, checks, polls, waits, retries or owning worker are added.
Original cancellation-first ordering, deadline construction and clock read, thrown errors,
descriptor retirement, child/group settlement and historical callbacks remain unchanged.
Stage means the operation entered, not every internal guard or syscall cause.

The ten generated surrogate cases now emit one terminal record with a fixed case label,
outcome category, enum stage/role/check refusal, numeric spawn and close status, launch
observation and settlement-event observation. It emits after the owning call returns or
throws, before the existing join assertion and any supplementary holder observation.
No paths, command text, source body or arbitrary error descriptions are added. The same
bodies, order, 10/0.25s timeouts, assertions, cleanup and scheduling remain.

Independent source review found the initial diagnostic name joined misleading. The
existing settled callback can fire before reap is verified. Only the output field was
renamed settledEvent. A notification does not prove a join. The callback, wait, guard and
assertions stay unchanged. Initial logs retain the old label as historical evidence.

## Actual local diagnostic qualification

One new test exercises five concrete generated refusals. Wrong executable hash reports
executableHash and two successful closes. Wrong library hash reports libraryHash/avformat
and four closes. Missing owned library reports libraryPin/avutil and four closes. An invalid
owned executable reaches actual spawn status8 with ten successful closes. The test requires
nonzero spawn status; code8 is this receipt's observation, not a universal contract.
A positive sub-nanosecond timeout makes the existing nanosecond delta zero and reports
options/deadline before any open. It qualifies deadline capture, not hosted timing behavior.
All five record zero launch/settlement events, no duplicate closes and unchanged source
bytes. No post-return consumed-number absence probe or spontaneous OS-close fault is used.

The original ten cases execute and emit distinct categories while keeping their join
assertions. Local silence/EOF-live/complete-live/pipe-holder cases observed deadline refusal
at process, with actual spawn status0. Successful normal output reaches complete. Nonzero
cases reach finalStream. Malformed/bounded output cases refuse at process. These passing
local observations do not identify the historical failed cases or their causes.

Initial11tests/2suites5.732s and expanded20tests/6suites15.879s passed without warnings.
Both precede the final label-only correction. The ordinary run started on final product
code with that earlier label. Final focused execution checks the corrected test label.
Static exact94-source hardened host compiles changed code but executes prior companion
preservation/review, not decoder/sample/crop/SPS/VCL loading. Private real fixed decoder
profiles remain opt-in. No known hardened copied-module loading is enabled.

## Limits and next evidence

PR132 run37322910457/attempt1/job111806230574 at exact head
e48eb642e9b89963ea039e58b22bc2143fa38e42 FAILED623tests525.378s8issues. Three absent-positive-
child decoder assertions, Fresh-analysis5.914658s versus <5, two unchanged120s AV1/TenBit
bounds, and Rendering/Measuring-candidate iterator EOF remain unexplained. No60s/180s or
crop-close issue occurred in that run. Writer73.566s/source77.917s/access225.209s/static209.139s
and exact shared fixture preparation32s passed; preview skipped. New writer checks passed.
Full log/run-attempt-job-head evidence retained and parent updated without rerun. Narrow or
local passes do not establish M1/M5 completion or resolve the hosted failures.

The next changed-head hosted run can expose exact cases and categorical refusals. It must
be inspected before any behavior fix. Missing mastering phase terminal cause, cancellation
timing and AV1/TenBit timeout-specific stages remain separate pending diagnostics. Claude's
metadata-surrogate pipe-holder lane is not duplicated. No denied patch, serialization/cache
removal, deadline/assertion/skip relaxation or global concurrency/scheduling change occurs.

Cancellation/external-check diagnostic hooks are source-traced but are not directly asserted
by the new five-case test. Matching callback PIDs, EPERM, signal success, direct-child join,
pipe EOF/close or energy expiry do not confer group cleanup/access release authority. All
previous resource/source/retention/sandbox/signing/distribution/recovery/source-frame/origin/
value/rendered/edited limits remain. No owner media body, captured artifact rebuild/copy,
C core/sanitizer/pixel-oracle/APFS/DeveloperID/UI or new release qualification.

Final product ordinary624 reported tests/105 suites219.705s PASSED40 unchanged explicit
opt-in skips/no warnings. It used the earlier test output label; the sole later test-only
label correction passed final11tests/2suites5.319s, with15 categorical records using
settledEvent. No ordinary retry; no callback/assertion/process behavior change.
Explicit optimized22.29s compiler-reported/current strict ad-hoc app/read-only helper
signatures/minima14.0/11.0 pass; writer/decoder/sample/crop absent. Static94-source host
runs prior preservation/review only. Five-file privacy zero/positive sentinel/protected
owner metadata-journal-original-frozen-D130/D142/D143 unchanged; planning empty.
Initial private build receipt regex assumed s; actual log says sec. Corrected read-only
receipt parsing without build rerun or product mutation. No new compile/test failure.
