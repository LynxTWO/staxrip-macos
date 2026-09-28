# StaxRip Mac Slice 002: Reviewed speech and original mastering
Version: 0.1 Draft. Date: 2026-09-28. Status: In progress.

SLICE STATE
Milestone: M1 feedback-planner checkpoint; experimental M3 workflow ready for draft review.
Open gates: D-015 planning-objective review after real-film failures, representative listening acceptance and owner native/VoiceOver walkthrough. Earlier failures remain recorded; they do not prove mathematical infeasibility.
Evidence so far: MASTERING-EVIDENCE.md; MASTERING-M1.md; LISTENING-MANIFEST.md; WAVPACK-STAGING-EVALUATION.md.
Last audit: 2026-09-28.

## 1. What the slice proves

A user can turn freshly measured mono/stereo audio and confirmed speech passages into an inspectable Smart or Night master, audition the result, and save a separately verified lossless file. AnalysisCore connects to GainPlanner, a linked renderer, VerificationReport and native preview. Manual speech is an anchor selected by the user, not machine-isolated dialogue.

This is the next capability after the accepted measurement workflow. Without it, the independent meter remains diagnostic and the existing FFmpeg mastering cannot use the speech selections. No best-in-class or universal listening-comfort claim is part of acceptance.

## 2. The walkthrough

1. Open a supported mono/stereo track. Select Smart or Night and a target reference: Whole programme (default) or Selected speech. Confirm or edit speech passages. Selected speech requires at least one measurable passage and an explicit confirmation that the selection is representative.
2. Enter target LUFS and maximum programme LRA. Read the proposed processing limits, source/decoder identity, selected-reference loudness and the other reference's measured loudness. A spoken hint explains the difference. Targets are not read from dialnorm or other tags.
3. Build a plan. Smart first checks constant gain, then proposes bounded dynamic gain only if needed. Night proposes stronger levelling with separate momentary/short-term excursion ceilings. Show any infeasible constraints and let the user change settings; do not silently relax them.
4. Choose a new destination for FLAC or WAV. Render a full staged candidate, independently measure it, and display before/after values, actual gain bounds and verification results. Show phase progress and Cancel. A failed verification cannot be published.
5. Audition 5 to 60 second excerpts from the full candidate and the same source frames. Choose Original/Processed, with optional level matching for comparison. Playback is initially paused and gain matching cannot cause clipping. Preview never changes exported gain.
6. Save the verified candidate and an optional local processing report. Cancel/discard removes only operation-owned temporary data. A changed source or settings invalidates the plan and candidate. Existing outputs remain untouched.

## 3. In scope, with build order

Defaults below are proposed engineering choices, not loudness standards. Approval of this brief accepts their bounded evaluation, not a claim they already sound good.

| Item | Boundary |
| --- | --- |
| Inputs | Explicit mono/stereo, up to four hours, source rates 44.1/48/88.2/96/192 kHz; no channel conversion or resampling in this new path |
| Outputs | Audio-only 24-bit FLAC/WAV at source rate/layout; existing AAC/Opus and old FFmpeg workflow stay explicitly separate |
| Target | -36 to -9 LUFS, maximum LRA 1 to 20 LU; Smart starting values -18 LUFS / 11 LU; Night -18 LUFS / 3 LU |
| Reference | Programme by default, or combined gated energy from confirmed speech windows; report programme and each passage separately |
| Speech aggregation | Pool valid 400 ms block energies wholly within the chosen regions, with 100 ms hop and per-region reset; apply -70 LUFS absolute then -10 LU relative gating to the pool. Never concatenate disjoint PCM, average LUFS arithmetically, or call this automatic dialogue loudness |
| Gain | One envelope shared by all channels; proposed maximum total boost +12 dB. Silence/low-energy holds prevent adaptive gain from rising merely because the source becomes quieter; constant offset and dynamic boost are reported separately |
| Peaks and excursions | Internal peak target -1.5 dBTP; measured final ceiling -1 dBTP. Night's initial short-term and momentary ceilings are target +6 LU and target +9 LU respectively, applied to the whole programme; measured acceptance tolerance +0.5 LU |
| Targets in conflict | Peak ceiling and source integrity take precedence. If the requested reference, LRA, excursion and gain bounds cannot all pass, return an infeasible result; never substitute another reference |
| Preview | Full staged render first, then time-aligned excerpts with a shared playback position. Reuse the verified candidate rather than render isolated excerpts with different processing history |

