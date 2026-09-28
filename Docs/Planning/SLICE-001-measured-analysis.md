# StaxRip Mac Slice 001: Measured analysis report
Version: 0.1 Draft. Date: 2026-09-28. Status: Done with evidence.

SLICE STATE
Milestone: M3 complete within the documented mono/stereo measurement boundary.
Blocked by: None for this slice. Broader accessibility/platform qualification remains release work.
Evidence so far: MAP-EVIDENCE.md and SIGNALFORGE-REUSE.md.
Last audit: 2026-09-28; see AUDIT.md.

## 1. What the slice proves

A user can inspect trustworthy full-programme and manually selected speech-region measurements before choosing processing. This is the first slice of the production completion plan, not the application's first feature. If users cannot understand and trust this report, automated gain planning should not proceed.

## 2. The walkthrough

1. Open local media in the native Audio Lab and choose a mono or stereo stream.
2. Optionally mark and edit speech intervals; the UI labels them user-selected, not detected or isolated dialogue.
3. Analyze with real progress and cancellation. Read integrated LUFS, LRA, momentary/short-term plots, peak method and per-channel diagnostics. Silence or insufficient duration displays an unavailable reason.
4. Inspect differences between programme and selected-region results without applying gain.
5. Save a versioned local report to a new path, reopen it, and see the same results with source/algorithm provenance. If the source changed, reanalysis is required before future processing can use it.

## 3. In scope, with build order

| Milestone | Contents and exit |
| --- | --- |
| M1 | One working day maximum for SignalForge reuse/dependency investigation, fixture rights/manifest, numerical conventions and streaming feasibility. Choose Swift adaptation or Rust bridge, document notices and sample/channel/timebase rules before M2. If unresolved, revise the brief. |
| M2 | Streaming meter adapter, AnalysisReport v1, explicit unavailable values, cancellation and known-answer/cross-meter tests. No whole-film PCM allocation. |
| M3 | Native report workflow, editable manual intervals, local save/reopen, error handling, accessible walkthrough and bounded full-film profile. |

R-006 authorizes only the fixture and comparison harness needed for this report. Preserve source notices and pin reused code/dependencies. Interval measurements must document whether windows are included or separately reset; do not join gaps and call the result continuous dialogue. Define that convention in M1 and test interval edges.

## 4. Out of scope, on purpose

| Excluded | Later seam | Decision |
| --- | --- | --- |
| Automatic speech model, source separation, new gain control | DialogueRegions and GainPlanner | D-003, D-004 |
| 5.1/7.1 mastering and object audio | Explicit ChannelLayout renderer | D-005 |
| HDR preservation/tone mapping | ColorPlan | D-005 |
| New release packaging, runner registration and notarization | Production qualification | D-007 |
| Whole SignalForge UI/database/music-reference workflow | No required seam | D-010 |

## 5. Stubs and their debts

No stub inside this workflow. Automatic speech remains unavailable, with manual selections labeled honestly until D-004 closes. Existing FFmpeg mastering stays available with its existing labels; this report does not silently replace it. D-003 records the later integration obligation.

## 6. Modules touched

AnalysisCore (new narrow module or service), meter bridge if M1 selects it, AudioAudit/AudioController, AudioLabView, report persistence and named tests. Existing ToolRunner/decoder adapters may gain only the bounded PCM streaming interface needed here. No session schema, queue semantics or mastering filter changes.

## 7. Data subset

AnalysisReport v1 from EDD section 5, integer-sample manual regions, source fingerprint and measurement backend identity. Validate sample rate, channel layout, region bounds, finite samples, schema version and source replacement. Preserve unavailable measurements in serialization. Reports are local, atomically saved without replacement and deleted only by user action. No older report schema exists to migrate; reject future unknown versions explicitly. Existing session compatibility is unchanged.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S-001 | Supported official mono/stereo fixtures meet their published tolerances, with no missing fixture counted as passed | Manifest/checksums, expected values and observed numeric results | meter-conformance |
| S-002 | Independent backend comparison agrees within preregistered tolerances; chunk partitions yield equivalent results; silence, sub-window duration, NaN and unsupported layout produce explicit states/errors | Generated fixtures and two backend identities; M1 fixes numeric tolerances before implementation | meter-crosscheck |
| S-003 | Native user completes the report flow, edits mistaken speech selection and reads its manual provenance; keyboard and VoiceOver expose controls, units and status | Recorded core/accessibility walkthrough | analysis-ui |
| S-004 | Save/reopen preserves fields and unavailable states; changed source, future schema and existing destination cannot be silently accepted or overwritten | Round-trip, source-change, hostile-report and collision tests | analysis-report |
| S-005 | Cancellation, missing decoder and read/disk failures produce recoverable errors and no source/previous-output changes | Generated long stream and fault-path tests | analysis-cancel |
| S-006 | Two-hour 48 kHz stereo analysis meets D-009 or records an approved target revision before completion; progress represents actual work | Peak-memory, elapsed-time and cancellation records on named Mac | analysis-performance |

M1 must fix tolerances and source-identity policy in this brief before M2; no post-hoc widening to pass results. Public logs exclude source paths. All EDD section 4.4 principles apply; this slice makes no listening-quality or gain-improvement claim.

## 9. Verification evidence required

