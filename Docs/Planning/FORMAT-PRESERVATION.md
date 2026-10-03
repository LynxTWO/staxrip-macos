# Format preservation and conversion sequence
Date: 2026-10-03. Owner direction: support formats properly, preserve original information whenever possible, and disclose unavoidable losses. Private encoding-test names and paths never belong in code or public evidence.

## Semantics

Container remuxing can preserve elementary streams without decoding. Re-encoding HEVC as AV1 is a codec conversion; original encoded bytes and metadata are not preserved by a generic lossless-pixel setting. A Dolby Vision to HDR10+ conversion has no assumed one-to-one equivalence: metadata must be derived and validated for the resulting pictures and the lost Dolby-specific information must be explicit. No format label substitutes for verified behavior.

Dolby Vision Profile 7 has a base layer, enhancement layer and dynamic metadata. The configuration record alone does not distinguish MEL/FEL. Converting to Profile 8.1 while discarding enhancement data must never be called complete Profile 7 preservation. Original compressed audio is the preservation choice for TrueHD/Atmos and DTS:X; channel-based AAC/Opus/FLAC cannot claim preservation of their object metadata.

## Implementation sequence

1. Slice 046: accurate declared HDR/audio inspection and conversion consequences, with specific refusals.
2. Qualify AV1 stream copy between MP4 and MKV using complete packet/configuration comparisons, decoded 8/10-bit pictures and presentation timing. Keep color intent explicit; no blanket high-bit-depth bypass.
3. Qualify HDR10/HLG/Dolby Vision original-video preservation. Capture and compare complete relevant configuration and packet data, including enhancement/RPU information, rather than dropping unknown side data. Missing scan declarations require an appropriate copy boundary, not guessed progressive labels.
4. Add complete original audio and embedded-caption payload verification, track identity/roles/layout and timing comparisons. Per-track copy plus optional compatibility encodes needs a separate saved-intent migration and native review.
5. Extend static HDR10 encoding to qualified chroma placements and missing-header scan cases using decoded evidence. Retain mastering/content-light metadata when appropriate; preserve placement or perform verified resampling, never relabel pixels.
6. Explicit HDR10 base-layer extraction and HDR-to-SDR tone mapping with clear loss statements, bitstream/decoded-level checks and calibrated reference viewing.
7. Dolby Vision re-encoding into qualified supported profiles/codecs: actual enhancement processing where required, per-frame RPU alignment through edits, correct container signaling and reference playback. Decoder/encoder capability and licensing may limit this path.
8. Research Dolby Vision to HDR10+ as a distinct metadata-generation workflow with resulting-picture analysis, scene validation and reference viewing. Do not promise equal rendering or losslessness.

Each step gets a bounded Scaffold Kit 0.4 brief and acceptance evidence before becoming advertised support. Generated synthetic fixtures go in tests; licensed/private real-media qualification remains local and anonymous. Full-film scans, failed verification, cancellation and exclusive publication remain required where the existing contract calls for them.

## Primary references

- [FFmpeg stream copying](https://ffmpeg.org/ffmpeg.html#Streamcopy): copies packets without decoding, filtering or encoding.
- [dovi_tool conversion modes](https://github.com/quietvoid/dovi_tool#conversion-modes): Profile 8.1 conversion and enhancement discard are explicit operations.
- [x265 Dolby Vision options](https://x265.readthedocs.io/en/master/cli.html): supported profiles and RPU input differ from arbitrary Profile 7 preservation.
- [Dolby Atmos](https://professional.dolby.com/tv/home/dolby-atmos/): objects have placement/movement metadata beyond channel count.

## Current evidence and limits

Local private-source assessment found 10-bit UHD HEVC/PQ/BT.2020, Profile 7 with base/enhancement/RPU declarations, top-left chroma, TrueHD/Atmos plus AC-3, text/PGS captions and chapters. Short beginning/middle/end decoded samples contained static mastering/light and Dolby metadata. That is sampling, not full-film or reference-display acceptance. No source or journal changes and no filenames were committed.