| Milestone | Contents and exit |
| --- | --- |
| M1 | At most one working day for the algorithm feasibility spike, after build approval. Fix and record gain smoothing, look-ahead, attenuation floor, noise/hold thresholds, limiting method, latency and deterministic iteration limit before building the renderer. Proposed starting maximum of three candidate renders, then refusal. Prove constant-gain path, speech aggregation, linked stereo and peak-limited feasibility on generated fixtures. If infeasible, revise the brief rather than widen tolerances. |
| M2 | Streaming renderer, immutable plan and independent encoded-output verification. Establish a rights-cleared listening manifest before acquiring dependent media. FFmpeg supplies decode/encode and a named baseline; the original planner and gain application must not just relabel loudnorm. Reuse a licensed limiter if M1 establishes its contract; a new DSP dependency requires a recorded license/implementation decision before integration. |
| M3 | Native planning/results view, staged candidate preview and exclusive publication. Before a costly render, show estimated scratch space and check available space; handle later disk failures honestly. Finish numerical, cancellation, long-file, listening and VoiceOver gates. |

## 4. Out of scope, on purpose

| Excluded | Later connection | Decision |
| --- | --- | --- |
| Automatic speech suggestions, language models, separation | DialogueRegions after manual anchoring passes | D-013 |
| Surround, LFE processing, Atmos, video remux, HDR | ChannelLayout / ColorPlan briefs | D-005 |
| New lossy mastering path | Encoded-output verification after lossless rendering is stable | D-014 |
| Session/queue schema changes, public API, database | Separate persistence/queue integration | D-014 |
| Signing, notarization, merge or public release | Production qualification | D-007 |
| Formal listener study or superiority claims | Broader licensed evaluation | D-014 |

## 5. Stubs and their debts

No stub inside the walkthrough. Automatic suggestions are absent, not represented by a disabled mock result. Existing FFmpeg Smart/Night controls remain a labelled legacy path until migration is tested. New plan/result controls clearly identify the original experimental engine. No reuse of an imported report as trusted gain instructions.

## 6. Modules touched

AnalysisReport/StreamingLoudness for internal window-energy access, AudioController and native audio views, new GainPlanner/LinkedRenderer/VerificationReport/preview service, existing MediaProbe/ToolRunner/ExportPublication, focused tests and documentation. Preserve the meter's published numerical behavior and report v1 readability. Transport changes may stream PCM through bounded buffers or owned local files, never whole-film RAM. Existing video/session/queue execution behavior is outside this boundary.

## 7. Data subset

Fresh internal AnalysisResult contains source SHA-256, track, layout/rate/frame count, decoder policy/version, meter version, valid window energies, manual regions and confirmation. Imported reports remain informational even if the source hash matches; rebuild analysis before rendering.

Immutable GainPlan includes reference kind, requested targets, region confirmation, source identity, parameter/algorithm versions, bounded frame-indexed gain envelope, limiter configuration and expected results. It is process-local and regenerated after edits. No executable filter strings or commands are accepted from a saved report.

