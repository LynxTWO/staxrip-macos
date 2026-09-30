# Filtered frame stepping feasibility

Local research, 2026-09-30. Slice 018 activated after Slice 017 hosted acceptance.

The existing preview independently renders matching original/filtered timestamps, uses whole-source fingerprints, retains bounded RGB frames and decodes from the beginning to preserve BWDIF history. It supports explicit-color zero-start square-pixel SDR only. There is no next/previous control; users currently type a time.

Candidate: scan decoded source PTS in presentation order using ffprobe's frame output, keeping only the immediately preceding timestamp, current anchor match and following timestamp. Require positive bounded time base and strictly increasing nonnegative bounded PTS; no average-rate arithmetic, guessed seek or retained whole-film index. Match the anchor rationally, stay inside the trim interval, stop the helper after the needed neighbor has been observed and await its actual exit. Missing/duplicate/backward timestamps or an absent anchor are explicit refusals. Overall operation remains cancellable and time-bounded.

Then render the chosen neighbor through the existing full-history comparison. A request just before the selected timestamp avoids a decimal-text boundary rounding upward; independently require both rendered stamps to equal the selected rational timestamp. Fingerprints must bind the prior image, scan and new result to unchanged source bytes. At a trim boundary retain the current verified pair with an explicit first/last frame message, not a silently duplicated step.

Primary references: [FFprobe main options](https://ffmpeg.org/ffprobe.html#Main-options) and [compact output](https://ffmpeg.org/ffprobe.html#compact_002c-csv). show_frames emits decoded frame information; show_entries limits fields; a numeric select_streams targets the inspected video stream. Compact output supplies delimited named fields. Local command uses frame=pts:frame_side_data= and compact=p=1:nk=0. Suppressed side data can still add empty trailing delimiters; do not interpret those as an extra frame.

Generated FFV1 VFR fixture has 24 frames with gaps from PTS 208 to 375 and 583 to 875 at time base 1/1000. A 12-selection spike spanning first/last and both sides of gaps exactly matched independent full-render RGB bytes, with and without BWDIF. Retained results: ignored local work/frame-stepping/spike.json. This proves the selection candidate on generated data, not arbitrary movie compatibility or real-time responsiveness.

Resource/lifecycle design note: during stepping, retain the current pair for boundary feedback while constructing at most one replacement pair. At the existing maximum this is at most 99,532,800 retained RGB bytes across both pairs, excluding decoder and CGImage overhead. Do not claim the old one-pair peak-RSS measurement applies. A generated resource check should measure the new path separately. Keep source fingerprint and actual anchor in the comparison. Stale/cancelled/failed operations cannot re-enable stepping as if a new pair had been validated; first/last boundaries are distinct successful outcomes.

A separate generated H.264 CFR fixture exposes 24 decoded timestamps at increments of 1001 in a 1/24000 time base. Keep fractional-rate identity rational rather than repeatedly adding a rounded interval.
