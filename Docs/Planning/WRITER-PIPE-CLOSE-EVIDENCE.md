# D157: Checked native writer pipe settlement

This is a finite M1 original-preservation prerequisite, consumed by the existing
CompanionArchiveOperation.execute → OriginalCompanionTransaction.execute → native
writer → full original semantic verifier → exclusive result-set publication chain.
That chain does not consume the unused SPS/VCL source-only entries. The native
choice/controller/result consumer and trusted non-DEBUG helper capability remain open.

## Ownership correction

The existing synchronous POSIX writer owner now checks six actual post-spawn pipe-end
closes. Each concrete field is consumed before the single close syscall and never retried.
Initial child-side copies, authorization stdin and stdout/stderr EOF or cancellation
retirement use the same fields. Every still-owned end is attempted despite an earlier
refusal. Close refusal is collected until required body/child/group settlement finishes;
it does not throw early and skip process settlement. Shared typed uncertainty prevents an
ordinary receipt and preserves the original operation cause. Existing process uncertainty
keeps stronger outer priority; source settlement keeps its D105 priority.

Consumed fields prevent fallback retry; they do not prove OS release if close failed.
Writer pin retirement, pre-spawn pipe construction/fcntl/rollback/deinit, other metadata/
disk/stage fallback resources and standalone direct-caller access remain separate gates.
No new owning worker, generic lease, runtime Python bridge, protocol, UI/action, packaging,
release or recovery/cleanup authority is introduced.

## Actual generated qualification

Five new tests exercise 35 new direct helper joins. Sixteen both-mode writer trials cover
normal/each individual/all six reported roles, actual fixed handshake and original bytes.
Three first-close/active/late cancellation trials and four final source/stage/executable
identity/nonzero trials retain original causes and attempt six real closes once. Prelaunch
bad-digest refusal observes no helper or post-spawn close event; it does not qualify
constructor rollback.

Two both-mode normal preservation trials join the actual writer and full original native
semantic verifier before exclusive publication, check all six writer roles before verifier
launch and both outer closes before reverse scope/activity release. Existing published bytes
survive a collision. Eight actual both-mode access refusal trials prevent verifier/publication,
retain the same concrete stage/access after dropped error and completed Task, serviced
main-queue energy expiry and conflicting preservation/review calls. Stronger source-close
refusal preserves the writer cause. Active cancellation observes a current-PID OS idle-sleep
assertion and a live non-zombie writer before cancellation, then direct join. Source/prior
bytes and uncertain generated stages remain intact; no automatic discard occurs.

Controlled refusal reports follow actual successful close status, not spontaneous OS
faults. Fake scope balancing is not sandbox grant/revocation evidence. The test-only 50ms
expiry is not production 120s settlement. DEBUG registry isolation after joined generated
work has no production recovery/cleanup authority. ARC disappearance is lifetime evidence,
not stage fallback OS-close proof or universal escaped-descendant/group assurance.

The initial new archive focus passed normal publication but failed eight new ARC assertions:
the completed Task retained its error after registry isolation. Dropping that Task before
the assertion corrected test ownership without product change or assertion relaxation.
Failed log/roots remain private. Final focus: 55 tests/5 suites/16.863s passed, no warnings.
Static exact 94-source hardened host compiles this change but executes prior companion
preservation/review, not decoder/sample/crop/SPS/VCL loading.

## Limits and retained failures

Parent PR131 hosted run37317128527 at exact D156 head failed 618 tests/645.297s with nine
issues: four decoder-surrogate absent-positive-child assertions, Fresh-analysis cancellation
5.755293s versus <5, two unchanged 120s bounds, and Rendering/Measuring-candidate EOF
expectations. No 60s/180s or crop-close failures in that run. Source-prefix108.768s,
access307.507s/static290.007s and exact fixture preparation45s passed; preview skipped.
Full log retained/parent updated without rerun or per-issue attribution. Local passes do
not resolve hosted failures. D136 duplicate-compilation correction is not proof of a
common timing cause or absence of logic defects. No deadlines/assertions/skips/historical
observers/global scheduling/concurrency workaround changed.

M1–M5 remain open. This resource correction does not qualify native original-preservation
UI, dynamic-HDR conversion, edited metadata/pixels, enhancement reconstruction or production
acceptance. Full conformance/active selection/origin/value/rendered/edited facts stay as
previously qualified. No owner media body, captured runtime rebuild/copy, signing/loading
retry, original/frozen/D130/D142/D143 mutation, C/sanitizer/APFS/pixel-oracle or UI execution.

Final aggregate/build/privacy checks are recorded below once complete.

Final ordinary623 reported tests/105 suites/244.877s PASSED40 unchanged explicit opt-in
skips/no emitted warnings. Access49.769s/writer21.929s/
source-prefix23.067s/static50.745s passed. No ordinary retry.

Explicit optimized build23.70s compiler-reported/no warnings and CURRENT strict ad-hoc
app/read-only helper signatures/minima14.0/11.0 pass. Writer/decoder/sample/crop absent.
Six-file privacy zero/positive sentinel/protected owner metadata-current journal-original
sample-prefix-frozen-D130/D142/D143 unchanged; planning findings empty. No new C/runtime
build-copy/sanitizer/pixel oracle/APFS/DeveloperID/owner body/full-source/UI qualification.