VerificationReport v1 is a new internal local JSON format: before/after measurements, per-region results and pooled speech value, maxima, bounds, actual gain statistics, decoder/renderer versions, source/output hashes, frame/layout/rate contract and pass/fail reasons. Exclude source paths and tags. Use a 32 MiB limit, finite-value validation and exclusive publication. Report failure after audio publication must explicitly say audio was saved and allow report retry; do not claim a multi-file atomic save. No analysis-report v1 schema migration or video-session changes.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S2-001 | Fresh analysis required; altered source/settings/regions invalidate candidate. Imported measurements cannot set gain. No measurable selected speech refuses that reference with a recovery path | Generated source mutation, hostile report and absent/silent/short interval tests | mastering-plan |
| S2-002 | Compatible Smart input uses constant gain; output matches the reference multiplication within 24-bit quantization tolerance (two least-significant bits). Pool speech block energies correctly with no cross-gap windows and no arithmetic LUFS average | Known-answer energy tests; unequal-duration passages, silence, transitions, clipping and phase-opposed stereo | mastering-dsp |
| S2-003 | Both modes meet the selected reference within 0.5 LU, programme LRA at most target +1 LU, and independently measured true peak at most -1 dBTP. Night also meets the section 3 excursion ceilings. Infeasible cases do not publish | Decode actual FLAC/WAV output; independent meter plus FFmpeg ebur128 cross-check using slice 001 tolerances on programme and peaks | mastering-output |
| S2-004 | Shared stereo gain preserves interchannel balance; rendered frame count/rate/layout match; latency compensated. Silence remains silence, noise holds do not increase adaptive gain, configured bounds hold at block boundaries | Deterministic generated inputs at five rates, impulses, asymmetric stereo, chunk partitions, boundary steps and long quiet sections | mastering-continuity |
| S2-005 | Preview uses the saved candidate frames and aligned original; matching changes playback only. Toggle/seek stops or crossfades without unexpected level jumps; source controls/settings remain editable after cancellation | Native A/B workflow and frame/latency checks | mastering-preview |
| S2-006 | Cancellation in analysis/render/verify returns control within five seconds; collision, disk/read/decoder failure leaves sources and existing outputs unchanged. No stale candidate can publish | Fault injection and cancellation tests; owned temporary-file checks | mastering-recovery |
| S2-007 | Two-hour 48 kHz stereo analysis, planning, render and verification use at most 512 MiB peak application RSS, with child-process peak and disk usage reported separately. No real-time throughput promise | Fixed generated full-length profile, including preview readiness and bounded render count | mastering-performance |
| S2-008 | Representative listening material has a rights/hash manifest before use. Compare original, peak-safe constant gain, existing FFmpeg baseline and new modes with concealed labels and matched excerpt loudness within 0.2 LU, or mark matching unavailable. Record intelligibility, pumping, transients, stereo image and fatigue separately | Owner listens to at least six 30-to-60-second excerpts covering quiet speech, dialogue/action transitions, music under speech, transient effects, ambience and mixed speaker levels. Include two languages if rights-cleared material is available; otherwise do not claim multilingual validation. Fix audible regressions before acceptance; an owner-only screen is not a population study | mastering-listening |
| S2-009 | Native and VoiceOver users can identify target reference, confirm/correct passages, inspect infeasibility, cancel, audition and save. Announcements preserve focus and avoid progress chatter | Owner core/error walkthrough, keyboard and spoken check | mastering-ui |

S2-008 is a bounded listening screen, not evidence that 3 LU prevents fatigue. All product principles apply: show limits, allow corrections, explain refusal, protect ownership, and use explicit defaults.

## 9. Verification evidence required

R-007 proposes only the tests and local listening comparisons in S2-001 through S2-009. Record source revisions, tool versions, declared-layout/decoder behavior, corpus rights/hashes, gate commands/results, full-length resource receipt and the owner walkthrough. Reuse the established EBU fixture gate if meter internals change. No hosted corpus uploads, new benchmark service or recurring observer. Generated numerical cases cannot replace listening evidence.

## 10. Agent guardrails for this build

Stay within sections 6 and 7. No source overwrite, cloud speech service, silent reference change, automatic model download, public-media redistribution or paid dependency. Existing owner delegation covers reversible implementation choices within the approved brief. Open M1 algorithm and M2 corpus decisions close with recorded evidence before dependent milestones; unresolved scope changes return to the owner. Numerical tolerances are not widened after a failed run. No merge or release is authorized.

## 11. Slice definition of done

All S2 gates pass with receipts, original-engine behavior is labelled truthfully, sources and prior outputs remain intact, documents/unknowns are current, and Daniel completes and approves the native/listening walkthrough. An unattainable target is a valid product refusal, but the required feasible acceptance cases must pass. General regression success is not a substitute for these gates.

## 12. What this unlocks

A later local speech-model spike can compare editable automatic suggestions against the manual reference, then integrate only with validated confidence/coverage behavior. Subsequent briefs can add lossy encoding/remux, surround mastering and HDR preservation. No speech model is selected or downloaded by this plan.

Approved for build by: Daniel Boyd, 2026-09-28. The owner explicitly approved this complete brief in the project conversation.
