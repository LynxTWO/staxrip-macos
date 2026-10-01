# Ordered external caption evidence
Version: 0.1. Date: 2026-10-01. Status: Native/focused verification passed; final regression pending.

## Scope

Slice 038, D-068 / D-069 / D-070 / R-048. Up to eight ordered plain external SRT tracks under the existing SDR/timeline guards. Generated fixtures only; no audio listening, broader embedded-label/player certification, merge or release acceptance.

## Focused verification

Nine new tests in two suites pass locally. Six actual MKV/MP4 transcode/trim/video-copy cases independently decode both added streams and check order, language, literal UTF-8 title, cue text/timing and custom chapters. Two maximum-eight-track exports independently decode every track, including titles containing composed/decomposed accents, delimiters and a final backslash. Five later-track refusal cases cover altered text/title, missing output stream, missing second file and an empty second trim intersection; publication stays absent, the next job Pending, originals unchanged and owned staging removed. Cancellation inside the second stream verifier joins its recorded process before cleanup. A second-track source mutation after capture affects only the next attempt; both attempts retain the independent first track.

Intent checks cover old/new envelope boundaries, invalid/duplicate/excess/orphan references, presets, undo/redo, missing/reordered/extra snapshots and chapter/input/output ordinals. Native picker intent refuses stale source/list changes. Title files preserve literal bytes, have 0600 permissions and refuse existing files/symlinks, oversized/count-invalid input and an already-cancelled task. Existing single-caption tests remain intact except explicit current/future envelope version expectations.

## Failed experiments and bounded corrections

- A synthetic plan fixture initially lacked the required 8-bit pixel format; the fixture was corrected without relaxing the SDR guard.
- Passing an accented title directly through Foundation.Process decomposed its UTF-8 bytes. A direct Swift-to-child argument experiment isolated the normalization. The strict output comparison correctly refused it.
- D-069's FFmetadata stream-section prototype avoided argument normalization but a title ending in a backslash consumed the next section boundary. Padding changed the title, so that design was rejected. Explicit stream metadata maps also disabled automatic copying for retained streams. D-070 supersedes both: each title uses a bounded, exclusive literal option-argument file loaded with `-/metadata:s:s:N`; no FFmetadata title parser and no new retained-stream metadata maps remain.
- A stronger generated MP4 check found that the muxer drops the existing embedded subtitle `name` even in a plain independent stream copy. The new test compares this retained label against that control; MKV retains the generated title. Added track titles remain byte-exact acceptance requirements in both containers. This slice does not claim general embedded-label preservation.
- The first ordinary full run reached 263 tests and failed three existing trimmed-caption summary assertions because the new language label interrupted their established phrase. The summary now retains that phrase and appends language afterward. The original assertions/deadlines/default scheduling are unchanged.

Primary reference: [FFmpeg option arguments loaded from files](https://www.ffmpeg.org/ffmpeg.html#Options). Title files contain raw `title=` plus at most 1024 UTF-8 title bytes, no trailing newline and no delimiter escaping. At most eight files/1030 bytes each; the owned writer settles before cancellation returns.

## Native qualification

Optimized build passed in 18.19 seconds. On macOS 27, native pickers added English/French generated SRTs, labels were edited and order changed, a row was replaced with German while retaining its metadata, then removed and added again. Save/reopen retained two references in French/English order. Per-file access review kept the saved list intact. Selecting the first file into the second row refused the duplicate and preserved both existing references; choosing the intended file corrected it. Light/dark layouts and filename/position-qualified accessibility labels were inspected.

The final build's independent queue editor changed only the second queued title; the workspace still read `English access`. The actual MKV export completed with both caption verifications and all 72 original video packets checked. Independent decoding matched both source SRTs and literal output titles, including the queue-only title. Source/session/caption bytes were unchanged, owned staging absent, and the previous recovery journal restored after checking the test job's destination and completion evidence. The generated app was closed normally. Native accessibility-tree inspection is not heard VoiceOver acceptance. Native picker `/var` canonicalization and a broad automation field matcher were resolved by fresh state inspection; neither was a product failure.

## Regression and remaining limits

Final ordinary local/hosted checks and planning audit are pending. Existing full regression includes unchanged numerical audio checks; no owner listening or audio-processing changes are included. Filesystem waits, permanent access permissions, arbitrary subtitle formats, default/forced selection, styling, broad embedded-label/player behavior and real-media qualification remain open.
