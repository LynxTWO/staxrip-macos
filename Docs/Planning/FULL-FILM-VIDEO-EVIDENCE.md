# Licensed full-film video evidence
Date: 2026-10-01. Status: Scoped acceptance at ordinary qualification head 542fde3; production Sources unchanged from 6c471b7.

## Need and boundary

Slice 039 / D-075 / R-049 exercises the actual user export path against a complete licensed film. Consequence class is user_data through BatchController publication. This is one observed real-film case, not an arbitrary-media guarantee. Source rights/acquisition are recorded in LISTENING-MANIFEST.md and the approved slice; source/media paths and outputs stay local.

The fixed original is Sintel (2010), © Blender Foundation / sintel.org, CC BY 3.0, 681,285,280 bytes, SHA-256 f12c070e295b38cfc94ebd61ac3357c3bac82d1015985f1e8da93a4c6496c46d. A read-only complete decode confirms 21,312 frames at 24 fps, zero start, 1280 by 544, square pixels and yuv420p. Licensed silent derivatives retain the original credits and a local attribution file that identifies video/audio/caption modifications; no endorsement is implied.

## Reproduction

The repository test does not download or bundle media. Ordinary CI leaves it disabled. On a Mac with the reviewed source and FFmpeg available, explicitly set `STAXRIP_FULL_FILM_VIDEO=1`, `STAXRIP_FILM_SOURCE` to its absolute local path and `STAXRIP_FILM_OUTPUT` to an existing local directory with at least 8 GiB available, then run `swift test --filter FullFilmVideoTests`.

Each run creates a private UUID-named subdirectory, local attribution, generated validation SRTs, a protected output sentinel and its own recovery journal. It leaves completed outputs, receipts and failure artifacts for inspection. No owner recovery journal is used by the automated test. Inputs with the wrong digest or size refuse before the export matrix. The three sequential MKV outputs explicitly omit audio and preserve all ten embedded subtitle streams, plus two generated validation tracks with early/middle/late cues. Generated text is plainly labeled and is not a film translation.

## Checks and limits

The actual queue uses video copy, software H.264 CRF 20 Fast and HEVC CRF 22 Fast. Independent references cover every decoded frame's timestamp/raster/pixel format and the complete decoded bytes of all 12 subtitle tracks, along with supported order/language/title. Copied video additionally compares the full decoded-picture SHA-256. Per-frame tolerance is fixed at 0.001001 seconds and never accumulated. Exactly 21,312 increasing frame timestamps are required. Output track counts and absence of audio are checked separately. Source fingerprint and generated/prior-file bytes remain protected; owned staging must be absent after completion.

One 15-minute whole-case deadline bounds the sequential run. Each tool's captured output is limited to the existing 4 MiB maximum; subtitles to 1 MiB per track. A result with truncated output or a nonzero tool exit fails. Each output must be smaller than 2 GiB after export; this is not an in-flight disk quota. Per-output receipts record complete frame and caption counts, maximum timing difference, output bytes, pipeline time, tool/system identity and the copied-picture hash where applicable. Pipeline time includes application checks and publication, not just encoder throughput. Error/cancellation joins the owned batch before propagating failure and leaves its artifacts local.

The first compile confirms only that the opt-in test builds and is disabled by default; it is not film acceptance. The native walkthrough and complete final local matrix passed as recorded below; ordinary full local/hosted regression passed as recorded in the closure below. No audio listening/processing, A/V synchronization, visual quality, calibrated HDR, arbitrary player, feature-length live-action or release claim is made.


## First run and bounded format correction

The first opt-in matrix at 2783d19 failed after 566.420 seconds. Copy and software H.264 each independently matched 21,312 frame timestamps (maximum difference zero) and all 12 caption payloads; HEVC encoded but its frame audit was correctly refused as truncated. Full matrix acceptance is not inferred from those partial results. Direct diagnostic capture of the identical HEVC query shows 5,282,761 bytes in ordinary JSON and 3,748,297 bytes in compact JSON, with exact parsed equality across all fields and 21,312 records. D-076 permits only the documented whitespace-format change, preserving the 4 MiB limit and every comparison. See FFprobe's [JSON writer](https://ffmpeg.org/ffprobe.html#json).

