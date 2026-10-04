# Native source-only observation prerequisite

D-126, R-059 / Slice049. An unused internal source pass now reconstructs original
Matroska/HEVC TrackEntry/hvcC, encoded packets and escaped RPU hashes/associations
directly into D125's owned SQLite spool. It requires an explicit original source
and caller-owned empty0700 folder. No companion, manifest, retained payload or helper
supplies source facts. There is no decoder execution or frame admission in this unit.

## Source capability and ownership

D109 and D110 share their existing finite source walkers with new readSource methods.
The old read methods still require exact retained configuration/TrackEntry/raw-RPU
bytes and retain their equality flags. Source-only results explicitly keep those
flags false. Track selection, byte counts, source offset, configuration and payload
hashes, and NAL length width are independently rechecked during packet traversal.
Each packet/RPU is synchronously appended; no whole observation stream is retained.
Raw concatenation size/delimiter offsets describe potential storage positions only.
No raw-RPU companion is written or matched by the source-only pass.

CompanionDiskCheck.spoolOriginalSource pins the original no-follow regular descriptor
and pathname, hashes its complete bytes before traversal, and runs source/spool work
on one dedicated worker. Fixed component read capabilities always refuse. Source
reads are capped at1MiB, with D109/D110's unchanged framing/timing/record limits and
D125's database/page/record controls. Signed encoded order, duplicates, nullable flags,
unsigned duration and every escaped RPU remain distinct. Actual TimestampScale and
Segment mode accompany the source facts. The worker rehashes source bytes and checks
final source path/descriptor observations, source-pass counts and spool membership.

SQLite and its file/folder pins close before successful return; the source descriptor
also has a checked actual close. An uncertain close carries shared unsettled-ownership
retention, supersedes ordinary refusal/success and is never blindly retried. Awaited
ordinary errors/cancellation unwind the worker before return. Cancellation before
acquisition and after worker completion cannot become success. Physical I/O, SQLite
and parser CPU cannot be preempted by cooperative checkpoints. Limits are configured,
not measured total memory or whole-source speed guarantees.

The caller continues to own folder/access lifetime, including typed uncertain-close
retention. There is no automatic stage removal, discovery, database adoption,
publication, access/activity controller, recovery release or archive action.
Independent source-frame association and edited-picture semantics remain false.
Source identity/content observations are not immutable snapshots, persisted producer
provenance or hostile same-user protection. This finite Matroska/HEVC capability does
not add MP4/AV1, whole-container demuxing, EL reconstruction or picture conversion.

## Generated evidence and retained failures

Actual generated Rust-writer sources for both retention modes are first compared
with D110 and the independent test-only original oracle. After deleting only each
fixture's companion stage, the native source-only pass stores four packets/five RPUs/
one enhancement NAL. A test-only read-only SQLite reread matches every stored field
against the independently reconstructed packet/RPU observations and source hash.
The runtime pass never invokes the writer/oracle or reads companion files.

Generated native passes cover all four NAL length widths and both Segment size modes,
signed duplicate/nonmonotonic order, exact Int64.min/max PTS, UInt64.max duration,
nullable flags, and escaped bytes. Existing companion methods refuse missing retained
components; forged track hashes fail source-only selection. Thirty-seven source
framing/malformed cases also refuse without component capabilities; two retained-file
forgeries remain relevant only to the original component comparison APIs.

Actual read/final cancellation, pre-cancel before file creation, no-follow source
alias refusal, existing spool preservation, final source mutation, extra membership
and spool pathname substitution refuse. A repeated1000-cluster source encounters
actual SQLITE_FULL under the configured8-page limit and returns no source-pass
receipt. This is database page-cap exhaustion, not physical volume ENOSPC. No actual
OS close-denial fault or production access grant is claimed.

Initial compilation exposed a directly constructed older track fixture lacking the
new explicit equality flag; its declaration-only fixture now states false. Another
new test compile failure used the wrong parameter name; corrected locally. Two
subsequent test-only SQLite rereads refused the temporary path, including Foundation
symlink resolution. Native F_GETPATH from the test's no-follow file descriptor made
the read-only no-follow reread succeed. Runtime D125's descriptor-bound path logic
was already correct and unchanged. Failed logs remain private; no no-follow policy,
historical assertion/deadline or global concurrency change follows.

Final focused46tests/5suites13.306s passed without emitted warnings, including the
93-source statically linked hardened native host13.305s. That host compiles this
source closure and executes its existing preservation/review/cancellation pipeline;
it does not execute the new source-only spool method. Ordinary regression, explicit
optimized product/signature and protection checks are recorded below after execution.

## Remaining association gate

Compose this source capability, D125's concrete open spool and D124's owned decoder
synchronously on one owning worker. Compare fresh decoder packet/frame rows against
stored source facts, with checked coverage, exact rational tick-to-nanosecond equality,
one picture per original packet and no missing/surplus records. No full2M-row capture,
Python runtime bridge, source-selected executable or generic receipt wrapper follows.
Default Preview still excludes decoder/writer. No owner source body, queue, full-film
archive/encode, listening, known-crashing module fixture, signing retry, merge or release.


Final ordinary474tests/98suites210.730s passed with28 unchanged explicit opt-in
skips and no emitted warnings. No private frozen decoder or known-crashing module
fixture was enabled. The prior PR100 automatic468tests/1141.409s/98issues is retained
without rerun:42 unchanged60s/34 unchanged120s/3 unchanged180s deadlines and19 other
gate/decoder/motion/phase issues. Its spool46.398s/static780.200s passed. These results
remain separate; the local pass does not explain the hosted failures.

Explicit optimized build observed Building for production and completed19.74s, no
warnings. Current strict ad-hoc app/read-only helper signatures pass, deployment
minima14.0/11.0. Writer and decoder remain absent. Ten changed files pass privacy
scan with zero owner path/name/stem matches and positive sentinel. Owner source
metadata and recovery journal remain unchanged; planning hygiene has no findings.
These checks do not qualify signing provenance, native archive action or frame edits.
