# Advanced export source stability research

2026-09-30. Slice 019 activated after Slice 018 hosted acceptance.

Code trace: BatchController.encode takes a whole-source SourceFingerprint only for Preserve static HDR10. Ordinary SDR jobs probe source metadata, encode, verify codec/raster/display shape/duration/tracks/container contents/captions and publish. Those checks do not identify source content. The existing HDR fingerprint reader uses an async Foundation file loop; extending its callers blindly would also extend its behavior to special files.

A generated command-line spike probes a blue H.264 video, replaces that selected path with a red H.264 video, then encodes it. Both probes report h264, 160x96, SAR 1:1, DAR 5:3, one second, no audio/subtitles/chapters. Source SHA-256 changes. This demonstrates that matching metadata is insufficient; it is not yet an app-level rejection test. Receipt: ignored local work/source-stability/spike.json.

Candidate: fingerprint all advanced queue source bytes before metadata inspection and after output verification, just before publication. Reuse the existing SHA-256 plus byte-count value, but use an export-specific regular-file reader on a utility queue. Open read-only with close-on-exec, nonblocking and no-controlling-terminal flags, then fstat and reject nonregular or empty input. Keep symlinks to regular files supported. Bound reads to the initially observed file size, compare descriptor size/change timestamps and path identity before returning, and close on every path. This avoids waiting for FIFO content or chasing an endlessly growing file.

The installed macOS open(2) manual documents O_NONBLOCK, O_CLOEXEC and O_NOCTTY; fstat supplies descriptor type and size. These flags do not establish bounded latency for all network filesystems. Cancellation should be checked between chunks and before returning, with the async operation awaiting the actual reader outcome. Never abandon a reader and delete its state just because a UI deadline elapsed.

Provide throttled byte progress for long source checks, tied to the current check identity so delayed callbacks cannot replace encoding/publication progress. A changed fingerprint refuses publication and stops later jobs. Existing HDR full-frame checks and content rechecks remain, while its duplicate final hash can move to the common path. Audio/preview readers are outside this change.

Costs and limits: two full source reads for normal SDR jobs, additional I/O on large or slow sources, no source snapshot or filesystem-wide write lock. Compare observed content at the checked boundaries and report that scope. This cannot prove absence of a malicious transient rewrite restored between observations or make arbitrary I/O interruptible. No whole-film throughput claim.
