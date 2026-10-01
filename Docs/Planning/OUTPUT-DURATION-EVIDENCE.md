# Bounded output duration evidence

Date: 2026-09-30. Slice 022, D-035 / R-025. Status: original-policy failure reproduced and corrected focused checks passed; full local regression/build passed; native passed; hosted passed at f52bade.

## Reproduction and policy

The original advanced batch check allowed a difference below max(250 milliseconds, one percent of planned duration). Two real 180-second, 24 fps generated-source exports were deliberately shortened to 179 seconds or extended to 181 seconds while preserving the expected codec, raster and track count. Both published and advanced the queue under the old policy. The pre-change regression failed in 1.014 seconds with 12 issues, including the measured accepted duration in both directions. The one-percent formula would allow a difference approaching 72 seconds at two hours; that is arithmetic from the source, not a two-hour truncated-export observation.

OutputDurationCheck now requires finite, positive observed duration and a finite expected value. For a known positive planned duration, the absolute difference must be strictly below 0.250 seconds regardless of length. Missing/nonpositive source duration preserves the existing unverified path but adds an explicit result statement. Mismatch errors show planned, observed and difference values and state that nothing was published. The completed result identifies the container-duration bound. Encoding arguments and all independent codec/raster/track/HDR/source checks remain unchanged.

## Focused evidence

The first corrected focused run passed three functions in 1.086 seconds. Unit cases cover matching and both sides of the strict quarter-second boundary at 1, 180, 7200 and 86400 seconds; invalid observed/nonfinite values; and explicit unavailable expected duration. Real shortened/extended outputs now refuse before publication, leave later jobs Pending, retain source/prior-output/unrelated-stage bytes and clean only their own stage. A fresh normal-encoder retry succeeds. A generated two-hour, one-frame-per-second source exports and trims near its end with the bounded verification result. A final fractional 24 fps trim check is included in the full regression gate.

## Limits

This compares declared container metadata with the current planned container/trim duration. It does not prove decoded frame completeness, track alignment, audiovisual synchronization or a correct source header. The two-hour fixture intentionally uses low frame rate and no audio; it is not real-film qualification. Unknown source duration remains explicitly unverified. Legitimate formats differing by 250 milliseconds or more now refuse and require an evidence-based policy revisit, not an automatic proportional exception. Audio mastering, native Quick Export and distribution remain outside scope.

Generated fixtures and logs are ignored work/output-duration. Final local release regression passed 189 tests in 37 suites in 37.545 seconds; app build passed in 14.12 seconds. The fractional 24 fps trim measured 2.25 seconds within one millisecond. Native receipt passed below; hosted acceptance passed.

## Native receipt

The rebuilt app opened the generated 180-second, 160 x 96, 24 fps source through its native picker, restored the generated H.264/no-audio session settings, and queued a new output. The configured destination was explicitly reviewed through the native folder picker. The queue completed and exposed Container duration within 250 ms of plan alongside the retained raster, display proportion, container and source-content checks. Independent FFprobe measured H.264, 160 x 96 and 180.000000 seconds. Source SHA-256 remained unchanged and no owned batch stage remained. This is a normal native export receipt; deliberately shortened/extended encoder cases were exercised by the integration tests.

Final hosted run 36802839483 passed at f52bade: Swift 6.1.2, 189 tests in 468.757 seconds, 9m01s job. No user media, local paths or generated outputs are committed.

## Acceptance mapping

S22-001: fixed strict boundaries and explicit invalid/unknown values passed. S22-002: actual shortened and extended encodes reproduce the old-policy failure and now refuse, preserve later intent and allow a fresh retry. S22-003: generated two-hour low-rate export, end trim, fractional 24 fps trim and native three-minute export passed. S22-004: local and hosted 189-test regressions passed with source, prior-output, unrelated-stage and owned-cleanup checks. The metadata-only limits above remain in force.
