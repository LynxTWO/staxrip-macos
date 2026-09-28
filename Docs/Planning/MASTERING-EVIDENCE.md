# Original mastering evidence

Work in progress, 2026-09-28. Slice 002 is not accepted or production complete.

## Numerical development

M1 registered its parameters before implementation. Eight focused tests passed in release (7.484 seconds): duration-weighted gated energy pooling, constant FLAC publication and report collision protection, generated 20 dB transition Night output, limiter impulse timing/frame count and peak at five rates, constant PCM multiplication within two 24-bit LSBs, silent/unconfirmed speech refusal and cleanup, linked phase-opposed stereo/noise hold with conflicting-range refusal, and changed-source refusal. Later tests add selected-speech output and phase cancellation; their results must be recorded below before claiming those gates.

The independent cross-check initially used a 1.5-second padded reading for integrated loudness, causing a short constant fixture disagreement. The corrected comparison uses unpadded integrated/peak readings and a separate padded LRA reading, matching the Swift meter's LRA-only tail policy. Tolerances were not widened.

The first complete debug regression passed: 55 tests in 9 suites, 252.339 seconds. Subsequent validation/report/UI refinements require the final regression below.

## Native development walkthrough

Observed in the local ad-hoc preview: select generated stereo FLAC, build fresh constant-gain plan, stage a verified candidate, prepare a 12-second aligned excerpt, start paused, enable level match, play, switch to Processed and stop at the shared 3.9-second position, save audio, save the separate JSON receipt, and edit target to invalidate plan/candidate. Output reference was -18.00 LUFS; independent FFmpeg -18.0 LUFS; output peak -16.50 dBTP. Individual result labels/values are separate accessibility elements. This is agent UI evidence, not the owner's spoken VoiceOver or listening approval.

Visual inspection found unlabeled numeric excerpt fields and an unnecessary native audio placeholder. Visible start/duration labels and explicit spoken labels were added; the placeholder was hidden. Final rebuild and focused inspection remain required.

## Resource and listening gates

The RF64 two-hour release pipeline passed, including a measured 60-second excerpt from the final minute of the original: 352.534 seconds excluding fixture generation, two candidate attempts, 84,393,984 bytes (80.5 MiB) peak test-process RSS, and 27,836,416 bytes (26.5 MiB) peak child RSS. Peak owned disk bytes at phase boundaries: 17,299,054,119 including the 310,091,900-byte generated source; conservative scratch budget 20,179,017,728 bytes. This profiles the engine in the test process, not the complete native app with every UI panel resident. Other local work was active; no real-time throughput guarantee follows. Local licensed corpus preparation is recorded in LISTENING-MANIFEST.md. Neither constitutes passed listening acceptance. The owner must still assess intelligibility, pumping, transients, stereo image and fatigue on concealed-label, level-matched excerpts.

## Remaining limits

Only mono/stereo at the five registered rates. No automatic VAD, isolated dialogue, surround processing, signed release or merge. Reported gain extrema are the actual Swift envelope before limiting; limiter attenuation is additional and not exposed as a fabricated total-gain statistic. Hard termination can leave an owned hidden staging folder beside the selected destination; normal cancel/discard/quit removes owned staging and preserves published hard-linked output.

Long-file inspection prompted RF64 support for WAV staging/exports (`-rf64 auto`): a two-hour float64 stereo original exceeds classic RIFF's 4 GiB limit. The final long-file gate must include an excerpt from the last minute of that original. Long WAV exports can therefore be RF64; players that only support classic RIFF may not open those files.

The native generated fixture output and separate receipt were also checked on disk. Source paths are absent from the receipt. The first real-film default Smart request refused its range constraint after three attempts; see LISTENING-MANIFEST.md for the explicit lower-target feasibility trial. No failed candidate was published.

## Feedback-planner checkpoint