Tests and source revision for each S-ID; official fixture availability explicitly checked; independent backend identity; core walkthrough and top two errors (unmeasurable input and interrupted operation); redacted performance record; existing Swift suite regression result. Reuse tests are supporting material, not proof that the adapter works. No new broad benchmark service or observer beyond R-006.

## 10. Agent guardrails for this build

Planning, implementation and verification remain separate checkpoints. Stay within sections 6 and 7. M1 can inspect and benchmark the two scoped candidates after approval; a dependency choice is documented with license/build consequences before integration. New unrelated dependencies, schema changes, scope expansion or release effects require a revised decision. Preserve user media and local work. Never run a private fixture or credentials through public CI.

## 11. Slice definition of done

All S-IDs have evidence; unavailable and error behavior is truthful; no temporary bypass remains; EDD definition of done holds; decision/status documents reflect observed results; Daniel completes and approves the native walkthrough. A green generic test job is insufficient if a named gate is missing.

## 12. What this unlocks

Dialogue-aware stereo gain planning can consume a trusted report. The next brief can evaluate local speech detection and compare Smart and Night settings through measured output and level-matched listening. A proposed 3 LU Night target is a listening hypothesis, not a universal fatigue threshold.

Approved for build by: Daniel Boyd, 2026-09-28. Explicit approval recorded in the project conversation.

## M1 decision and fixed numerical contract

2026-09-28: choose a focused Swift adaptation of SignalForge's K-weighting, integrated gates and four-phase 12-tap peak filter, preserving its MIT notice. Rust analysis currently pulls core/audio, decoding, FFT and resampling dependencies; its sequence API lacks LRA/traces and a C ABI. A bridge would require extracting the same small core plus new packaging/ABI maintenance. No Rust build-speed claim was measured. The Swift candidate will be profiled before this slice closes.

Input: explicit mono or stereo, source rate 44.1/48/88.2/96/192 kHz, decoded interleaved Float64 PCM; no downmix, normalization or user output settings. Unknown channel layouts are rejected unless the user explicitly declares mono/stereo matching the decoded channel count. That declaration is recorded in the report. Legacy EBU PCM WAV files require this explicit declaration. FFmpeg codec-default metadata/DRC behavior is reported, never claimed disabled globally. Each manual interval resets meter/filter state and is reported separately; gaps are never joined. Source identity is whole-file SHA-256 checked before and after analysis, not a path or metadata tag. Paths are omitted from saved reports.

Integrated windows: 400 ms / 100 ms hop, -70 LUFS absolute and -10 LU relative gates. Trajectories: 400 ms and 3 seconds at 20 ms cadence; LRA uses 3-second windows at 100 ms cadence, -70/-20 gating and nearest-rank 10th/95th percentiles, plus 1.5 seconds terminal silence for file LRA only. No partial window is labeled a complete measurement. Peak: four-phase 12-tap estimate plus original sample maxima and filter tail. Double precision adaptation; no sentinel for silence.

Fixed tolerances: official integrated/momentary/short-term cases 0.1 LU (or the fixture's explicitly published tolerance), LRA 1 LU, true peak -0.4/+0.2 dB around nominal; independent generated-tone FFmpeg comparison integrated 0.15 LU and peak 0.2 dB, LRA 1 LU. Chunk partition differences at most 1e-9. True-peak method limitations and backend identity remain visible. M1 test acquisition uses EBU material only locally for internal research with copyright credit and no redistribution; missing files are an unmet gate. No superiority claim follows.


Implementation checkpoint: M1 selected the Swift adaptation and fixed tolerances before code. Official EBU v5 fixtures were acquired locally via the browser after command-line downloads returned HTTP 403. The first supported 64-sequence run passed. Saved timeline v1 uses fixed-width little-endian records in a base64 JSON field (frame, presence bits, two Float64 values), preserving unavailable states and precision without hundreds of thousands of JSON objects. The report file limit is 32 MiB. SignalForge's MIT notice is copied into existing development bundles by build.command/package.command; this is attribution for the approved reuse, not a new release workflow. No signing or notarization submission is performed by this slice.

## Functional walkthrough and accessibility refinement

2026-09-28: Daniel confirmed the functional walkthrough passed. He then approved layered VoiceOver guidance: concise labels and values, optional explanatory hints, visible terminology help and useful operation status. This authorizes refinement of the measured-report view and existing preset, encoding and queue controls. No DSP or rendering behavior changes are included. See ../VOICEOVER-GUIDANCE.md. Daniel then confirmed the spoken experience, identified the H.264 pronunciation issue, and confirmed its correction. This closes the owner core walkthrough, with broader voice/settings coverage still outside the tested evidence.

## Closure receipt

S-001/S-002: 64 supported EBU sequences and independent/chunk/gating checks. S-003: native workflow plus Daniel’s functional and spoken feedback, including the corrected codec pronunciation. S-004/S-005: report round-trip/hostile-input/no-overwrite and cancellation/failure tests. S-006: two-hour profile at 106.7 MiB. Details and coverage limits are in MEASURED-ANALYSIS-EVIDENCE.md and ../VOICEOVER-GUIDANCE.md. Hosted checks for commits 9888fd6 and 96f1d38 passed. PRs 13 and 14 remain unmerged; closure records acceptance of the scoped development work, not production release readiness.
