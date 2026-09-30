# Filtered frame stepping evidence

Date: 2026-09-30. Slice 018, D-031 / R-021. Status: local and native acceptance passed; hosted gate pending.

## Contract

Previous/Next frame scan decoded presentation timestamps for the inspected video stream, using its rational time base. The scanner keeps one partial line of at most 256 bytes and adjacent timestamp state, with at most two million scanned records. It requires nonnegative bounded, strictly increasing PTS, finds the current anchor rationally and respects the configured trim interval. Missing, duplicate, backward, malformed or absent-anchor evidence fails; it never computes a frame step from average FPS.

The helper stops after sufficient prefix evidence and ToolRunner awaits actual process exit and pipe drainage. Task cancellation wins over an intentional early scan stop. The whole step has a 120-second limit, including source identity checks and rendering. A boundary requires a stable source and retains the current pair with an explicit first/last-frame message. It does not silently duplicate a frame as a successful step.

A selected neighbor renders through the existing full-history comparison path. Both original and filtered rational stamps must equal that selected timestamp. Source fingerprints bind the prior comparison, discovery and replacement. Source/settings/time edits, cancellation and failed stepping prevent retained old pictures from becoming a current stepping anchor. Normal rendering resets boundary state. Completion clears transient cancellation status even if cancellation happened just before the awaiting actor resumed.

## Automated evidence

Nine new test functions cover streaming one-byte chunks, equivalent time bases, VFR gaps, trim and EOF boundaries, malformed/duplicate/backward/missing/oversized records, frame-count bounds, absent anchor, fractional cadence, independent full-render RGB comparison with and without BWDIF, wrong rendered timestamp, changed source, controller state and late completion, helper failures, cancellation and timeout. Process checks require scanner PIDs to be gone before return. Source hashes and directory inventories verify no preview media or staging files are written.

Twelve research selections and eight integration selections across VFR gaps match independent full-render pixels. Fractional CFR stepping identifies 1001 ticks in a 1/24000 time base. The focused old/new preview run passed 19 tests in 3.553 seconds, including two disabled opt-in resource functions. The final optimized full regression passed 166 tests in 32 suites in 36.439 seconds, with 16 opt-in skips. Existing audio tests are regressions, not new listening acceptance.

A separate enabled 4K resource test passed in 0.729 seconds: current plus replacement pairs retained 99,532,800 RGB bytes; test-helper peak resident memory was 153,468,928 bytes. This is a short generated source and test-helper measurement. It does not include a guarantee about separate decoder memory, native CGImage overhead or whole-film throughput.

## Native walkthrough and hosted gate

The final optimized preview build passed in 13.66 seconds with its ad-hoc signature. On macOS 27.0.1 / Apple M5, the generated VFR source was explicitly opened through the native picker. Native controls set crop top/bottom/left to 2 pixels, right to 6, All frames BWDIF and trim 0.208 through 0.584 seconds. No queue job was created or encoded.

Before rendering, both frame buttons were disabled. Rendering produced original 160x96 and filtered 152x92 at 0.208 seconds. Next moved both to 0.375 across the VFR gap; Previous returned both to 0.208. Another Previous retained the image, reported the first trim frame and disabled only Previous. Editing jump time to 0.58 marked both images out of date and disabled stepping. Rendering selected actual 0.583 seconds. Next retained that image with the last-frame message and disabled only Next. Previous then moved both images to 0.542 and re-enabled both directions.

Accessibility exposed direction-specific button hints, original/filtered image roles, actual times and current/out-of-date state. Screenshot inspection confirmed both images, controls, dimensions, timing and scope text without clipping. The jump field stays separate from stepped actual time and describes that distinction in its hint. Source SHA-256 stayed unchanged; no encoded output or staging directory appeared. Owner spoken and broader platform qualification remain separate.

Hosted macOS regression remains required. Generated research, logs and fixtures remain in ignored local work/frame-stepping. No user media, absolute local paths or binaries are committed.

## Limits

Existing preview support remains explicitly tagged, zero-start, square-pixel 8-bit SDR BT.709 up to the prior raster bounds. Full-source scans and fingerprints may be slow; timeout is an explicit refusal. This is frame stepping in a still comparison, not real-time motion playback, accelerated seeking, compressed-output quality assessment, broad HDR support or all-film compatibility. No audio work, encode-plan change, persistent schema, merge, signing, notarization or release is included.
