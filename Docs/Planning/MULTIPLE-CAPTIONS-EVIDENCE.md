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

Ordinary local tests at fabcb61 passed all 263 tests in 61 suites in 212.481 seconds. Hosted run 36874248554 failed before tests: Swift 6.1 could not type-check the enlarged EncodePlan return expression, whereas local Swift 6.4 compiled it. The summary, title snapshots and expected codec are now separate typed values with identical behavior. At c386a77, the optimized build passed in 16.75 seconds and the ordinary local command passed all 263 tests in 61 suites in 206.244 seconds. The only product change from the native walkthrough is that behavior-preserving expression split. Hosted run 36874754310 failed only the new second-caption cancellation-entry guard. The planning audit has zero findings across 41 selected documents. Existing full regression includes unchanged numerical audio checks; no owner listening or audio-processing changes are included. Filesystem waits, permanent access permissions, arbitrary subtitle formats, default/forced selection, styling, broad embedded-label/player behavior and real-media qualification remain open.

## Snapshot worker diagnosis and correction

D-071 diagnostic hosted run 36876558655 reproduced that guard failure: source/caption/tool workers entered promptly, both caption reads entered by 9.391 seconds, but encoding had not begun when the guard expired at 16.445 seconds. Cancellation settled at 55.395 seconds. The same runner's focused case passed in 0.313 seconds. No test deadline or full-suite scheduling was changed. The local diagnostic full command passed 263 tests in 205.723 seconds.

D-072 isolated the intervening SubRip snapshot writer, which still used shared utility dispatch. A fixed bounded CPU-load probe against the actual writer failed its one-second entry expectation at 2.99791775 seconds. Replacing only that dispatch with an operation-owned queue preserving task priority passed the same probe at 0.000028958 seconds; both runs joined the same three-second load and verified written bytes/exclusive creation. A separate controlled writer gate checks that cancellation cannot finish until the owned writer is released and settled, and pre-cancellation creates no file. The opt-in probe remains under `STAXRIP_CAPTION_SNAPSHOT_STRESS=1`; a DEBUG-only boundary hook supports it without normal logging.

Temporary phase traces and the additional hosted diagnostic step are removed. Final plain local/hosted regression for the worker repair is pending. This corrects a demonstrated dispatch backlog, not arbitrary filesystem system-call cancellation latency. No unrelated chapter writer, audio processing, generic process runner, deadline or ordinary scheduling policy changed.
