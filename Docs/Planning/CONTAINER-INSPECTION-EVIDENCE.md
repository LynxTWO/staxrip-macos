# Chapters and attachments inspection evidence
Date: 2026-09-30. Scope: Slice 010, D-023. Status: Focused, regression and native checks passed; hosted check pending.

## Behavior and sources

The native inspector adds Tracks, Chapters and Attachments sections. The existing probe requests chapter metadata and retains optional identifiers, timestamp strings, tick/time-base fields and tags. Attachments and attached pictures are separated from ordinary tracks for display; the existing first non-cover-art video selection is unchanged. Missing filenames/types stay Unspecified; missing titles stay Untitled chapter. No embedded payload is extracted, rendered, registered as a font, or opened through a tag-derived path.

FFmpeg's [ffprobe documentation](https://ffmpeg.org/ffprobe.html) describes chapter sections and distinguishes attachment streams from attached pictures. Its [metadata format documentation](https://ffmpeg.org/ffmpeg-formats.html#Metadata-1) defines the chapter/time-base representation used for generated fixtures. Local spikes at FFmpeg 9.0.2 confirmed a chapter-bearing MKV with text attachment and an MP4 with cover artwork.

Presentation retains duplicate reported identifiers using independent positional row IDs. It shows at most 200 rows per section and states the full count and limit. New metadata labels are bounded to 512 Unicode scalars, control characters are replaced, and shortening is labelled. Missing/nonfinite/overflow-scale timestamps are Unavailable, never zero. Reversed timing, negative starts and chapter ends beyond reported duration are noted. These are reported times, not verified frame locations or a chapter-preservation audit. Probe output remains bounded at 4 MiB and truncation is refused.

Inspection request generations protect result, error and busy-state updates. Superseded or cancelled old requests cannot replace the current source's result. Starting an inspection without tools clears the previous source's metadata.

## Focused receipts

Four ContainerInspectionTests passed in 0.353 seconds. Cases cover missing/invalid times, duplicate IDs, timestamp rollover, control and long text, 201-entry bounds, attachment/cover-art classification and untrusted filename labels. A real generated MKV reports two Unicode-titled chapters at [0,0.5] and [0.5,1] seconds plus notes.txt declared text/plain. Production probing left source bytes and directory contents unchanged. A generated MP4 reports a separate PNG cover-art stream while the main H.264 video remains index zero; its source bytes also stayed unchanged.

An overlapping controlled-probe test starts an old slow request, starts a newer one, then cancels the old request while the newer is still busy. The old completion cannot clear busy state or publish an error/result. The newer chapter result remains visible, and a later unavailable-tools attempt clears it. This is process cancellation evidence, not a network-filesystem guarantee.

The four existing VideoInspectionTests passed in 0.098 seconds with their generated SDR/PQ/HLG metadata cases. They retain the earlier encoding-policy boundaries. No output routing or preservation behavior is changed by this slice.

## Regression and native receipts

The release regression passed 113 tests in 21 suites in 9.127 seconds, with 14 existing opt-in skips. The optimized ad-hoc build passed. Subsequent UI-only refinements were rebuilt and checked natively; the final build completed in 10.78 seconds. The section picker now has one accessibility label, verified after a full app restart.

Native inspection on macOS 27 / Apple M5 exposed a SwiftUI lazy-view identity issue: switching from Tracks to Chapters reused the first track card. Giving the scroll view an identity tied to the selected section fixed it. Repeated Tracks/Chapters/Attachments transitions then showed the correct cards and reset scrolling. Both Unicode chapter titles, start/end times, identifiers and time bases appeared in the accessibility tree and screenshot. The embedded file showed notes.txt and text/plain with codec Unspecified. No payload was opened.

A separate MP4 correctly showed one movie track, zero chapters and one Cover artwork entry with PNG codec and unspecified filename/type. A plain MP4 showed explicit zero-chapter and zero-attachment states. Escape dismissed the sheet. All three generated source hashes, recovery journal bytes and fixture-directory names were unchanged across the walkthrough. Local native-before.json and native-after.json retain the receipts without committing personal paths.

## Remaining validation and limits

Hosted product check passed at 087adcc: run 36713752263, job 109882151161, completed 2026-09-30 at 12:29:37 UTC in 9m37s on macos-15-arm64 / Swift 6.1.2. This is automated coverage, not native qualification on that platform. Chapter editing, seeking, retiming, attachment extraction, output-preservation checks, owner spoken VoiceOver and broader platforms remain open. Audio listening stays parked.
