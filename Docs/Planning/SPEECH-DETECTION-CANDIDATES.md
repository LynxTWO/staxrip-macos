# Speech detection candidates

Research note, 2026-09-28. Suggested by the owner during Slice 002. Read-only research; no model or runtime installed. Automatic detection remains a later slice, following the current manual-speech mastering validation.

## Silero VAD

The [official upstream README](https://github.com/snakers4/silero-vad) reports MIT licensing, no telemetry or registration, a roughly 2 MB JIT model, and less than 1 ms per 30+ ms chunk on one CPU thread. These are upstream claims, not measurements of our app or this Mac. The ONNX artifact and inference runtime have their own sizes; a 2 MB model does not imply a 2 MB app dependency. Supported evaluation sample rates are 8 and 16 kHz. Review the pinned release and its [license](https://github.com/snakers4/silero-vad/blob/master/LICENSE) before integration, avoiding unrelated forks.

Proposed evaluation: use a 16 kHz analysis copy to propose intervals while measuring loudness on the original-rate decoded channels. Keep recurrent state separate per channel/file, preserve timeline offsets, and test channel combination rules, especially phase-opposed stereo and centre-channel speech. Do not sum channels blindly. Speech-present confidence is not isolated-dialogue loudness: music and effects remain in the measured mixture.

Benchmark full-file wall time, peak RSS, CPU, cancellation, runtime/package footprint and offline operation on Apple silicon. Compare proposed regions with manually labelled speech, including whispered dialogue, breaths, singing, crowd noise, speech over music/effects and at least two languages. Record false positives and missed speech, not just throughput. Use held-out clips and pin thresholds before final evaluation. Keep user corrections available; uncertain detections must not silently become gain authority.

Silero is the first candidate, not yet a selected dependency. A lightweight non-neural baseline can establish whether model complexity buys enough accuracy. Investigate heavier speech separation only if mixture loudness proves inadequate; separation introduces a different distortion and validation problem.

Related storage question: WAVPACK-STAGING-EVALUATION.md records the owner-requested compressed-cache benchmark. Model detection and cache optimization remain separate from mastering quality acceptance.

## Midnight direction from owner discussion

The owner proposed dynaudnorm-style smooth local levelling, improved with full-file speech analysis and coordinated multichannel adjustment. [FFmpeg's primary documentation](https://ffmpeg.org/ffmpeg-filters.html#dynaudnorm) describes 500 ms default frames, a 31-frame centred Gaussian window, optional RMS targeting and default channel coupling. Its single pass still buffers future frames. Use it as a named comparison, not evidence that any new algorithm is superior.

Proposed later design: measure channels independently, keep related channel pairs linked, and allow bounded dialogue-related changes only after establishing what the mix contains. Centre-channel content is not necessarily isolated speech. VAD gives speech presence, not transcription or separation; speech-window LUFS measures the mixture. Suppressing competing sounds within the same channel requires another method and artifact evaluation. Preserve an unchanged original for every render attempt. Treat 2 to 3 LU as a listening-test hypothesis alongside transient limits, not a guarantee of intelligibility or low fatigue.

This direction is recorded for the later DialogueRegions/ChannelLayout briefs. Slice 002 remains manual-reference mono/stereo with one shared envelope; no model, separator or independent channel normalization is added here.
