# External subtitle feasibility

2026-09-30. Generated-media feasibility and design for Slice 015 / D-028. Research preceded activation; implementation acceptance is separate.

FFmpeg 9.0.2 generated spike: one UTF-8 SRT containing accented Latin, Chinese and multiline text retained exact millisecond cue intervals and text after MKV stream copy and MP4 mov_text encoding, followed by independent extraction to SRT. Source video hash unchanged. MKV stores the requested title in title; MP4 stores it in name. Both retained the requested fra language. MP4 chose a default subtitle disposition, so this first design does not offer a default/forced playback promise.

Negative cases matter: overlapping cues survived MKV but MP4 shortened the first cue to the next cue's start without a failing exit code. Markup/ASS-like positioning and literal backslash escapes changed during conversion/extraction. Therefore a bounded plain-text nonoverlapping SRT contract is needed, with staged-output text and time verification; exit status and stream count are insufficient. Raw spike receipts remain in ignored work/external-subtitles.

Primary references:
- https://ffmpeg.org/ffmpeg.html#Stream-selection (explicit maps, input/output ordering)
- https://ffmpeg.org/ffmpeg-codecs.html (subtitle encoders)
- https://ffmpeg.org/ffmpeg-formats.html (container capabilities)

Proposed boundary: one optional external UTF-8 SRT, <=1 MiB, <=10000 sequential cues, <=4096 UTF-8 text bytes per cue, positive-duration ordered nonoverlapping intervals in integer milliseconds within a known zero-start source duration. Refuse style/position markup, backslash escapes, invalid controls, invalid UTF-8, special files, unsupported timing, trim and HDR combinations in this first slice. Read a bounded regular file off the main actor, using a nonblocking/no-follow file descriptor to avoid opening a FIFO as a normal caption file. Capture and canonicalize once per job; FFmpeg receives an operation-owned SRT snapshot rather than the mutable original. No network protocols or subtitle scripts.

MKV copies SubRip; MP4 explicitly encodes only the added stream as mov_text. Existing embedded-track selection and copied-codec checks remain. UI labels distinguish embedded-track handling from the additional external SRT; the legacy stored Remove all subtitles value continues to mean removing source embedded tracks, with external inclusion explicit under the new schema. Default/forced disposition and player rendering remain separate.

Persist optional path/language/title as source-specific configuration. New sessions v6 and journals v5 reject in older apps rather than silently dropping the external track; new app accepts prior versions without the new field. A legacy version carrying the new field is refused. Reusable presets strip external file references when saved and preserve the current source's reference when applied. A newly loaded source clears its external reference, as it clears track selections.

Before publication, independently extract the staged external stream to bounded SRT using the installed local tool, parse it with the app's bounded parser and require exact cue count, text and millisecond start/end times. Verify codec and supported language/title metadata. Keep existing video/audio/container validation. Check queue validates fresh input without writing; Start reads a fresh snapshot and cannot trust a stale check. Report captured/verified cue count, not a visual-quality or all-format subtitle-preservation claim.

## Mixed embedded and external mapping spike

A second generated test copied one existing subtitle track and appended one external SRT, overriding only the second subtitle encoder for MP4. Both MKV and MP4 produced two subtitle streams and exact additional multilingual cue text/times; the additional language/title remained visible (MKV title, MP4 name). The copied MP4 stream lost its prior name tag, so the new guarantee must explicitly concern the additional external track, not broaden the existing embedded-track metadata contract. Source hash stayed unchanged. Receipt: mixed-selection-spike.json.

Implementation review: ToolRunner returns Data and a truncation flag, so extraction can reject invalid UTF-8 and truncated output before parsing. Keep explicit subtitle-stream index from the output probe; do not accidentally extract the first embedded stream. A source-specific snapshot is captured once per attempt and canonical bytes staged only in that job’s owned directory. File refusal should use nonblocking/no-follow open, fstat regular-file checks and bounded reads, including growth beyond the cap. This does not claim a filesystem-level atomic snapshot under adversarial concurrent writes.

## Plain-text edge spike

