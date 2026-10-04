# Native companion writer process evidence

Date: 2026-10-04. R-059 / Slice049 / D-107. Internal unbundled generated native process
ownership; no owner archive operation or application action.

## Contract and ownership

Ready/staged stdout alone is not completion. Actual writer/group/pipes must settle
before a trusted phase returns; cancellation/refusal cannot admit a late partial result.
Partial stage files remain owned by the caller and are not archive success. Independent
source/disk/original semantic admission and D105 exclusive publication remain distinct.
The future owner chooses retention and reviews losses/storage/privacy before execution.

CompanionWriterProcess uses one dedicated worker queue, a one-way cancellation flag and
POSIX spawn with a new group. Launch, handshake, all PID/group signals and waitpid occur
on that worker. There is no timer/monitor racing with child reaping, no shell or generic
ToolRunner modification. Native stdin/stdout/stderr are CLOEXEC pipes, parent endpoints
nonblocking; F_SETNOSIGPIPE turns a closed stdin write into refusal rather than killing
the parent. Only explicit stdio dup2 actions are inherited, with CLOEXEC_DEFAULT closing
other descriptors. Environment is fixed PATH=/usr/bin:/bin, LANG=C, LC_ALL=C; no inherited
DYLD/credentials/model controls or ambient command resolution. Exact absolute executable
is passed to posix_spawn, not a manifest/session field.

Input regular file size1...1TiB and an empty owner0700 stage are pinned by no-follow/
CLOEXEC descriptors. Expected source/stage device/inode IDs are passed to the actual
writer, whose existing producer checks them before component writes. Source/executable
path/descriptor ID, mode/owner/link count/size and modification/change times are observed
before launch, at ready and after process settlement. Stage ID/mode/owner remain pinned;
its mtime/content change intentionally as the writer creates components. These are
observations, not an immutable snapshot, ancestor sandbox or same-user adversarial race
proof. No source/full-container hash is computed by this controller.

Tool capability currently has only a DEBUG generated initializer requiring fixed
staxrip-dolby-companion-writer basename and explicit expected64lowercase-hex SHA256.
Worker opens a regular executable1...32MiB, incrementally hashes it against that digest,
checks path/descriptor observations and keeps its descriptor through the operation.
This binds explicitly reviewed generated tool content; it is not DeveloperID signature,
team/notarization/native distribution provenance. The release build cannot construct a
capability through that initializer. No silent runtime download/fallback or writer
packaging/action/lease/resource policy is installed. Executable hash observations do
not make pathname-based spawn atomic against same-user replacement races.

D106 parser admits exactly ready, authorizes one41byte start frame, and accepts one
matching bounded staged row. Start is written without blocking, then stdin closes.
Staged output before finite stdin completion refuses. Stdout is read16KiB at a time;
parser rows remain bounded16KiB. Stderr is drained/discarded, never surfaced with source
payloads; exceeding64KiB refuses and aborts. Generic runtime diagnostics contain no
source/stage paths. Native process receipt still claims producer hashes/counts and
requires actual disk/original semantic checks; parser cannot authenticate that truth.

Worker polls at most10ms between runnable boundaries, checks cancellation and a positive
finite deadline up to120s, and does not reap the direct child until both output EOFs.
An exited leader therefore keeps its PID reserved while a descendant holds a pipe.
EOF without process exit remains pending and expires. Cancellation/protocol/read/deadline
refusal signals owned group SIGKILL, closes native pipes and waits for the direct child
before returning. Successful zero exit/EOF closes all parent pipes, rechecks pins,
requires no cancellation and finishes the parser. Task cancellation is checked again
on async return. No stage deletion or publication occurs on either path.

If group signaling or joining cannot be established, OwnershipFailure explicitly says
to retain the stage for review. Unexpected ECHILD is treated as loss of ownership and
never signals a potentially reaped/reused PID. Future D105 integration must distinguish
this unsettled ownership outcome rather than discarding automatically. Group signal
fallback targets only the still-owned direct child; it cannot qualify unknown orphan
writers. Fixed reviewed Rust writer has no fork/descendant launch. Generated group tests
cover a pipe-holding orphan; this caller can join only its direct child, not OS-reparented
descendants. Signals cannot preempt uninterruptible physical I/O; observed normal-file
copy cancellation does not establish hard deadlines under blocked filesystem/kernel I/O.

## Generated verification

Seven focused Swift test functions passed initially3.758s and final3.695s; final actual
both-mode native case0.508s. Generated retained-mode packets/RPUs/source bytes and all
actual component sizes/hashes agree with native parsed process receipt; metadata mode
has6members and full mode7including exact entire original container. The source fixture
has one packet/two duplicate signed-PTS RPUs and opaque enhancement bytes, not decoded
BL/EL pictures or residual reconstruction.

