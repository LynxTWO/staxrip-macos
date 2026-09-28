# Loudness mastering: requirements and evidence

The product target is an original offline mastering engine that earns a best-in-class claim through measurement and listening comparisons. The present implementation is a foundation built on FFmpeg loudnorm and linked compression, not that finished engine.

## Two workflows

- **Smart master:** measure the complete decoded programme after the intended channel conversion, accept user LUFS and maximum LRA, prefer constant gain when peak/range constraints permit, otherwise apply dynamic treatment explicitly. Preserve intent and channel relationships. Never invent dynamics merely to reach a requested range: the range is a maximum, not a minimum.
- **Night / Venue:** reduce variation and sudden loud events while retaining enough contrast for comfortable listening. Initial experimental defaults are −18 LUFS and maximum 3 LU LRA, with user overrides. These are engineering starting points, not a loudness standard or a guarantee of comfort. Venue and night listening also depend on speaker gain, background noise and the listener.

The foundation accepts −36 to −9 LUFS and 1–20 LU LRA. Night / Venue applies linked RMS compression before measured dynamic normalization. The final encoded file must meet integrated loudness within 0.5 LU, maximum LRA within 1 LU and true peak at or below −1 dBTP; otherwise it is not published. No acceptance decision is based on metadata alone.

## Standards and distinctions

[EBU Tech 3341](https://tech.ebu.ch/docs/tech/tech3341.pdf) defines metering and test signals. Programme measurement must use BS.1770 channel weighting and gating. The LFE is excluded from standard programme LUFS; inspect it separately rather than adding it to the standard result. The implementation currently audits each decoded channel as mono, which is diagnostic and not additive programme loudness. A synthetic quiet/loud/quiet sequence tests gating behavior, but passing one sequence is not full conformance certification.

[EBU Tech 3342](https://tech.ebu.ch/docs/tech/tech3342.pdf) defines LRA from gated three-second loudness, using the 10th and 95th percentiles. Its relative gate differs from integrated measurement. Isolated loud events can fall outside those percentiles; small LRA therefore does not guarantee an absence of spikes. The future engine must also evaluate short-term and momentary maxima, overshoot, crest behavior and gain modulation, separately from true peak.

[EBU Tech 3343](https://tech.ebu.ch/docs/tech/tech3343.pdf) discusses cinematic dialogue and the programme-to-dialogue difference. Centre-channel energy is not equivalent to speech. User-selected clean dialogue passages provide an auditable first measurement; the current UI measures a selected passage but does not drive gain from it. For representative manual checks, use clean passages across the film. Future automatic detection must be validated for languages, accents, whispers, shouts, singing, off-screen speech, music and effects. Report confidence, coverage and failure instead of inventing dialogue values.

[FFmpeg loudnorm](https://ffmpeg.org/ffmpeg-filters.html#loudnorm) is the current standards-based measurement/normalization backend. Smart mode can fall back from linear to dynamic processing under its constraints. The app remeasures the encoded output. Actual output LRA can differ from the requested filter parameter; verification is mandatory.

## Original engine acceptance plan

1. Implement an independently tested gated meter and time-aligned loudness trajectory. Run the official EBU test corpus and cross-check another implementation; include silence, noise, clipping, intersample peaks, long files, discontinuities, sample rates and channel layouts.
2. Add an offline gain planner with look-ahead, linked multichannel envelopes, bounded gain/slew, noise-floor protection, silence holds and scene-aware transitions. Avoid boosting ambience between dialogue phrases. Keep original and processed trajectories for review.
3. Add dialogue classification with confidence and temporal coverage, plus manual correction. Measure detected speech itself; do not trust dialnorm tags or label all centre content dialogue. Record decoder treatment of metadata/DRC. Keep surround geometry and handle LFE explicitly.
4. Add separate limits for short-term/momentary excursions and a verified true-peak limiter. Repeat measurement after lossy encoding. Reject or explain unattainable combinations.
5. Provide level-matched A/B excerpts, a processing report and measured changes. Blind listening tests must cover dialogue intelligibility, pumping, transient damage, fatigue and spatial image. Compare against unprocessed, constant-gain and established dynamic processors.
6. Validate complete feature films and a licensed multilingual dialogue corpus on several speaker/headphone setups. Synthetic tones validate math, not listening quality. Do not advertise automatic dialogue-aware mastering, multichannel export, certified metering or superiority until those acceptance gates pass.

## Current limits

Export still accepts mono/stereo sources. Channel audits accept up to eight channels and label unknown layouts honestly. Dialogue is manually selected and diagnostic. The adaptive planner, automatic speech detector, independent meter, LFE processing contract, short-term ceiling and listening study are outstanding. Multiple full-file passes cost time. Audio settings are not yet saved in video sessions.