Retained planner: revision 3, 24 bounded energy-feedback iterations before each of at most three actual renders. Internal 20 ms K-weighted energy bins do not change saved report v1. The constant-gain predictor agrees with fresh meter readings in a known-answer test, including a partial terminal bin and exclusion of synthetic LRA padding. Planning runs outside the main actor with cancellation propagation. UI decoding progress is limited to four updates per wall-clock second rather than one update per media second.

Final retained release regression: 62 tests in 12 suites passed in 8.259 seconds after the final UI/cancellation changes. The official EBU v5 gate after the new energy lane passed all 64 supported mono/stereo sequences in 14.345 seconds. These are numerical/regression gates, not listening acceptance. The generated quiet-tail fixture now succeeds within unchanged limits; the former refusal was a limitation of the old planner. Excessive required boost still refuses safely.

The retained film trial failed: Smart -23 LUFS/11 LU request ended at -25.94 LUFS/13.46 LU after three attempts; Night -30/3 ended at -34.26/5.93. Predicted versus actual first-candidate reference/range agreed to about 0.01 LU on this source. No failed candidate was published. Three additional preregistered smoothing/background variants also missed the film preflight and were not adopted. See MASTERING-M1.md for parameters and results. D-015 is open; no complete listening pack or production-ready Midnight claim is justified.

Final retained two-hour resource gate passed: 210.682 seconds excluding fixture generation, one candidate attempt, 99,827,712 bytes (95.2 MiB) test-process peak RSS, 27,934,720 bytes (26.6 MiB) child peak RSS, and 17,286,790,586 bytes peak owned disk at phase boundaries including the generated source. Scratch budget: 20,179,017,728 bytes. The final-minute original RF64 excerpt contained the required 2,880,000 frames. Other local UI/build work was active; this is not an isolated throughput claim or a measurement of every native app panel resident.

Final native cancellation: while decoding a generated one-hour mono source, Escape invoked the dedicated mastering cancel action. The observed state changed to “Cancelled · no output published”, with source and target controls editable, in 749 ms including UI observation. Before an explicit keyboard shortcut was added, Escape did not cancel; accessibility automation also encountered invalidated button elements during progress updates. The final keyboard path is verified; do not claim those earlier attempts passed. Native generated-file staging and paused aligned excerpt building were repeated, with -18.00 LUFS and -16.50 dBTP matching the independent check. Visible excerpt labels and individual accessibility values were inspected. Spoken owner acceptance remains open.

Final visual/interaction check: the native player placeholder is hidden; excerpt start/duration remain visibly labelled. Matched playback advanced, switching to Processed paused at the shared 8.2-second position, and editing target to -19 removed the candidate and changed status to “Mastering inputs changed. Build a fresh plan.” The previous ready message no longer survives invalidation. This used generated audio and establishes interaction behavior, not film listening quality.

## Gain-limit and gate-membership diagnosis

PR #16's macOS CI at a583451 passed in 9m41s. A subsequent opt-in local diagnostic export passed in 6.864 seconds; a separate standard-library Python calculation reproduced the retained Swift predictor's integrated loudness and range percentiles within 0.000001 LU for both film plans. Known constant-energy gain and silence checks passed. Source gate membership would materially understate rendered LRA: 7.68 versus 13.32 LU Smart, and 1.23 versus 5.53 LU Night. Actual metering continues to recompute gates from output.

The registered energy-neutral range-correction experiment passed 12 generated/recovery tests but failed both film preflights: -23.3645 LUFS/15.6372 LU Smart and -30.2166/10.3341 Night. It was reverted; no failed film output was published. Only diagnostics and research records remain from this follow-up. Product DSP, acceptance thresholds and UI are unchanged, so the prior native walkthrough applies to the retained product. These results narrow the planner problem; they do not make the listening pack ready.

Final retained release regression reported 63 tests in 13 suites, successful in 8.665 seconds. Seven opt-in test declarations were skipped, including film preparation, corpus/resource/hardware checks and the separate diagnostic exporter; do not interpret the ordinary suite as a new pass of those gates. The exporter was exercised separately above. Scaffold audit reported zero findings across five recognized planning documents; whitespace checks passed.