Cancellation at actual ready joins child before returning CancellationError and writes
no stage components. Actual-copy case appends a valid trailing Matroska global Void with
sparse128MiB payload to the generated source. The actual Rust writer streams it into
original-container.mkv; a new DEBUG process poll boundary cancels only after observing
positive but incomplete file length. After join the retained copy is still incomplete,
manifest absent and full generated source fingerprint unchanged. This demonstrates a
real streaming-copy cancellation window, not cancellation while blocked physical I/O.
A zero-exit settled boundary cancels before receipt admission; complete-looking files
remain without a successful returned result. These DEBUG boundaries are this new process
unit's fault fixtures, not new observers of D090 historical timing failures.

Wrong digest, nonempty stage and actual pre-cancel refuse before launch. Generated source,
stage or executable pathname substitution after ready refuses before start/data writes,
retaining original and replacement bytes. Seven generated native C surrogate cases cover
live silence/deadline, closed output pipes with live child, nonzero exit, malformed ready,
excess stderr, closed stdin/SIGPIPE avoidance and an exited direct child with pipe-holding
descendant. Direct child is already reaped (waitpid returns ECHILD) at return. Pipe-holder
is gone or stopped/zombie awaiting OS reaper; no orphan join claim. Surrogate paths are
explicit generated trust only; no fixture response can select source/stage/tool paths.
No production assertion/deadline or ordinary suite scheduling is changed.

Initial compile errors from conditional parameter syntax/C string array inference were
fixed without policy changes. A test closure's mutable header capture was replaced by
its fixed source length; final focused check records that warning cleanup separately.
Unchanged Rust/semantic/reference tools retain prior receipts, not new full-source runs.
Ordinary regression/build/final preservation settlement is recorded below.

## Gates and retained failure

Independent native original semantic admission and joining it to D105 publication are
next. Actual parent disk verification, native security-scope leases/resource policy,
fixed signed writer capability/packaging/hardened loading/distribution remain open. Stable
archive/import and persisted producer binding, ENOSPC/volume/crash, blocked-I/O behavior
and decoded association remain separate gates. Metadata-only excludes BL/EL pictures and
outside-track information; entire-container retains source-sized whole original including
other streams and embedded names/metadata. No native archive UI or production-ready claim.
Original preservation/compatible conversion/edited-picture statistics/enhancement
reconstruction/companion archival remain separate choices. Decoder candidate unbundled,
completed120552 association retained without repeat; interrupted DeveloperID attempt
retained without retry. Original media/session/current journal/prior outputs protected.
No owner queue/archive/full-film encode, listening, merge or release.

PR81 reader37193191544 passed1m53s. App37193191532 failed Fresh analysis6.648579vs5,
AV1 and ten-bit copy matrices both130.882s after unchanged120s deadlines. All348tests
finished468.176s3issues, preview skipped. Native protocol suite79.448s passed. Private
failed log retained/PR updated; no rerun, historical observer, assertion/deadline or
scheduling workaround. Causes remain unknown and D090 investigation remains completed.

| Claim | Kind / confidence | Evidence and limit |
| --- | --- | --- |
| Actual writer runs through native finite stdin and joined zero EOF/exit | observed_behavior / verified on generated files | Both retained modes, exact source/component hashes and direct child ECHILD; no production provenance capability |
| Ready/active-copy/late cancellation refuses completion after direct-child settlement | observed_behavior / verified on generated files | Actual Rust writer, partial128MiB copy and unchanged source fingerprint; not blocked physical I/O preemption |
| Signals are owned by one worker and never issued after its reap | source_fact / verified; observed_behavior / verified on tested paths | Single worker control flow + direct/native surrogate tests; external ownership loss is retained failure, not a guarantee against hostile parent reapers |
| Native production archive is complete | unknown | No semantic/disk/transaction/lease/signature/import/storage/decoded gates qualified |

Consequence local_only generated work, future user_data. Method Apple Swift6.4/Swift
Testing, locked unchanged actual Rust writer and operation-owned native C fixtures. Source
identities bind to draft PR/private handoff. Process/parser/tool/lifecycle/OS policy or
producer changes invalidate affected evidence. New process suite is serialized within
its seven generated ownership tests; existing suite scheduling/assertions stay unchanged.
Final focused7tests3.850s passed after test-only immutable capture cleanup with no new
warnings. Ordinary355tests/81suites203.526s passed. Optimized build/strict ad-hoc app and
read-only helper signatures passed; actual minimum declarations14.0/11.0, writer absent.
No hardened/notarization/older-OS runtime qualification. Nine changed/nonignored-untracked
repository files scanned for three exact owner path/name/stem identifiers: zero matches
with positive private sentinel; private media/receipts/ignored binaries excluded. Scoped
absence, not certification. Source stat/current recovery bytes unchanged; planning no findings.