The first ordinary hosted run [36895508537](https://github.com/LynxTWO/staxrip-macos/actions/runs/36895508537) at 2783d19 failed one existing Fresh analysis cancellation assertion: 6.796 seconds against the unchanged five-second limit. It ran 267 tests in 583.784 seconds after a 115.32-second build. The full-film test was disabled as intended. This result is retained; it is not a passed regression gate and no audio code, scheduling or deadlines are changed by D-076.

The native walkthrough used the existing optimized product at 6c471b7 (Sources unchanged). Explicitly reviewed source and both generated captions, selected No audio and Copy original, checked and started the queue into a new owned directory. Completed details reported eight chapters, both three-cue added tracks and 21,312 verified copied packets. Independent output checks found no audio, 12 complete matching caption payloads, 21,312 increasing decoded frames with zero PTS difference, 1280 by 544 yuv420p and the identical full decoded picture hash. Output size was 610,211,035 bytes. Source and generated/session bytes stayed unchanged, owned staging was absent and the prior owner recovery journal was restored after verifying the completed job identity. The app closed normally. Native MKV playback remained visibly unavailable; no playback, listening or subjective picture acceptance is claimed.


## Complete final matrix at 2fe44cf

Verified observed_behavior through the existing user_data export path. Explicit opt-in local run passed its one sequential case in 545.545 seconds, within the unchanged 15-minute deadline. Platform: Apple M5, macOS 27.0.1 (26A434), Swift 6.4, FFmpeg 9.0.2. Test source identity is the fixed digest and byte count above; production Sources and hosted workflow are unchanged from 6c471b7. All outputs used a new private run directory and independent recovery journal.

| Output | Decoded frames | Maximum PTS difference | Complete subtitle tracks | Bytes | Application pipeline seconds |
| --- | --- | --- | --- | --- | --- |
| Original-video copy | 21,312 | 0 seconds | 12 | 610,211,035 | 3.585 |
| H.264 CRF 20 Fast | 21,312 | 0 seconds | 12 | 255,512,295 | 111.489 |
| HEVC CRF 22 Fast | 21,312 | 0 seconds | 12 | 146,197,058 | 203.781 |

Every output has one video stream, no audio, increasing complete frame timestamps, 1280 by 544 yuv420p, ten byte-matching decoded embedded SRTs and two byte-matching generated SRTs. Supported stream order/language/title checks passed. Source fingerprint, generated captions and prior-output sentinel remained unchanged; owned staging was absent after each completed output. Copy additionally matched the complete decoded-picture SHA-256: 42204713f85ebb24aa311e83a0214756313576cc8f9ec7a127e485254aca3aa9.

Pipeline timing starts at actual batch launch and includes application verification/publication. It excludes separate preflight and independent reference decoding; the whole-case time includes those checks. These are single-run observations at different quality settings, not matched-quality throughput or compression superiority evidence. Sizes are postconditions, not quotas. Final source/tool/controller/test changes invalidate the corresponding receipts and require scoped requalification. Other platforms, codecs, files and visual/audio claims remain outside this result.

S39-001 film-input, S39-002 film-video, S39-003 film-captions and S39-004 film-native have scoped passing evidence. S39-005 film-regression passed at the ordinary closure below; the historical hold and diagnostic results are retained.


## Ordinary regression hold and bounded diagnosis

Ordinary local swift test at 2fe44cf passed 267 reported tests across 62 suites in 206.658 seconds; 25 opt-in tests, including the separately executed film matrix, were skipped. [Hosted run 36897429716](https://github.com/LynxTWO/staxrip-macos/actions/runs/36897429716) failed the same existing Fresh analysis cancellation settlement guard at 6.248 seconds against five. It reported 267 tests in 630.019 seconds after a 96.81-second build. No other issue was reported. This second failure means S39-005 remains unaccepted despite the local and film successes.

D-077 permits one bounded test-only observation using the existing cancellation case and DEBUG process hook. At most 32 path-free labels identify phase notification, cancellation request/return, process worker entry and task settlement; they print after the unchanged checks. All fixtures, comparisons, deadlines, ordinary scheduling and product code remain unchanged. A third failed ordinary hosted run triggers the reframe stop. The purpose is to identify a lifecycle boundary; no sound-processing, listening or normalizer acceptance follows.


D-077 local comparison at diagnostic head aa7f5bd: ordinary swift test passed 267 reported tests across 62 suites in 205.916 seconds (25 opt-in skips). Fresh analysis recorded the cancel request at 0.259209 seconds, cancel return at 0.259229, task exit at 0.259906 and test result observation at 0.259977 relative to the case trace origin. This local run does not reproduce the hosted delay. The test's original Date-based five-second assertion and file/staging checks are unchanged. A focused comparison also passed all three existing cancellation phases in 24.309 seconds; the final diagnostic build passed without warnings after preserving compatibility for non-DEBUG builds. These observations do not identify the hosted cause or clear S39-005.


The [diagnostic hosted run 36899766961](https://github.com/LynxTWO/staxrip-macos/actions/runs/36899766961) at aa7f5bd passed 267 reported tests in 509.548 seconds after a 78.10-second build. Its trace observed task entry at 4.534595 seconds, target phase at 7.802048, the cancellation callback at 9.544578, cancel request at 9.544638, cancel return at 9.544699, task exit at 9.588910 and result observation at 9.589003. Thus this passing run settled cancellation in about 44 milliseconds; the earlier delay did not reproduce and its cause remains unknown. The trace also shows scheduling delays before the measured cancellation window, which cannot be substituted as the cause of the earlier failures.

The temporary observer is being retired under D-077. OriginalMasteringTests will be restored byte-for-byte to 2fe44cf; production code and all workload/deadline/assertion choices remain unchanged. Ordinary final-head hosted regression is still required. This passing diagnostic is not a claimed cancellation repair. A further ordinary failure invokes the recorded third-failure stop without expanding the observer.


## Ordinary closure and acceptance

Final ordinary [hosted run 36901339753](https://github.com/LynxTWO/staxrip-macos/actions/runs/36901339753) at 542fde3 passed 267 reported tests in 527.517 seconds after a 70.95-second build; 25 opt-in tests were skipped. The complete actual film case ran separately and passed at 2fe44cf. Git comparison confirms Sources, Tests, Package.swift and the hosted workflow at 542fde3 are byte-identical to 2fe44cf, so the ordinary local 267-test/62-suite result in 206.658 seconds and the full-film matrix remain applicable. The temporary cancellation trace is absent. Optimized native product evidence at 6c471b7 remains applicable because production Sources are unchanged.

All five Slice 039 gates have scoped observed passing evidence. S39-001 covers fixed source identity, attribution and protected originals; S39-002 the complete three-output frame/raster/timestamp matrix and copied-picture hash; S39-003 all retained/generated caption payloads and supported metadata; S39-004 the native reviewed silent copy and safely restored prior journal; S39-005 ordinary local/hosted regression, source provenance and a zero-finding selected planning audit across 42 documents. This accepts one licensed-film qualification slice, not the broader program or a universal preservation guarantee.

The two prior ordinary hosted cancellation failures remain unexplained. The later diagnostic and ordinary passes do not establish a repair or reliable five-second settlement under every workload. Repeated failure reopens that lifecycle qualification; do not silently lengthen its guard or expand diagnostics. Owner listening, calibrated HDR, feature-length/live-action corpus, broader platforms/filesystems, software licensing and signed distribution remain open. No merge or release was performed.
