# Advanced export source stability evidence

Date: 2026-09-30. Slice 019, D-032 / R-022. Status: focused, full local regression and native acceptance passed; hosted gate pending.

## Scope and implementation

Every advanced queue job observes a SHA-256 and byte-count fingerprint before source inspection and again after output verification, immediately before publication. Different observed bytes refuse publication, stop later jobs and clean only the current owned staging. A retry observes the current source afresh. Static HDR10 retains its additional post-preflight content check and full-frame audits; its final fingerprint now uses the common path. Quick Export and audio/preview fingerprint readers are unchanged.

The export-only reader opens read-only with nonblocking, close-on-exec and no-controlling-terminal flags. It requires a nonempty regular file, follows ordinary symlinks to regular files, reads at most the initial size with a fixed one-MiB buffer, hashes incrementally and compares descriptor size/change timestamps and path device/inode before returning. It refuses missing, empty, directory and FIFO inputs; growth, truncation, same-size edits and atomic path replacement are covered. It uses a utility queue. Cancellation sets a locked flag and waits for the reader to close its descriptor; no timeout abandons in-flight I/O.

Byte progress emits at most 101 callbacks per check. A per-check identity rejects delayed messages after completion or cancellation. The queue explains source-read overhead in Start queue help and reports waiting for a cancelled source check until it settles. Existing exclusive publication and recovery formats are retained.

## Focused checks and negative control

Seven test functions in two suites passed locally in 0.503 seconds, including parameterized cases:

- Known SHA-256 for `abc`, independent multi-chunk digest, byte count, ordinary symlink and bounded monotonic progress.
- Missing/empty/directory/FIFO refusal without waiting for a writer.
- Append, truncate, in-place change with changed timestamp, and atomic replacement during the content read.
- Cancellation before work and while a deterministic worker gate is held; the operation cannot return before the worker is released.
- Real generated blue/red H.264 sources with identical checked metadata. Replacement before encoding or after encoding refuses with the source-content reason, preserves a prior output and unrelated staging, leaves later jobs Pending, and supports a fresh retry.
- Delayed progress after Completed cannot change the result. Held initial/final queue checks retain running state and owned staging until cancellation settles; delayed progress cannot overwrite the stop message.

Negative control: temporarily removing the final fingerprint comparison made the replacement regression fail with eight issues across its two cases. Changed content was published and later jobs ran. The comparison was restored before regression/build. Local logs are retained in ignored work/source-stability; no generated media or machine paths are committed.

## Regression and native receipts

The first full run reached 173 tests and found one existing HDR assertion that expects the phrase “Source changed.” The new shared refusal now preserves that phrase and explains that the content fingerprint differs. No existing assertion was weakened. Final release regression passed 173 tests in 34 suites in 36.694 seconds. The ad-hoc development app built in 13.79 seconds. Initial hosted run 36795072130 at 1f552e9 failed in an inherited HDR test: its 20-second polling window ended while the batch was still running outside Encoding. The run does not establish whether it was still inspecting or had passed encoding. The mutation test now uses a real encoder wrapper to append one byte after successful encoding and before queue verification, and asserts that the mutation occurred. It retains the source-change refusal, no-publication and later wrong-output-declaration assertions. Final regression/build and hosted results follow below.

Native walkthrough on the development Mac used a generated one-second 160x96 H.264 MP4 extended with a valid trailing `free` atom to 4 GiB logical size, with 4 KiB allocated. This exercises repeated chunking without allocating gigabytes of media storage. A saved generated session restored the settings; source and destination were then explicitly selected through attached native pickers. The restored source initially showed the known access/load limitation; explicit source selection resolved it. Durable access is not fixed by this slice.

Start queue help exposed the two whole-source reads and their cost. During execution, accessibility showed INSPECTING and “Checking source content before inspection · 1.59 GB of 4.29 GB,” with Cancel batch available and configuration editing disabled. The job then showed COMPLETED, the expected geometry/container checks and “Source content fingerprint unchanged,” with Reveal output available. A screenshot confirmed the completion detail wrapped within its card. Spoken VoiceOver and other platforms remain separate.

Independent post-run hashing confirmed unchanged source SHA-256 and byte count; ffprobe confirmed H.264, 160x96, SAR 1:1, one second, no audio. The output was 2,238 bytes and no owned staging remained. Native artifacts and receipts are local ignored work/source-stability/native. This is a sparse-file responsiveness check, not physical storage throughput or long-film qualification.

## Limits

Normal SDR exports add two full source reads. The reader holds a fixed chunk, not a whole-file copy, but no broad throughput target is claimed. Regular-file I/O on a slow or unavailable filesystem can still block inside a syscall; cancellation waits for that syscall to return while keeping the UI free. These checks compare observed content at boundaries, not an immutable input snapshot, filesystem write lock, or detection of every transient rewrite-and-restore. Long films, network volumes and hostile concurrent writers require separate qualification. Audio listening, signing, merge and release are outside this slice.

## Final lifecycle review

A cancelled source check now retains its active identity until the reader returns, but disables progress acceptance immediately. Keeping the active identity also keeps delayed HDR-audit callbacks from overwriting the waiting message. The held initial/final check tests exercise cancellation and late content callbacks. No saved-format change is involved.

Final release regression after the lifecycle correction and deterministic HDR mutation passed 173 tests / 34 suites in 36.657 seconds.
