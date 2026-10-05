# Native decoder descriptor settlement — D132

The unused DEVELOPMENT decoder owner now checks actual close outcomes for its fixed
parent-side source, executable, three libraries, stdout/stderr read/write ends and
null stdin. It changes no parser, metadata/sample/source association semantics,
archive schema, app action or default packaging.

## Concrete ownership change

Source fact, verified from the previous D124/D130 code: pin deinitializers, pipe
methods and null-stdin defer requested close while discarding its status. Their
return did not establish successful descriptor release. D132 uses one private fixed-
role table per synchronous decoder invocation. Only these ten enum roles can be
registered by the concrete pin/pipe/null constructors; no caller-selected resource,
generic lease or receipt API was introduced. Constructor validation failures and
prelaunch refusal use the same settlement.

Each role leaves the owned table before `Darwin.close`. Pipe-end aliases are consumed
before that call too. Actual status is checked, with no retry of an uncertain number.
Closed roles cannot be closed again by final settlement; pin/pipe destructors no
longer make hidden extra close calls. Remaining roles close in reverse fixed order
on the same worker after the process body returns its result. Normal source/tool/
library identity and content rechecks still precede their close. Parent pin/null
closes follow an actual direct-child join on ordinary launched work; pipe ends can
close earlier as EOF/write ownership permits.

Close uncertainty is accumulated instead of thrown in the middle of abort. Existing
process-group signalling, EOF, direct-child reaping and refusal rules therefore finish
first. Actual close refusal then supersedes ordinary success, cancellation or error
with shared typed `OwnershipFailure("descriptor-close")`; stronger existing unsettled
process/group errors retain their reason. In either case callers have no stage cleanup
or access-release authority from an ordinary result. Consumed uncertain numbers do
not establish that a failed close physically released the descriptor. No attempt is
made to probe or close a possibly reused number after return.

DEBUG callbacks report the real role/number/status and optionally add a controlled
reported refusal after the actual call. They cannot mask a nonzero OS result. This is
a finite generated specification hook, not an OS-fault claim or production close
provider. Physical close/I/O/parser/wait cannot be preempted; universal descendant,
hostile same-user, immutable-source or recovered-ownership guarantees do not follow.
Fatal coordinator loss remains a separate qualification, not Swift cleanup evidence.

## Executed checks

Initial unchanged metadata/sample focus15tests/4suites3.998s passed. Expanded focus
19tests/4suites4.814s passed without warnings. Both metadata and sample C surrogates
qualify one ordinary complete run and ten reported refusals, one for each actual
close role. Every role's real close returned zero exactly once in these generated
cases; direct children joined/ECHILD. Constructor validation/prelaunch refusal checks
empty source, changed executable/library hash and missing source with their exact
owned-role subsets and no helper launch. Active/late cancellation, deadline, malformed
and nonzero output still join first; reported close refusal prevents an ordinary result.
Existing stronger group-1-joined-true refusal is preserved if observed. Files receiving
typed refusal are retained privately even when the report was deliberately injected.
There is no claim of a spontaneous OS close error, no post-return FD-number absence
probe and no arbitrary FD/PID corruption or signal.

Compatible composed focus20tests/5suites13.724s passed without warnings. The actual
captured D130 compatible probe/library runtime performs ten generated source/sample
trials across1/four threads and SimpleBlock/BlockGroup/VINT/codec-conformance/open-GOP
cases. Each normal helper closes all ten roles successfully exactly once, after strict
sample/source coverage and before the enclosing source/spool result. Three additional
actual helpers inject reported stdout-write/null/source close refusal and prevent a
source/sample receipt despite complete-looking inner coverage. The existing source/
spool substitution and active/late cancellation cases remain: eighteen total actual
sample helper direct joins; live repeated2000cluster cancellation settled ordinarily.
Controlled and actual typed uncertainty retain the generated root. Original source/
prior/tool/library contents remain unchanged. No complete owner film source was read.

The prior93-source statically linked hardened native host also passed13.723s with its
seven joined companion helpers and ordinary cancellation. It compiles the changed
native owner but executes prior preservation/review, not decoder/sample loading.
Metadata/sample parsing and original sample-source/edited proof limits stay unchanged.
The static host is not positive DeveloperID or SwiftUI/distribution qualification.

Ordinary500reported tests/100suites209.796s failed one existing decoder-surrogate
positive-child/join assertion, with32unchanged opt-in skips and no new warnings. New
close-settlement tests passed. The complete failure log is retained without retry;
no prelaunch/timing/phase cause or harmlessness is inferred. Explicit production build
passed without warnings; current strict ad-hoc app/read-only helper signatures pass,
minimum macOS14.0/11.0. Writer/decoder/sample remain absent from the default bundle.
Six-file privacy scan has zero private owner path/name matches and a positive sentinel;
owner source metadata/current journal, original sample/prefix/frozen/runtime objects
remain unchanged. Planning audit findings are empty. Known crashing dynamic module
is disabled; actual private sample trials remain explicitly opt-in.

PR106 automatic37245077790 failed496reported tests1052.187s/125issues:57unchanged60s,
53unchanged120s deadlines and15other assertions. Sample and source spool suites passed;
metadata decoder surrogates recorded four absent-positive-child PID assertions. Full
log and prior PR update are retained without rerun, new historical observer, relaxed
assertion/deadline or global scheduling/concurrency change. D090 timing/phase/motion/
prelaunch causes remain unknown. A current local pass does not resolve hosted failures.

## Remaining gates

D131 original source/sample association remains source-dependent agreement with the
fixed decoder, not independently remeasured sample values, luminance/rendering, EL,
container/user crop/resize or valid Dolby metadata conversion. All edited flags stay
false. Actual source/spool security-scope/pin/activity ownership for samples must still
be integrated with D128 concrete retained review; no app-facing analysis follows here.
Positive DeveloperID/hardened loading/signing, release capability/packaging, actual
sandbox grants/revocation, production recovery release, volume/blocked-I/O/power,
stable importer/binding and rendered/edit qualification remain separate. Typed
uncertainty is not settled by idle-sleep activity expiry or child join alone.

No owner media body, queue/full-film archive/encode/listening, merge/release, signing
retry, library-validation bypass or broader entitlement. Original owner metadata/
current journal, original sample/prefix/frozen objects and D130 runtime remain protected.
No UI walkthrough claim: product action and default bundle remain unchanged.
