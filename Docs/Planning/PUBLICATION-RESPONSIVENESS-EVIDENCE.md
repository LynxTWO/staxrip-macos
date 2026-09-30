# Responsive batch publication evidence

Date: 2026-09-30. Slice 014 / D-027 / R-017. Local and native checks passed; hosted regression pending.

## Publication ownership

Advanced batch publication now dispatches the existing exclusive hard-link operation to a background worker and awaits its actual result. Cancellation before dispatch prevents publication. Cancellation after dispatch does not resume the caller early, remove staging or hide an eventual success. A successful output remains Completed and later jobs remain Pending; a filesystem failure remains Failed. The journal lease lasts through the operation and cleanup. The persisted phase remains Verifying; only a transient publishing job identity drives the Finishing label and Stop after current publication control. Late HDR progress callbacks cannot replace the finishing message.

There is no hard timeout for a blocked filesystem syscall. Quick Export/audio publication and other synchronous I/O remain outside this migration. This does not establish durable access across launches or resolve every remote/filesystem permission issue.

## Automated checks

A controlled synchronous worker waits behind a semaphore while main-actor test code continues, observes the worker is off the main thread, requests cancellation, and then permits the real hard link to finish. A separate pre-cancelled test proves no output is created. Real generated H.264 batch fixtures hold publication in both success and competing-destination cases. Before release, the batch stays running, owned staging remains, cleanup has not run, and recovery identifies the in-flight item as Interrupted. After cancellation and release, success preserves a probe-readable Completed output; a competing destination fails with its bytes unchanged. Later jobs stay Pending, source and prior-output bytes are unchanged, and owned staging is removed only after the publication returns. Restored journal phases match the outcomes.

The focused three test functions (including two queue cases) passed in 0.176 seconds. Full release regression passed 125 tests in 25 suites in 10.177 seconds, with 15 existing opt-in tests skipped. The final optimized ad-hoc build passed in 12.78 seconds. These checks do not add audio listening or mastering acceptance.

## Native walkthrough

On macOS 27.0.1 / Apple M5, restored generated completed jobs exposed the new per-job source and destination access sheets. Cancel preserved queue paths and status. Selecting a different generated source reported a mismatch without changing the queue. Entering the exact configured source path through Go to Folder reported Source selection reviewed; selecting the configured parent reported Destination folder selection reviewed. No action started an encode or relinked a job. Matching is lexical standardized file-path comparison, not a potentially blocking main-thread symlink traversal; aliases and alternate path spellings are not promised equivalent.

One generated job was then explicitly edited to a fresh output name and started. It completed with verified 1800x1080 raster dimensions. Independent probing agreed. Source and both earlier output SHA-256 hashes were unchanged. This run removed its own staging; the one interrupted staging directory preserved during Slice 013 remained untouched. The native publication did not block, so actual stalled-call UI/stop behavior is supported by deterministic held-operation evidence, not claimed as a reproduced native hang.

Initial attempts to open the existing runModal session picker left a modal session that native automation could not see; an idle app restart and direct queue recovery enabled the sheet-based access walkthrough. This interaction limitation is recorded separately, not treated as a successful session-open check. The early source-selection mismatch was traced to an automation click selecting another row, not established as a product comparison defect.

## Remaining gate and boundaries

Hosted regression is pending. No merge, release, signing or notarization was performed. Other filesystem operations, durable bookmark persistence, manual VoiceOver listening, broader OS/CPU coverage, forced-process-exit ownership and network/removable-storage cases remain separate work. Apple's [filesystem responsiveness guidance](https://developer.apple.com/documentation/foundation/improving-performance-and-stability-when-accessing-the-file-system) informs the background-I/O boundary; native panels use [NSOpenPanel](https://developer.apple.com/documentation/appkit/nsopenpanel) without broad security settings changes.
