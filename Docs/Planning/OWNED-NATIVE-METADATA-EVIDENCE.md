# Owned native read-only metadata process evidence

D-113 qualifies an unused internal process prerequisite on generated files only.
It runs fixed `mkv-summary` using a caller-trusted generated helper with fixed basename,
explicit SHA256 and observed file identity. DEBUG factory only; no release capability,
signature/provenance authentication, native archive action or package comparison.
Existing ToolRunner/DolbySourceInspection and writer process remain unchanged.

One dedicated POSIX worker pins source/executable descriptors, compares source content
before/after with the fresh helper's complete hash/bytes and owns PID/group/stdout/
stderr/EOF/status. Null stdin, fixed minimal environment, fixed argv; no arbitrary
helper mode. Nonblocking16KiB pipe reads, stderr64KiB refusal bound, no full stdout
capture. Direct child stays unreaped until both EOFs or abort. Cancellation/deadline/
malformed output kills the owned group before direct-child waitpid; unexpected external
reap is an unsettled ownership error with no further signals. No signal timer runs
after reap. Final source/executable path/descriptor observations follow joined output.

The fixed stream parser rejects duplicate/unknown fields and malformed/excessive rows,
requires exact begin/packet/RPU/resources/complete schemas and order, source hash/size,
signed PTS/encoded-packet sequence/counts, packet/RPU offset bounds and peak bytes,
nullable duration/flags, compact summary shape and positive reported heap<=64MiB.
Unsigned TimestampScale/default duration preserve UInt64 extremes; signed PTS preserves
Int64.min/max. JSONL65536bytes includingLF/4000003rows; same bounded audit JSON grammar
(depth4/256values/20keys/16array elements/128ASCII string bytes). Resources are fresh
helper claims; no measured parent peak-memory/resource guarantee is inferred.

Callbacks receive bounded transient rows only, synchronously on the owning worker.
They must remain bounded/trusted and cannot launch unsettled work. Partial/full-looking
rows are not successful process receipts. The120s maximum deadline is a configured
development bound; physical I/O/parser/consumer CPU or blocked wait cannot be preempted.
No immutable source snapshot or hostile same-user executable/path guarantee is claimed.
Group descendants receive abort signals; non-child orphans cannot be portably joined,
and escaped/pipe-closing descendants are not a universal supervision guarantee. The
fixed audited Rust helper does not spawn descendants; C surrogates test pipe-holder
failure only, not metadata authenticity.

Observed actual rapid helper exit can make group SIGKILL return EPERM despite a joined
direct child. Keep typed CompanionUnsettledOwnership marker, retaining stage on later
transaction integration; no conversion to ordinary cancellation cleanup or success.
The new cancellation tests require either CancellationError or exactly observed
EPERM/joined marker before reap, plus joined child/source unchanged. Actual live-reader
cancellation separately confirms a non-zombie child before cancellation and joined
child afterward, using2000 generated repeated clusters and stdout backpressure.

Focused25tests/3suites4.651s passed; metadata suite4.650s. Actual read-only Rust helper
4packet/5RPU/1EL source report0.451s and exact generated original audit (excluding fresh
resources) match. Generated signed-extreme/unknown-Segment/nonzero-crop/UInt64 duration
sources0.386s; live stream cancellation0.181s;24 protocol refusal cases0.193s pass.
Nine compiled native process surrogates refuse deadline/EOF-live/malformed/overflow/
pipe-holder/full-output-live/nonzero cases. Wrong digest, unsafe source, pre-cancel,
launch/row/after-exit cancellation and late source/executable mutations checked.
No new warnings in final focused log; initial conservative ownership refusals and
captured-variable warnings retained, not successful receipts.

PR87 automatic compilation failed before tests at a long generated Video Data
concatenation; D113 splits it into typed fields/append reduction without changing
bytes/assertions. Hosted compiler qualification remains pending on changed code.
This is distinct from prior D090 unknown-cause test timing failures; no rerun or
historical observer/assertion/deadline/scheduling change.

Next: actual native stored audit/summary/source comparison using this owned reader and
D108 pinned member reads/final observations, then complete semantic transaction admission.
No full flags from a fresh stream alone. Release capability/packaging/signing, resource/
security leases, stable importer/persisted binding, owner losses/storage/privacy review,
ENOSPC/volume/crash/blocked-I/O and decoded association remain separate gates.
Final ordinary regression/build/protection settlement is recorded below when complete.


D-113 final ordinary regression:417tests in87suites passed206.698s; native metadata
process suite13.000s, actual live cancellation0.360s in that run. Focused25tests/
3suites4.651s retained. No new warnings in final focused/regression logs. Optimized
development build/strict ad-hoc app/read-only helper signatures passed; minima14.0/
11.0, writer absent. No DeveloperID/notarization/older-OS runtime qualification.
Ten changed public/nonignored-untracked files scanned against three exact private
source path/name/stem patterns: zero matches with positive decoded private source-field
sentinel; private media/logs/receipts/ignored binaries excluded. Source metadata/current
journal unchanged; planning findings empty. No native UI/action, owner queue/source
processing/private film archive/encode/listening, merge or release. Stored audit/fresh
summary comparison and complete semantic transaction admission remain next; no full
semantic flags or release reader capability claimed.
