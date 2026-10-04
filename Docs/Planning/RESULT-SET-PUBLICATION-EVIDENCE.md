# Companion result-set publication prerequisite
Version: 0.1. Date: 2026-10-04. Scope: D-099 / R-059 / Slice 049.
Status: focused generated filesystem, ordinary regression and optimized build passed;
unused internal seam, archive/native integration still open.

## Outcome and product boundary

ResultSetStaging is an unused internal publication seam. A future export with an
explicitly requested companion must verify every requested component before presenting
success. This implementation checks the exact file set, lengths and SHA-256 digests
then moves the same directory to the chosen result name using Darwin renameatx_np with
RENAME_EXCL. It never falls back to replacing rename or individual-file publication.
Existing flat-file exports, BatchController, session formats, native controls and
recognized dynamic-HDR refusal are unchanged.

The component receipts are supplied by a trusted operation after all its writers
settle. They are not accepted from a saved session or a public archive import. One
manifest.json member is required, but its semantic content is not parsed here.
Opaque fixture contents are deliberately not playable-media or Dolby archive evidence.
Content checks cannot prove original BL/EL/RPU/configuration completeness, decoded-frame
association, correct transformed metadata or future reattachment/playback compatibility.
Those must be established by archive producers and semantic verifiers before integration.

## Ownership, resource and cancellation contract

The operation creates a unique private 0700 stage in the destination parent and retains
parent/stage descriptors. Immediate filenames use a bounded ASCII basename subset;
path traversal and hidden names are refused. There must be 3...16 unique requested
members including a manifest no larger than 1 MiB. Components are nonempty, at most
1 TiB each, and exact membership disallows extra files. This is a verification bound,
not a consented storage budget; source/output size estimates belong to native review.

Verification runs on an owned dispatch queue retaining caller priority. A 1 MiB read
buffer streams hashes. At most 16 component descriptors stay open through verification,
with exact device/inode/type/owner/size/link-count/mtime/ctime checks before commit.
Only singly linked regular files owned by the current user are admitted. Symlinks,
FIFOs, directories and hard-linked members refuse. Enumeration is bounded and repeated
with an independent directory-open description. Stage membership/identity and parent
identity are rechecked; stage substitution refuses without removing the replacement.

Cancellation before commit admission refuses. A short locked transition admits the
single rename; its syscall runs without holding the cancellation lock so cancellation
does not wait on filesystem I/O on the caller's actor. Once admitted, return the actual
success or failure after worker settlement, even if cancellation arrives. A successful
commit cannot be described as an unpublished cancellation. All verification descriptors
close before the waiter can clean up or retry. There is one active operation per stage.

Explicit discard removes only immediate entries of the captured owned stage. It never
recurses or follows a link; directories and permanent cleanup failures leave an honest
temporary-files-remain error. It refuses active/published/discarded or substituted
stages. Deinitialization closes descriptors but does not silently attempt cleanup.
Native integration must own that explicit settled cleanup and report failures.

The same-parent exclusive rename provides one directory visibility boundary on the
host filesystem. Filesystem support failures return an error without fallback. This
is not fsync/power-loss durability, arbitrary remote-volume qualification or protection
against a same-user adversarial writer racing the last check. Producers must be settled
and the parent/stage kept stable. No source snapshot or immutable archive is implied.

## Generated observations

Verified observed behavior on the development Mac: 12 focused Swift tests with 29
parameterized invocations passed in 0.037 s. Actual generated filesystem operations
check the intact media/companion/manifest set and same directory inode after commit;
file, empty-directory and dangling-symlink destination collisions preserve the original
entry, and a new destination succeeds using the same stage after collision.

Missing/extra members, changed lengths and same-length hash corruption (including the
manifest) refuse. Symlinks, hard links, FIFO and directory components refuse without
following protected content. Invalid paths/receipts refuse. Rewrite, atomic replacement,
append and extra-file mutations after hashing refuse. Substituting the stage refuses
both publication and deletion of the replacement. Generated source/sentinel bytes stay
unchanged. Cleanup refuses recursive traversal and succeeds after its known invalid
producer entry is removed in the owned fixture.

Semantic barriers test cancellation before verification finishes and after successful
commit. The caller cannot discard an active stage or start a second publication; the
cancelled worker settles before cleanup. Already-cancelled requests take no ownership.
A committed set returns success despite later cancellation. Two actual competing stages
publish to the same destination; exactly one wins and all final components belong to
that winner. These barriers inject lifecycle cases, not a timing investigation or a
new observer of the historical hosted failures.

An initial compiler exclusivity error in the new streaming loop was corrected by
computing requested read size before entering the mutable buffer closure. The retained
initial compile log is not passing evidence. Final focused compilation/checks passed;
no historical assertions, fixtures, scheduler or deadline changed.

Final ordinary app regression passed 331 tests in 78 suites in 209.291 seconds with
existing default scheduling/assertions and opt-in skips retained. Optimized build.command
passed; outer app and existing Rust helper signatures verify. Actual app Mach-O minimum
is macOS 14.0. This is development ad-hoc signing, not Developer ID/notarization or an
execution check on macOS 14 hardware. No new helper/library was bundled. New product
and test files compile without new warnings; existing Swift concurrency warnings in
two unrelated tests remain. No UI/controller/session change requires an owner walkthrough.

Privacy scan examined eight changed/nonignored-untracked repository files for exact
owner source path/name/stem (three patterns, zero matching files, positive sentinel).
Ignored binaries, private receipts and original media were excluded; this is scoped
identifier absence, not universal secret detection. Source descriptor and current
recovery bytes remain unchanged. Planning audit reports no findings.

Automatic PR 73 app run 37181281124 failed the existing cancellation assertion at
6.251403 seconds versus five; 319 tests settled with one issue in 449.741 seconds.
The AV1 matrix passed in 116.965 seconds. Failure remains in the hosted qualification
record; no rerun/observer/deadline change and no inferred causal repair follows.

## Remaining gates

Archive byte writers and manifests, original/transformed component separation, complete
BL/EL/RPU/configuration/timeline verification, meaningful storage estimates and native
result review are open. Actual ENOSPC for this new directory path, unsupported volume
behavior, parent movement and crash recovery need their own qualification before a
production claim. Existing file-publication/APFS evidence does not prove those new
cases. No owner source/session/queue/output was edited or executed; no new dependency,
conversion admission, subjective listening, hardened signing, merge or release.
