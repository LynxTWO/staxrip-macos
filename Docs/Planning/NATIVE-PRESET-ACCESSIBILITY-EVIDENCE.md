# Native preset accessibility and subprocess evidence

Date: 2026-09-30. Accepted Slice 023, D-036/R-026 and dependency amendment D-037/R-027. Local regression, native workflow and final app build passed. Final hosted gate at 543b991 passed; earlier failed attempts remain below.

## Native preset semantics

Quick Export derives short native-preset labels through the shared spokenCodecs helper, so H.264 becomes H two six four. Selected / Not selected follows NativePreset. Visible names remain voice-control input aliases. Optional hints explain AVC/HEVC, Apple preset behavior and the separation from workspace settings. Visible titles, preset identifiers and encoder choices are unchanged.

Native activation of H.264 720p, HEVC 1080p and H.264 1080p left exactly one Selected value after each choice. The accessibility tree exposed all names and hints, and a screenshot confirmed unchanged visible cards. The final rebuilt app also exposed the expected labels and default selection. This proves exported semantics, not heard pronunciation or actual voice-control recognition. No system accessibility preference changed. S23-001/S23-002 have direct native evidence; S23-003 has local/native/hosted evidence. No tests merely mirror text literals.

## Reproduced subprocess dependency defect

The original ToolRunner scheduled blocking process waiters and pipe readers on shared dispatch workers. An isolated generated-byte probe completed 16 children in 0.204 wall seconds, but 96 children stalled until a 45-second external watchdog. A process sample recorded 64 workers inside Process.waitUntilExit and 64 live child processes. The watchdog terminated only those identified generated children and its own parent probe. This verifies a local worker-starvation defect; no hosted sample proves that every earlier hosted timeout shared this cause.

ToolRunner now joins process-termination notification and two nonblocking pipe readers. Readiness events drain bounded chunks on independent serial queues. No worker waits for child exit or another dispatch block. Return waits for exit, both EOFs, reader closure and completed callbacks. Literal arguments, retained stdout/stderr limits and cancellation escalation remain. A second process on the same active runner refuses explicitly. Admission occurs before completion-group entries are created, and launch failure balances those entries.

The repaired isolated probe completed all 96 children with full stdout/stderr and expected exit status in 0.085 wall seconds; 16 also passed. This is a bounded liveness observation, not a throughput or memory benchmark. Arbitrary callbacks, descendants holding inherited pipes and filesystem latency remain outside that proof.

Three focused tests exercise 96 actual children producing 1 MiB stdout plus 32 KiB stderr each; complete callback bytes while retaining only a bounded tail; and direct-child cancellation that ignores INT/TERM until forced exit. They also check empty output, nonzero exit status, active-runner refusal and retry after launch failure. Final focused run passed in 4.313 seconds. S23-004/S23-005 have local and hosted evidence.

## Local regression and build receipts

| Source/test scope | Result |
| --- | --- |
| Original label change e2a543f, release | Framework reported 189 tests / 37 suites passed in 37.420 seconds |
| Original label change e2a543f, debug | 189 tests / 37 suites passed in 214.521 seconds |
| Initial runner repair e7b6e63, release | 192 tests / 38 suites passed in 38.272 seconds |
| Ownership test c8ec24f, debug | 192 tests / 38 suites passed in 212.873 seconds |
| Instrumented existing display matrix 6d4a4ec, focused release | All 12 exports and independent output assertions passed in 1.994 seconds |
| Final bookkeeping repair 543b991, release | 192 tests / 38 suites passed in 38.200 seconds |
| Final ad-hoc app 543b991 | Build passed in 14.63 seconds; launch and native preset semantics passed |

Full local suites retain 16 existing opt-in skipped entries, including listening/long-resource, hardware and owned-volume checks. They are not new coverage for this slice. Audio feature work and owner listening remain parked; existing audio regression still executes. No tests were additionally disabled and no assertions or deadlines relaxed.

## Native process workflow

The initial repaired app e7b6e63 built in 14.61 seconds. A generated 60-second 640x360 H.264 source was explicitly selected through the native file picker. The queue export completed with verified duration, raster, display proportions and source fingerprint. A second output was cancelled during visible encoding: Cancelled / No output published, absent final path, no owned staging, and unchanged source and earlier output SHA-256. Explicit Start queue retried successfully. Independent ffprobe measured 60.000000 seconds, H.264 and 640x360 for both completed files. A screenshot showed readable completion details. The later bookkeeping correction affects refused/failed launches; this successful native path is unchanged.

Before explicit source selection, opening the generated saved session triggered a native read that waited inside CoreMedia file open and did not settle after Cancel. A process sample showed AVURLAsset teardown waiting; the app stayed interactive and was quit to end the read. This is not a successful cancellation receipt or a confirmed permission root cause. Selecting the same source after relaunch resolved the local workflow, after which the saved settings loaded successfully. Durable restored-session access and arbitrary native I/O latency remain open release gaps. No source/output change occurred during the failed attempt.

## Hosted receipts and scoped acceptance

| Run / head | Result |
| --- | --- |
| 36804013683 attempt 1 / e2a543f | 30 issue records across multiple suites; no later test progress; manually cancelled after 20m40s. Not accepted |
| 36804013683 attempt 2 / e2a543f | Failed after 539.182 test seconds with five time-limit issues. No further unchanged retry |
| 36807168879 / e7b6e63 | Passed: Swift 6.1.2, 192 tests in 495.690 seconds, including new fan-out/cancellation tests |
| 36807330169 / c8ec24f | Failed: one 120-second limit in the existing 12-export display-proportion matrix. New process tests passed |
| 36808273566 / 6d4a4ec | Passed: 192 tests in 469.076 seconds; matrix exports completed in 81.647 seconds |
| 36808673370 / 543b991 | Passed: Swift 6.1.2, 192 tests in 439.807 seconds; matrix exports completed in 87.375 seconds, full matrix test 94.274 seconds |

The display matrix took 98.711 seconds in the passing hosted run and 8.795 seconds in local debug. Its failed phase was not logged, so resource contention remains inferred. At most 96 phase-only records now identify progress without personal paths. All 12 media cases, output assertions and the 120-second deadline remain intact. The final product/test head passed without changing the cases, assertions or deadline. S23-001 through S23-005 are accepted within these limits; hosted timing variability remains visible in the retained receipts.

Ignored local receipts live under the native-preset-accessibility work directory: original/final regression logs, hosted logs, the isolated diagnostic's baseline and repaired receipts, native before/cancellation/verification receipts and the native wait sample. No generated media, private paths or binaries are committed. Draft PR 40 remains unmerged; there is no release or notarization claim.
