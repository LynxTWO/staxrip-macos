# Licensed full-film video evidence
Date: 2026-10-01. Status: Local opt-in qualification underway; no acceptance yet.

## Need and boundary

Slice 039 / D-075 / R-049 exercises the actual user export path against a complete licensed film. Consequence class is user_data through BatchController publication. This is one observed real-film case, not an arbitrary-media guarantee. Source rights/acquisition are recorded in LISTENING-MANIFEST.md and the approved slice; source/media paths and outputs stay local.

The fixed original is Sintel (2010), © Blender Foundation / sintel.org, CC BY 3.0, 681,285,280 bytes, SHA-256 f12c070e295b38cfc94ebd61ac3357c3bac82d1015985f1e8da93a4c6496c46d. A read-only complete decode confirms 21,312 frames at 24 fps, zero start, 1280 by 544, square pixels and yuv420p. Licensed silent derivatives retain the original credits and a local attribution file that identifies video/audio/caption modifications; no endorsement is implied.

## Reproduction

The repository test does not download or bundle media. Ordinary CI leaves it disabled. On a Mac with the reviewed source and FFmpeg available, explicitly set `STAXRIP_FULL_FILM_VIDEO=1`, `STAXRIP_FILM_SOURCE` to its absolute local path and `STAXRIP_FILM_OUTPUT` to an existing local directory with at least 8 GiB available, then run `swift test --filter FullFilmVideoTests`.

Each run creates a private UUID-named subdirectory, local attribution, generated validation SRTs, a protected output sentinel and its own recovery journal. It leaves completed outputs, receipts and failure artifacts for inspection. No owner recovery journal is used by the automated test. Inputs with the wrong digest or size refuse before the export matrix. The three sequential MKV outputs explicitly omit audio and preserve all ten embedded subtitle streams, plus two generated validation tracks with early/middle/late cues. Generated text is plainly labeled and is not a film translation.

## Checks and limits

The actual queue uses video copy, software H.264 CRF 20 Fast and HEVC CRF 22 Fast. Independent references cover every decoded frame's timestamp/raster/pixel format and the complete decoded bytes of all 12 subtitle tracks, along with supported order/language/title. Copied video additionally compares the full decoded-picture SHA-256. Per-frame tolerance is fixed at 0.001001 seconds and never accumulated. Exactly 21,312 increasing frame timestamps are required. Output track counts and absence of audio are checked separately. Source fingerprint and generated/prior-file bytes remain protected; owned staging must be absent after completion.

One 15-minute whole-case deadline bounds the sequential run. Each tool's captured output is limited to the existing 4 MiB maximum; subtitles to 1 MiB per track. A result with truncated output or a nonzero tool exit fails. Each output must be smaller than 2 GiB after export; this is not an in-flight disk quota. Per-output receipts record complete frame and caption counts, maximum timing difference, output bytes, pipeline time, tool/system identity and the copied-picture hash where applicable. Pipeline time includes application checks and publication, not just encoder throughput. Error/cancellation joins the owned batch before propagating failure and leaves its artifacts local.

The first compile confirms only that the opt-in test builds and is disabled by default; it is not film acceptance. Actual local matrix, native walkthrough and ordinary full local/hosted regression remain pending. No audio listening/processing, A/V synchronization, visual quality, calibrated HDR, arbitrary player, feature-length live-action or release claim is made.
