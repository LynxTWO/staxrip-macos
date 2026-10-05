# Shared native test fixture build evidence

D136 removes repeated private Cargo compilation from the Swift fixture builders.
This changes tests and CI preparation only. Product sources, default Preview,
archive/decoder/sample protocols, packaging and release capabilities are unchanged.

## Assessment and concrete correction

The owner supplied an external resource-contention diagnosis. Read-only source
inventory confirmed 31 Cargo call literals across 15 directly building fixture files,
30 target-directory literals and additional callers of the common metadata fixture.
Those are counting units, not 28 directly building suites. The old workflow prepared
only the default-feature read-only release binary in the default Cargo target.
Fixtures separately requested development writer/reader release binaries and debug
Rust test harnesses under many private targets. Cold duplicated compilation is a
material resource-contention mechanism; it does not prove that every residual
assertion is starvation or rule out logic defects. Individual D090 failures remain
unattributed. Earlier successful-build/missing-artifact observations remain retained.

The test coordinator now uses one separate native-development-fixtures target with
one fixed development-companion-writer feature set and --locked dependencies. It
prepares both release binaries and the library/binary/matroska debug test harnesses.
Cargo JSON selects the concrete compiled harnesses. Named generators execute directly
with exact test selection; zero selected tests is refusal. A native flock covers
build preparation, generator execution and exclusive private helper copies. Each
request opens its own lock descriptor, so actor reentrancy cannot bypass exclusion.
Waiting cancellation and ordinary lock release check actual close results, consume
descriptor numbers once and never retry. The lock covers copying beyond Cargo's own
build lock. Helper hashes are captured and rechecked before/after copying.

Signing, mutation and subsequent helper execution use exclusively owned per-fixture
copies. Shared build outputs, app/default Cargo outputs and existing private target
caches are not signed, mutated or deleted. Preparation is once per coordinator in a
test process, with incremental Cargo validation against the shared target; it is not
a claim that all possible compilation is zero. The CI step prepares the exact same
release and test profiles before timed Swift tests. It neither globally serializes
suites nor changes existing deadlines, assertions, skips or job concurrency. Fixture
acquisition alone serializes the concrete shared artifact/generation/copy interval.

## Checks and limits

One explicit new cold qualification uses an initially absent owned target, without
purging existing caches. Three simultaneous staged/original/reference requests prepare
one profile pair and acquire one ownership interval at a time. Three native readers
check generated source semantics; source bytes remain unchanged. Copied helper hashes
match; private mutation leaves other copies/shared artifacts unchanged. Actual lock
waiting cancellation, exclusive-copy refusal and subsequent acquisition pass. This
checks direct-child/pipe completion through the existing test ToolRunner, not universal
escaped descendant supervision, checked closure of every subprocess resource, hostile
same-user protection or physical-I/O preemption. The cold fixture is retained privately.
No new app-runtime bridge or production ownership authority is created.

Initial focus selected the reader binary's unit harness instead of the library harness
containing the staged generator. Explicit --lib preparation and exact library artifact
selection corrected that refusal. A new missing-try compile failure is retained.
The first regression also exposed four exact fixture-root inventories omitting the new
private reader copy. They now require that named copy; stage/publication/semantic
assertions remain strict. Failed logs are retained, not rerun unchanged.

Executed final results are recorded below after settlement. Product build evidence is
reused from unchanged D135; current strict ad-hoc app/read-only helper validity is a new
check, not DeveloperID or distribution. Writer, decoder and sample probe remain absent.
No UI walkthrough, owner media read, full-source association, C/sanitizer/APFS/signing
or known-crashing dynamic-module execution occurs in this unit.

PR110 automatic37252719350 failed 515 tests in1111.249s with85issues:37declared60s,
30declared120s, one180s bound and17other assertions. Full log retained/PR updated
without retry. Changed hosted qualification is required before attributing residual
failures or claiming a CI fix. No CI-aware margin, scheduling workaround or causal
claim that every other assertion is downstream follows this correction.

After changed hosted results are inspected, D099 internal parent/stage/component/
directory-stream checked closes and actual post-rename state propagation remain the
next native prerequisite. D135 source and D134 outer closes do not qualify those roles.
Source-dependent sample binding still does not independently remeasure pixels or prove
rendering/luminance/EL/container-user crop/resize/edited conversion. Signing, sandbox,
recovery/import binding and distribution gates remain open; no whole-program completion.

## Final executed results

The owned initially empty target qualification passed2tests/1suite10.117s. It includes
three simultaneous native generator requests, one preparation pair, matched private
helper copies and native reader counts1/2,4/5,4/4packet/RPU with unchanged source.
Actual lock waiting cancellation/exclusive copy refusal/subsequent release pass.
Final inventory/lock focus52tests/5suites8.976s passes without emitted warnings.
The CI preparer separately passes against the warm fixed target (release0.10s,
test0.03s), not a second cold benchmark. Final ordinary517reported tests/101suites
210.071s passes33unchanged explicit opt-in skips/no emitted warnings. Existing actual
writer/verifier/publication/candidate/native statically linked host fixtures run through
private helper acquisition; the host still executes its prior companion pipeline,
not decoder/sample loading. No product source was added or changed.

D135 explicit production build is reused, not rerun. Current strict ad-hoc app/read-only
helper signature checks pass; writer/decoder/sample absent. Source metadata/current
journal/original sample/prefix/frozen/captured runtime unchanged. Privacy positive
sentinel/zero matches and planning findings empty after one new hygiene correction.
The initial regression517tests207.392s/4issues and new fixture compile/selection failures
remain retained. Changed-head hosted results are pending; no timing-cause or whole
program completion claim follows the local pass.
