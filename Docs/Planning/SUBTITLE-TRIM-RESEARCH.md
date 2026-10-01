# External caption trim feasibility

Discovery on FFmpeg 9.0.2, 2026-10-01, generated media only. The current refusal is correct: a four-cue SRT and a [2,5) selection through global output -ss/-t produced missing and overlong cues despite exit zero. MKV omitted the cue crossing the start and ended the final cue at 4 seconds; MP4 extraction retained inside/final cues at 3.5/4.5 seconds and the final end at 6 seconds. These are actual extracted results, not a documentation inference.

Clipping the source cues to the selected interval and shifting their retained bounds gave [0,1), [1.5,2), [2.5,3). A generated video filtered with trim and setpts, with no global output seek, independently extracted those three ranges in MKV and MP4. This establishes bounded feasibility, not app integration.

A second generated source has PCM audio beginning at 3 seconds. Common-start atrim/asetpts produced a one-second delayed audio track in MKV; MP4 AAC starts at 0.978667 with encoder priming. Decoded sample alignment remains an acceptance requirement, not a claim based only on metadata.

[FFmpeg seeking documentation](https://ffmpeg.org/ffmpeg.html) distinguishes input/output seeking. [The trim and atrim documentation](https://ffmpeg.org/ffmpeg-filters.html#atrim) explains that timestamp bounds and timestamp rewriting are separate operations. Neither promises correct subtitle boundary clipping. We must test the emitted files.

Integration boundaries: ChapterPlan currently writes original source times because global output seek offsets them. This new path requires explicit output-time metadata. BatchController must write the plan-owned transformed snapshot instead of the original captured document; its post-encode verifier must compare that same snapshot. QueuePreflight already constructs the plan, so no-cue and precision refusals can happen before encoding. Existing source identity, fresh per-attempt caption read and exclusive publication remain unchanged.
