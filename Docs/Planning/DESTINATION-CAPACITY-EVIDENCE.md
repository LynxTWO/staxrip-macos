# Destination capacity evidence

Date: 2026-09-30. Slice 012 / D-025 / R-015. Local and native acceptance passed; hosted ordinary regression pending.

## Fixture boundary

A disposable 64 MiB read/write disk image was formatted HFS+ and attached at a private work-directory mount on macOS 27.0.1 / Apple M5. Filesystem capacity was 67,067,904 bytes. It had a dedicated device identity and an explicit fixture marker. Only generated data was written; the main filesystem was never filled. The test bounds filler writes to 64 MiB and requires a separate mount, marker, capacity at most 64 MiB and at least 8 MiB initially free. The source and journal stay on the ordinary workspace filesystem.

This validates a local HFS+ image. APFS, physical removable media, network filesystems, interrupted writes, and full journal/source volumes remain unqualified. It is not a free-space predictor. The test is opt-in through STAXRIP_CAPACITY_TEST_MOUNT; the marker and mount checks do not authorize pointing it at owner data.

## Automated result

The focused final test passed in 0.324 seconds with FFmpeg/ffprobe 9.0.2. A filler reached actual ENOSPC after 65,470,464 bytes. Production BatchController then started an actual H.264 encode: FFmpeg exited 228 with trailer/close errors reporting No space left on device. The test specifically requires that encoder error, not just any failure.

The first job became Failed with no published destination; the next stayed Pending. Source bytes and an existing sentinel output stayed unchanged. Owned batch staging was absent. Removing only the generated filler and explicitly retrying the first job produced Completed with a readable H.264 output, unchanged protected files and no staging leftovers. No production changes were required.

The ordinary release regression passed 119 tests in 23 suites in 10.565 seconds. Fifteen opt-in tests were skipped, including this capacity fixture; its separate opt-in success is recorded above. No application source changed, so the previously validated optimized app build was used for the native check.

## Native result

A generated two-job session was loaded without starting execution. On the full fixture, explicit Start queue showed Failed and the readable No space left on device error, with the second job Pending. Accessibility text and screenshot agreed. Both destinations were absent; source/sentinel hashes matched and staging was absent.

After removing only the generated filler, explicit Start queue completed both jobs. Both results independently probed as readable, protected hashes still matched and staging was absent. The owned disk image was detached successfully after validation; its generated outputs remain inside the bounded image. No source files, owner outputs or historical staging were deleted. The saved test session is local-only and points into that disposable fixture, not a normal user workflow.

## Reproduce locally

Run `./scripts/check-destination-capacity.command` from the checkout on macOS with FFmpeg installed. It creates its own unique temporary 64 MiB image, runs only the opt-in test, then detaches and removes that owned fixture. If detaching fails, it retains the fixture and reports its path instead of deleting mounted contents. Do not point STAXRIP_CAPACITY_TEST_MOUNT at an existing owner volume. The wrapper itself was run successfully locally.

## Remaining gate

Hosted ordinary regression pending. Hosted execution is not claimed to run the opt-in capacity test. No audio listening, broad filesystem qualification, merge or release acceptance.

## Hosted gate diagnosis

Run 36724013329 at e893ae6 failed in the pre-existing BatchCleanupTests cancellation case. Verified observations: the five-second startup poll expired without a writer marker, cancellation then reported No output published with no cleanup attempt. This did not exercise the intended writer-cleanup boundary. Hosted scheduling/probe contention is a plausible cause, not a reproduced local diagnosis. Capacity execution was skipped on the host as designed.

The cancellation test now waits for its writer-owned marker while the batch runs, requires a live Encoding phase before cancellation, and uses a one-minute test-level limit with cancellation-aware polling and deferred cleanup. It no longer proceeds into outcome assertions after a missing prerequisite. Existing process-settlement, retained partial bytes, primary outcome, cleanup warning and protected-file assertions remain. No product behavior changed.

The corrected test includes a deliberate six-second probe wrapper to exceed the old startup deadline and verifies cancellation still targets the started encoder. Both failure/cancellation cases passed locally in 7.542 seconds within the full release regression: 119 tests, 23 suites, 9.491 seconds, 15 opt-in skips. This reproduces the deadline trigger; it does not establish the hosted scheduler's precise cause. A fresh hosted run is required.
