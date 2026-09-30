# External subtitle evidence

Date: 2026-09-30. Slice 015, D-028 / R-018. Status: local, native and final optimized regression passed; hosted acceptance pending.

## Supported contract

One plain UTF-8 SubRip file, at most 1 MiB and 10000 sequential nonoverlapping cues, each at most 4096 UTF-8 text bytes. Known zero-start SDR source, no trim, duration at most 48 hours. Language comes from the exposed list; title is bounded plain metadata. Unsupported styling, escape syntax, line-edge whitespace, malformed timing, special files and final-component symbolic links are refused. Ordinary embedded-track selection remains independent.

Each attempt reads fresh regular-file bytes off the main thread and captures a canonical cue list. The encoder reads only its owned staged snapshot. Before exclusive publication, the added track's codec, language, title, decoded UTF-8 cue bytes and integer-millisecond intervals must match. MP4 uses mov_text for the added track; MKV uses SubRip. Verification has a bounded output and 120-second deadline; cancellation waits for the subprocess to settle before cleanup. This does not guarantee typography, player rendering, default/forced disposition or all embedded subtitle text.

## Automated evidence

17 new test functions across three suites passed in 4.654 seconds. Parser tests cover UTF-8 byte identity (including canonically equivalent but byte-different text), CRLF/BOM, adjacent cues, malformed/styled/overlapping input, exact byte/cue/text limits, source timeline bounds, metadata validation, regular-file freshness, symlink/FIFO/directory/missing/oversize refusal and transient permission exclusion from encoding.

Persistence tests exercise sessions v6 and recovery v5, older/future envelope refusal rules, interrupted recovery, source-specific preset stripping and application, source changes and same-source reload without undo resurrection, while queued copies remain independent.

Real FFmpeg fixtures cover MKV and MP4, selected embedded streams, empty title/unspecified language, changed text/timing/Unicode/extra/missing cues/oversized extraction, staged language/title/codec corruption, original-file mutation after capture, fresh next-attempt reads, stale preflight, verification cancellation, deadline process cleanup and a publication collision. Successful encoder exit alone cannot publish the altered fixtures. Fixture helpers preserve evidence if a batch remains active.

The initial optimized regression passed 142 tests in 28 suites, 15 opt-in skips, in 35.654 seconds. The initial optimized preview build passed. Final session-sheet changes receive a separate full regression and native check below. Logs and generated media are in ignored local `work/external-subtitles`; generated media are not committed.

## Native export walkthrough

On macOS 27.0.1 / Apple M5 with FFmpeg 9.0.2, the native workspace selected the generated one-second 160 × 96, 24 fps, audioless SDR source and an explicit generated output folder. Caption picker cancellation preserved the prior state. Selecting multilingual SRT, French and a title worked with embedded tracks explicitly removed. A queued MKV job was edited using the nested native caption picker: cancel retained its original file; selecting an alternate Arabic/Hebrew/emoji/decomposed-accent fixture changed only that job. The MP4 job retained the original multilingual workspace file. Remove reference and Undo left queued copies intact.

Check queue reported two passing jobs with one and two captured cues. Both jobs reached Completed and displayed verified caption text/timing results. Independent ffprobe checks confirmed SubRip/MKV and mov_text/MP4 with the expected French language and separate titles. Independent extraction matched timestamp strings and cue text bytes exactly; only trailing blank SRT separator newlines were ignored. SHA-256 of the source and both original SRT files stayed unchanged. Native session saving succeeded.

The initial accessibility tree duplicated the language label and full path. The final view gives the filename a complete static-text accessibility label, keeps the full path visible without repeating it in the accessibility text, and uses the language picker's own label. The final native tree read “External SubRip subtitle file, multilingual.srt” and a single language label. This is accessibility-tree inspection, not a new owner VoiceOver listening sign-off.

Session reopen then exposed an existing standalone modal panel visibility problem: the main window stayed visible and File commands were disabled without a visible chooser. The brief was amended and committed before replacing session save/open and replacement confirmation with attached sheets. General source/destination/preset panel conversion is outside this slice.

## Limits and remaining acceptance

Final native session restoration/cancellation and accessibility inspection passed. The attached open chooser and replacement confirmation each cancelled without changing the demo workspace; accepting restored the generated source, both queued caption references and their independent settings without starting encoding. Saving through the attached save sheet produced a JSON document structurally identical to the original session. The session-sheet optimized regression passed 142 tests / 28 suites in 35.846 seconds. A subsequent Unicode title change-detection regression first failed against the old equality with four issues: unchanged session/queue identity and broken Undo. Comparing title UTF-8 bytes fixed it; the final optimized regression passed 143 tests / 28 suites, 15 opt-in skips, in 36.069 seconds. Final ad-hoc preview build: 13.49 seconds. Scaffold audit: 0 findings / 18 documents. Initial hosted macOS run 36783897395 passed at bb9a765: Swift 6.1.2, 142 tests in 500.428 seconds, job duration 9m37s. Final Unicode-title/accessibility follow-up hosted acceptance: pending. Owner listening remains parked. No audio feature, signed artifact, notarization, merge or public release is part of this result. Other supported OS/CPU versions, slow/removable/network media, broad subtitle corpora, styled/multiple/trimmed/HDR captions and durable file-access bookmarks require separate work. A restored path is intent, not a promise of filesystem access.
