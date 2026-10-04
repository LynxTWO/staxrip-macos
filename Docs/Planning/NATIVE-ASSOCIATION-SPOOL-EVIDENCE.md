# Native association storage prerequisite

D-125, R-059 / Slice049. Source facts and generated observed behavior only.
The unused native DolbyAssociationSpool stores D110 packet and escaped-RPU observations
by encoded index. System SDK SQLite3 loads locally at version3.54.0. There is no new
third-party package or downloaded binary. Both generated original-source walkers feed
four packet/five RPU rows through this spool and read back every field. Multiple RPUs,
signed duplicate/nonmonotonic PTS, Int64 extremes, UInt64.max duration and nullable flags
survive without deduplication. A source-pass count result is not frame association proof.

## Concrete ownership and bounds

The trusted synchronous caller creates/owns an empty0700 folder and keeps its worker
on one thread. The spool exclusively creates fixed association.sqlite0600 through an
owned no-follow folder descriptor. It pins folder/file IDs, modes/owners and single file
link count. F_GETPATH supplies SQLite's concrete folder path from that descriptor.
SQLite OPEN_NOFOLLOW remains enabled; caller and concrete paths must keep matching the
pins. Only fixed prepared queries and bound observation values are used. No source
path, payload, arbitrary schema, helper-selected file or executable is stored or opened.

Configured caps:4096-byte pages,131072 maximum pages (512MiB database),8MiB requested
cache, no mmap,2M packet rows/2M RPU rows,1TiB declared source,16MiB encoded packet,
65536-byte RPU. Counts, offsets, sequence and hash shape are checked before inserts.
SQLite memory journaling is checked; each row uses autocommit to avoid a whole-source
in-memory rollback journal. The fixed queries do not sort or retain a whole stream.
These settings are not a measured total memory ceiling or whole-film speed guarantee.
Cancellation occurs before/after native operations. SQLite and physical I/O cannot be
preempted by these checkpoints. No long shared async worker wait or helper is introduced.

Any refusal poisons the pass. Source-pass count settlement/read-back and final path/
membership checks precede a normal return. All statements finalize on their scoped exit;
SQLite close and both POSIX close results must succeed. An uncertain close is a shared
CompanionUnsettledOwnership marker. There is no automatic removal, discovery, import,
publication, source access/activity controller or production retained-review release API.
The caller must settle all work and revalidate ownership before any cleanup. A completed
file, caught error, count or escaped object cannot establish an association receipt.

## Discriminating failures retained

Initial fixture compilation failed recursive nested Swift Testing throws macros. The
precise nested use was replaced with explicit error observation; assertions remain.
Early runtime runs refused during initialization. Native discriminator found APFS folder
link count2 becoming3 after the owned file was created. Directory identity keeps
mode/owner/dev/inode and exact membership; file single-link checks remain unchanged.

Separate SQLite discriminator observed no-follow CANTOPEN through temporary path aliases
and success at a concrete /private path. F_GETPATH now binds the actual owned folder;
no no-follow policy is removed. Further discriminator saw a journal side file after the
requested OFF mode. OFF was not established. Checked MEMORY with row autocommit avoids
that side file. A throwing Boolean compile expression was corrected explicitly.

A subsequent descriptor-number assertion failed in concurrent fixtures. Such numbers
alone cannot identify a closed descriptor after reuse. Final tests observe successful
owned close syscall results and refuse escaped closed objects; no global concurrency,
historical timing deadline/assertion or D090 observer changes follow. Temporary new
constructor diagnostics are removed, with private logs retained.

## Scope still open

No actual native source/spool/decoder composition, exact rational tick comparison or
one-picture-per-original-packet admission executes here. D124 source-frame and edited
picture flags stay false. Invisible declarations and surplus RPUs are retained in
storage; a later conversion admission must refuse unsupported picture multiplicity,
never deduplicate it. No portable persisted importer, immutable snapshot, producer
provenance, hostile same-user or crash/power-loss durability is established. Product
Preview still excludes writer/decoder; no queue, UI, owner media body or film run,
listening, certificate retry, library-validation bypass, merge or release.

## Checks

Final composed focus8tests/3suites13.144s passed: actual native D110 both-mode source
round-trip0.837s, spool six tests0.022s and93-source statically linked hardened native
qualification host13.143s. The host links the new SQLite dependency but its pipeline
still exercises existing preservation/review; it does not execute the spool there.
Final measured storage focus6tests0.022s passed: actual SQLITE_FULL after194 inserted
rows with32768-byte database at the configured8-page bound, all owned close calls
successful. This is a SQLite page-cap refusal, not physical volume ENOSPC or APFS-full
qualification. Cancellation, count/sequence/record-limit, unsafe/preexisting members,
late file substitution and extra membership refuse with source/prior files preserved.
Ordinary regression, optimized product/signature and privacy checks follow below.

The preceding PR99 automatic run37229721475 independently shows seven decoder surrogate
assertions with child>0 false. Its State.assertJoined then called waitpid(0), which may
reap another same-group fixture child. D125 guards that unsafe diagnostic syscall while
keeping the positive-child/equal-joined assertion unchanged. It does not accept a missed
launch as successful fault coverage, alter the0.25s deadline, or establish the precise
pre-launch refusal cause. This observed ownership problem is confined to the new decoder
fixture; it does not diagnose D090 historical timing failures. The local ordinary run
using the old fixture remains retained. Changed decoder focus and qualification follow.

Changed ordinary468tests/98suites213.595s passed with28 unchanged explicit opt-in
skips and no emitted warnings. The original failed468tests222.982s/two issues is
retained. The changed run verifies the guarded diagnostic with current code; it does
not identify why prior surrogate launches were absent or fix hosted deadline reliability.
No known-crashing dynamic loader or private frozen decoder was enabled. Remaining
source/spool/decoder composition and full association flags stay unqualified.

Explicit release build observed Building for production and completed52.63s with no
warnings. Current strict ad-hoc app/read-only helper signatures pass; minima14.0/11.0.
Writer and decoder remain absent. Nine-file privacy scan has zero owner path/name/stem
matches with positive sentinel; source metadata/current recovery journal unchanged,
no owner media body read. Planning findings empty. Owned19716 temporary awake receipt/
command/start remain matched, expires21:30:44UTC. No persistent security setting change,
UI walkthrough, positive certificate loading, distribution or full association claim.