Generated adjacent intervals ending/starting at 500 ms round-trip exactly, including an initial cue at zero. Arabic/Hebrew, emoji and decomposed accents also round-trip byte-for-byte in these MKV/MP4 fixtures. Leading/trailing spaces on each line are stripped by extraction in both formats. The first contract should therefore refuse surrounding line whitespace explicitly, not silently strip it or promise its preservation. Receipt: plain-edges-spike.json. Compare UTF-8 cue bytes, not only Swift String equality (which allows canonical-equivalent representations), when claiming exact text preservation.

UI plan: shared external-subtitle controls in Workspace and Queue editor. Use a native file importer that can present from the active editor sheet; the queue access-review presenter’s main-window-only rule is not sufficient for an editor already attached as a sheet. Keep visible embedded-track handling and an additional-file section, language, title and explicit Remove reference action. Store no caption contents in sessions or presets. Verify source-switch/history isolation, including reselecting the same source, so undo cannot resurrect a stale reference after intentional reset.

## Proposed adversarial acceptance matrix

- Parsing: valid LF/CRLF and optional BOM; reject invalid UTF-8, UTF-16, lone CR, missing/sequentially wrong indices, empty text, extra timing attributes, invalid time fields, end-before-start, overlap, markup/ASS/backslashes, controls and surrounding line whitespace. Accept adjacent intervals, multilingual text and combining marks without normalization.
- Bounds: exact cap versus cap+1 for bytes, cues and per-cue text; reject more than 48 hours, malformed source duration and unknown/nonzero source timing. Include FIFO and symlink fixtures to verify refusal does not block the reader.
- Persistence: v6 session/v5 journal round trips; earlier versions without the optional field remain readable; earlier version envelopes carrying the new field refuse; future versions refuse. Imported presets carrying a source-specific reference refuse. Applying a valid preset retains the current source’s reference; new source/reset/demo cannot inherit it, including through undo history.
- Mux: MKV SubRip and MP4 mov_text, with/without embedded subtitles, exact added stream mapping and language/title. Retain all existing codec, geometry and chapter/attachment checks. Added text verification must compare UTF-8 bytes and integer milliseconds.
- Corruption: same cue count with altered text, interval or Unicode representation must fail independently of output existence/encoder success. Missing and extra cues, wrong codec and metadata must also fail.
- Ownership: mutate the original SRT after snapshot capture and demonstrate the captured bytes drive the current operation; a later attempt reads fresh contents. Cancel during inspection/encoding/extraction and collide at publication, proving source, caption and existing destination bytes unchanged and only owned staging removed. Avoid removing a fixture while owned work remains active.
- UI: Workspace and queue editor native file selection (including editor sheet), cancel, add/replace/remove, readable language/title fields, save/reopen, explicit preflight refusal and successful generated MKV/MP4. Verify accessible labels programmatically; owner VoiceOver listening remains a separate gate.

## Native import and permission lifetime

Apple’s fileImporter documentation (https://developer.apple.com/documentation/swiftui/view/fileimporter(ispresented:allowedcontenttypes:oncompletion:)) confirms a system picker, macOS 11 availability, cancellation without onCompletion and security-scoped returned URLs. Local reference: apple-file-importer.md. Path-only storage cannot substitute for a scoped URL’s runtime permission lifetime.

Proposed implementation: the source-specific ExternalSubtitle value has persisted path/language/title only, plus a private optional runtime access holder excluded from Codable and intent equality. The immutable holder retains the selected URL, starts security-scoped access, and balances a successful start on deinit. Copies held by workspace, queue and settings history share the holder; loading a session creates no holder. Reading uses the retained URL only when its standardized path matches the saved intent. A false start result is not itself an error in an unsandboxed app; actual bounded read determines access. No bookmark or credential is persisted. Preset recipes strip the entire external reference. Selecting the same file again through the editor refreshes current-run access without pretending the session has durable permission. This also avoids a process-global unbounded permission cache. Native testing still must establish presentation from the queue editor sheet; docs alone do not prove that UI behavior.

Keep existing queue source/destination review unchanged for this slice; external access is reviewed by selecting the file again in the source-specific editor. Do not add a separate external review action that loses the scoped URL immediately.
