# Native staging transient close evidence

D137 qualifies the existing D099 verifier's temporary member descriptors, directory
streams and descriptor rollback after refused stream admission. It does not qualify
long-lived parent/stage pins, create rollback or deinit. This finite slice preserves
ordinary collision retry and avoids prematurely changing those lifetime contracts.
No archive action, release tool, recovery-release, schema or packaging change follows.

## Concrete ownership and actual publication

Every opened member enters the concrete verification list before type/length admission.
After the synchronous body settles, every owned member number is consumed before one
actual close attempt. Close uncertainty accumulates; a close refusal cannot skip other
owned members. fdopendir success transfers its fresh descriptor to the stream; exactly
one checked closedir precedes return/throw. Failed/refused stream admission checks the
actual descriptor rollback close. No retry of uncertain numbers/pointers and no
post-return descriptor-number absence proof. Physical I/O and filesystem calls cannot
be preempted. A failed close does not prove that its descriptor was released.

Directory-stream uncertainty in discard refuses before the first unlink and blocks
further stage use. Ordinary pre-commit refusal remains retryable only when transient
ownership settles. Cancellation and semantic/identity refusal remain operation causes
when checked closes also refuse. Shared uncertainty takes review priority over ordinary
success/refusal/cancellation. CleanupFailure now carries the shared marker as well.

The exclusive rename captures actual Published state before callbacks/member close
settlement. A later checked-close refusal carries that actual directory/verified bytes/
member count. The worker keeps committed state; it never resets available after commit.
A pre-commit ownership refusal moves to review and prevents discard/republication.
D105 learns committed state from the typed staging error even when publish cannot
return ordinary success; combined source-close refusal preserves both causes/result.
D134 retains the actual locator and needed source/parent grants in the existing
exclusion registry after dropped errors. Energy expiry is not access release,
settlement or cleanup authority. In-memory actual state is not persisted recovery,
producer provenance, import/adoption or permission to delete a candidate.

DEBUG close reports follow actual successful close and are controlled refusals, not
spontaneous OS faults. Refused stream-admission tests exercise real opened-descriptor
rollback, not an observed OS fdopendir failure. Fake scopes do not establish actual
sandbox grants/revocation. Controlled registry isolation after fixed child joins and
known successful transient closes is not a production recovery-release/group guarantee.
Generated uncertain fixtures remain retained privately; they are not adopted/deleted.

## Scope and remaining owners

Parent/stage descriptor actual close results in ResultSetStaging.create/deinit remain
unqualified. Next finite ownership work must establish ownership before creation
rollback, explicitly consume/check terminal pins, and retain actual Published state
through any after-rename refusal. Deinit alone cannot establish checked settlement.
Writer/metadata/disk helper pin/pipe/directory-stream closes are separate obligations;
this verifier correction does not qualify those owners or all archive resources.

D109-D114 full original source-dependent semantic verification remains mandatory.
Version zero is not portable/stable import, immutable/persisted execution provenance
or an independent libdovi decoder. D127/D131 source/sample agreement does not verify
sample values independently or prove rendering/PQ/EL/every field/crop/resize/edit HDR
conversion. Positive DeveloperID/hardened distribution, sandbox/recovery/import binding,
blocked-I/O/volume/power and edited-picture gates remain open. No whole-program completion.

## Executed checks

Initial changed product focus passed12tests/1suite0.040s. The new transient-role focus
passed16tests/1suite0.058s. Composed67tests/3suites11.099s passed; final68tests/3suites
11.265s passed after adding shared cleanup marker and actual joined-writer/cleanup
stream case. No emitted warnings or fixture compile failures. Five new opaque-stage
tests exercise normal closes, member/stream/admission rollback controlled refusal,
malformed member and active cancellation with cause retention. Every requested normal
member closes once; all-member closure continues after one reported refusal.

Three new concrete-operation tests execute eleven fixed helper direct joins: four
actual native writer/full original verifier trials across both modes (eight joins),
combined source/staging post-commit refusal (two), and ordinary verifier admission
refusal after joined writer followed by cleanup stream uncertainty (one). Both modes
preserve original source/prior/stage/published bytes. Late cancellation after acknowledged
rename plus member refusal retains actual Published; no ordinary success or pre-commit
discard. Dropped errors keep grants/exclusion through bounded energy expiry. Actual
normal and rollback close results are distinguished from controlled reported faults.
Ordinary final regression and explicit optimized/signature results are recorded below.
Static93-source host still executes prior companion pipeline, not decoder/sample loading.

PR111 automatic37255801350 exact shared preparation passed27s; new fixture suite passed
38.802s. Full517tests466.200s failed33issues:21declared120s/seven180s bounds plus three
absent-positive-child and two mastering phase EOF assertions. Full log retained/PR111
updated without retry; preview skipped. New fixture ownership passed, while residual
individual timing/phase/prelaunch causes remain unestablished. No deadline/assertion/
skip/global concurrency/scheduling workaround or historical timing observer is added.


D137 final ordinary regression:525reported tests/101suites220.356s passed with33unchanged
explicit opt-in skips/no emitted warnings. Final composed68tests/3suites11.265s passed
without warnings. Existing cancellation/collision/identity/hash/member membership tests
remain strict. No new fixture compile failure, assertion/deadline/global concurrency
change or historical observer. New generated reported-uncertainty roots retained;
no group/OS-fault/production cleanup authority follows those controlled tests.

Explicit STAXRIP_CONFIGURATION=release production build and current strict ad-hoc
app/read-only helper signatures passed without warnings, minima14.0/11.0; writer/
decoder/sample absent. Static93-source host ordinary execution compiles changed code
and runs its prior native companion pipeline, not decoder/sample loading. No new
product file or UI/controller/session action; no UI walkthrough claimed. Separate
C sample/sanitizer/APFS/frozen/owner-source receipts reused, not new executions.
