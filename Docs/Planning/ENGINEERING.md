# StaxRip Mac Engineering Document
Version: 0.1 Draft. Date: 2026-09-28. Status: In interview.

INTERVIEW STATE
Last completed: Slice 039 accepted at 542fde3; Slice 002 experimental implementation and local listening pack preserved.
Next: Select the next bounded non-audio capability after the full-film qualification closure; no new slice is active.
Open questions: Software license, platform matrix, audio listening and algorithm acceptance.
Statuses pending: Slice 002 paused by owner on 2026-09-29, not accepted. See NON-AUDIO-RESUMPTION.md.

## 1. One-Page Overview

Protect media first, measure before making claims, preserve explicit user choices. The top goals are correct measurements, recoverable operations and truthful user-visible results. ADD section 15 records the build boundary; the owner has paused Slice 002 for non-audio work. Measurement acceptance is recorded in MEASURED-ANALYSIS-EVIDENCE.md; later mastering receipts are in MASTERING-EVIDENCE.md. Native export cleanup and start-notification hardening passed hosted macOS validation at a69e95b in run 36599311645; the original unlogged removal failure cause remains unknown. Static HDR10 has scoped synthetic preservation evidence; calibrated HDR pictures, broader formats, original mastering and speech models remain unqualified.

## 2. Engineering Principles

1. Source data is immutable input.
2. A tag is not a measurement.
3. An unknown layout or speech result stays unknown.
4. Failed verification prevents publication.
5. New DSP must beat a stated baseline on stated material before superiority claims.
6. Keep signing and public contribution execution separate.

## 3. System Goals

| Goal | Acceptance |
| --- | --- |
| Measurement correctness | Every applicable official fixture within its published tolerance; independent comparison disagreements investigated |
| Recoverable work | Cancellation, invalid source and destination conflict leave source and previous output unchanged |
| Honest analysis | Programme, mono-channel, LFE diagnostics and manual/automatic speech results visibly distinguished |
| Accessible operation | Import, select, analyze, cancel and save-report flows usable by keyboard and VoiceOver |
| Local privacy | Processing requires no upload; report sharing redacts identifying paths by default |

## 4. Requirements Ledger

### 4.1 Confirmed requirements

| ID | Requirement | Acceptance |
| --- | --- | --- |
| R-001 | Native Mac product | Real native core walkthrough, not a web mockup |
| R-002 | Two measured mastering workflows | Smart and Night have explicit targets and measured encoded results |
| R-003 | Dialogue and all relevant channels considered | Actual speech/channel measurements with documented weighting; no metadata-only gain decision |
| R-004 | Protect sources and outputs | Existing no-overwrite and cancellation tests remain passing |
| R-005 | Public project and tracked work | Public visibility verified; changes remain reviewable PRs |

### 4.2 Assumed requirements

| ID | Assumption | Verification |
| --- | --- | --- |
| A-001 | Analysis uses at most 512 MiB working memory for two-hour stereo | Profile a generated long fixture; revise target before dependent work |
| A-002 | 3 LU is a useful comfort-mode starting range | Level-matched listening comparison; no universal comfort claim |
| A-003 | English UI is sufficient for first release | Owner readback; keep strings ready for localization |

Approved R-006: the first SignalForge-derived meter and local report path, with official-fixture harness and cross-meter comparison explicitly in scope. Consequence: user_data, because wrong gain guidance can damage derived outputs. This is the only new harness requested by slice 001.

Approved R-007: only the local numerical, resource, native preview and listening gates S2-001 through S2-009 in SLICE-002-dialogue-mastering.md. Consequence: user_data. Approval of the brief activates this verification scope; no broad benchmarking service or listener campaign is included.

### 4.3 Open questions

Speech model/license, additional listening-corpus rights, software license and supported platform matrix remain recorded below. Signing setup and the bounded analysis memory result have evidence; neither establishes release readiness.

### 4.4 Product principles

Truth: report uncertainty and processing mode. Repair: edit manual speech regions and retry analysis. Dignity: accessible controls and neutral errors. Ownership: sources remain user-owned and reports can be saved locally. Informed choice: optional model downloads show size/license before installation; no background upload or urgency prompts.

## 5. Data Model

Implemented AnalysisReport v1: schemaVersion, source fingerprint, duration, decoded sample rate, channel labels/order, decoder identity/options, measurement algorithm/version, integrated LUFS or unavailable reason, LRA or unavailable reason, momentary/short-term trajectories, true-peak method/value, per-channel diagnostics, manual speech ranges and warnings. Automatic speech confidence is not implemented. Source identity must detect replacement; hashing cost is measured in M1. No report may claim dialogue content was machine-verified in slice 001.

Manual region: start/end in integer sample positions with an explicit timebase, bounded to source duration; selection method and user confirmation recorded. Nonfinite values use an explicit unavailable state, never JSON NaN. Exported report schema is internal and versioned, not a promised external SDK. Save atomically to a new destination; preserve existing reports. Session schema changes are excluded from slice 001.

Proposed mastering data: fresh AnalysisResult, process-local immutable GainPlan and a new bounded VerificationReport v1. SLICE-002-dialogue-mastering.md section 7 owns their field and validation contract. No imported report drives rendering; no session migration is included.

## 6. Permissions and Access Model

The local user controls source and destination access. App reads selected media and writes operation-owned staging/report paths. Contributors can propose code; they cannot access signing credentials or private fixtures. Maintainer chooses reviewed release commits. Enforce access through OS permissions and separate runner/signing environments; report text cannot authorize actions.

## 7. Security Requirements

Threats: hostile media or session files, oversized decoder output, altered sources between analysis/render, malicious PR code, model supply-chain changes and credential disclosure. Validate boundaries, bound memory/output, pass subprocess arguments without a shell, pin model identity and never execute model-provided code. A public runner has no signing secrets. No auth service, password storage or public application endpoints exist. Dependency vulnerabilities and distribution rights need review before shipping. Incident response: stop affected processing/distribution, preserve redacted evidence, rotate exposed build credentials and publish a scoped fix notice if users were affected.

## 8. Privacy and Data Handling

Media, paths, manual speech selections and derived reports can reveal personal content. They remain local. Keep analysis intermediates only for the operation; forced-crash cleanup must prove ownership. Explicitly saved reports persist until the user deletes them. Shared reports omit absolute paths and identifying metadata by default. Source deletion is outside app cleanup authority. Before release, document tool/model downloads, report contents and crash-log redaction. No claim of legal certification is made.

## 9. Coding Standards

Swift typed boundaries, structured errors, explicit unavailable measurements and immutable execution plans. Keep CPU analysis off the main actor. Do not interpolate untrusted text into filters or shells. Label native controls, separate displayed text from stable serialization identifiers, and document numerical conventions. Use the repository's existing style; a formatter migration is outside this slice.

## 10. Repository Organization

Existing Sources, Tests, Resources, build.command and package.command stay in place. This planning set lives in Docs/Planning and references the established Docs records rather than replacing them. AnalysisCore is a proposed module, not an installed package. Clean-machine setup must record Xcode/Swift, macOS and FFmpeg versions. Generated media, SDKs, binaries and credentials stay out of Git.

## 11. Testing and Verification

| Requirement | Gate | Evidence |
| --- | --- | --- |
| R-001 | Native core walkthrough | Versioned UI checklist and observed results |
| R-002 / R-003 | Existing AudioTests; future speech/mastering gates | Current evidence is only the FFmpeg foundation |
| R-004 | ExportTests, FFmpegTests, RecoveryTests | Existing local debug/release logs, scoped in MAP-EVIDENCE.md |
| R-005 | GitHub visibility and PR inspection | Operational evidence in SIGNING-AND-CI.md |
| R-006 approved | meter-conformance, meter-crosscheck, analysis-ui, analysis-report, analysis-cancel, analysis-performance | Recorded runs tied to S-001 through S-006 in MEASURED-ANALYSIS-EVIDENCE.md |
| R-007 | mastering-plan, mastering-dsp, mastering-output, mastering-continuity, mastering-preview, mastering-recovery, mastering-performance, mastering-listening, mastering-ui | Active Slice 002 gates S2-001 through S2-009; no results claimed |

Do not rename a skipped gate as passed. Official test data needs a rights manifest, checksum and expected values; fetch locally if redistribution is not allowed. Cross-check a second implementation and investigate discrepancies. Repeated inconclusive attempts stop at the slice's time box; revise the decision instead of inventing wider harnesses. Blind listening belongs to later mastering slices, with corpus coverage and success criteria fixed before results are seen.

Approved R-008: the bounded still-preview checks S5-001 through S5-006 in SLICE-005-filtered-picture-preview.md. Consequence: local_only for temporary rendering, with R-004 source/output protection retained. The named gates are picture-plan, picture-frame, picture-display, picture-lifecycle, picture-resource and picture-ui. Owner approval of Slice 005 activates this bounded implementation and verification scope. M1 must verify temporal identity before M2/M3 depend on it.

## 12. Tool and Agent Discipline

This engagement writes planning documents and performs the separately requested repository-publication operation. No product code, package installations, runner registration, credentials, merges or releases are changed by the plan. Earlier owner delegation informs routine defaults, but does not invent approval of this newly requested framework brief. Protected effects remain governed by AGENTS.md and direct owner instructions. No new restrictions are imposed by an inferred approval checklist.

## 13. Observability

Record operation phase, elapsed time, tool/algorithm versions, chosen policy and failure category. Keep raw media, credentials and private paths out of public logs. Show actual before/after measurements and unavailable reasons. No hosted analytics or recurring monitoring is introduced.

## 14. Operations and Deployment

See ADD section 12 and SIGNING-AND-CI.md. Public standard hosted checks provide clean environments. Local checks provide hardware-specific evidence. Do not attach the daily-use signing Mac to public PR jobs. A self-hosted runner, if later needed, requires a disposable isolated environment and explicit registration scope. Old session formats must remain readable or fail explicitly; no silent incompatible downgrade.

## 15. Cost Discipline

Use current tools and free public standard runners. No new paid allocation or service commitment. A dedicated runner or commercial speech model is an Open decision until cost and license are known. Developer Program enrollment is an owner account action, not an automated purchase.

## 16. Risk Register and Unknowns

| ID | Area and concern | Impact / confidence | Next check / owner | Status |
| --- | --- | --- | --- | --- |
| U-001 | Speech model accuracy and license | Wrong dialogue gain; unknown | Reopen for automatic-speech brief after manual mastering; maintainer | Deferred |
| U-002 | Official fixtures and film corpus rights | Cannot redistribute evidence; unknown | Review licenses and record local acquisition manifest; maintainer | Open |
| U-003 | OS/CPU/HDR display coverage | Untested compatibility; unknown | Select support matrix and obtain representative hardware; owner | Open |
| U-004 | Developer Program/team authority | Credential setup verified | Developer ID identity and notary profile verified on 2026-09-28; owner | Confirmed |
| U-005 | Software license | Public code reuse rights unclear; unknown | Owner selects license after dependency review; owner | Open |
| U-006 | A-001 memory/cancel targets | Unusable full-film analysis; inferred | Slice 001 two-hour test passed at 106.7 MiB; profile new mastering path under S2-007 | Confirmed |
| U-007 | A-002 comfort and A-003 language needs | Fatigue/access gaps; inferred | Owner readback and later listening panel; owner | Open |

Coverage: source boundaries examined; existing local result records reused; new meter verified within the stated fixture/platform scope; automatic speech, actual HDR displays, Intel/older OS tests and signing remain unexecuted. Cloud billing eligibility is external and judged by actual runs.

## 17. Definition of Done

Per slice: approved brief, all S-IDs have evidence, core and error walkthroughs executed, no unsupported claims, privacy boundaries preserved, documents updated and owner walkthrough recorded. Per production release: all acceptance-ledger gaps either closed or explicitly removed from release scope, license resolved, platform matrix passed, signed/notarized artifact and clean-machine installation verified, rollback artifact retained and owner release approval recorded.

## 18. Change Control

Version 0.1 is a draft, not an audited product specification. Decision changes use new log entries and explicit superseding links. Mechanical audit success does not approve decisions or demonstrate software behavior. Exactly one slice becomes active after its own approval; later slices do not inherit that approval.

## Preset extension, 2026-09-29

Approved R-009 under delegated Slice 006: source-independent recipes and bounded settings undo. Consequence: user_data for local saved settings. Gates preset-scope, preset-storage, preset-conflict, preset-history and preset-ui bind S6-001 through S6-005. No general test service or schema migration is included.

## Orientation extension, 2026-09-30

Approved R-010 under delegated Slice 007: validated source orientation shared by queue and still preview. Gates orientation-plan, orientation-export, orientation-preview and orientation-ui bind S7-001 through S7-004. Consequence: user_data for newly encoded output, with R-004 no-overwrite and source preservation retained. No configuration migration or new dependency. Generated fixtures and independent pixel permutation checks are bounded to this feature.

## Queue preflight extension, 2026-09-30

Approved R-011 under delegated Slice 008: bounded read-only queue preflight with truthful deferred checks. Gates queue-review, queue-review-scope, queue-review-lifecycle and queue-review-ui bind S8-001 through S8-004. Consequence: local_only observations with no staging, encoding, recovery or output writes. Existing execution/publication remains independently validated.

## Batch cleanup extension, 2026-09-30

Approved R-012 under delegated Slice 009: report and persist batch cleanup failures while preserving the media outcome. Gates batch-cleanup-success, batch-cleanup-published, batch-cleanup-failed and batch-cleanup-lifecycle bind S9-001 through S9-004. Consequence: user_data for removal of the current operation's owned temporary directory only; source, final output and unrelated siblings remain protected. No recovery schema change or deletion of historical leftovers.

## Container inspection extension, 2026-09-30

Approved R-013 under delegated Slice 010: inspect reported chapters and embedded attachment metadata, with bounded labels/rows and request identity. Gates container-inspection-data, container-inspection-bounds, container-inspection-ui and container-inspection-identity bind S10-001 through S10-004. Consequence: local_only read-only observations. No filename tag is interpreted as a path and no attachment payload is extracted or loaded.

## Slice 011 container preservation checkpoint

Approved R-014 under delegated Slice 011: verify retained flat chapter titles/times and attachment payload SHA-256, sizes, names and MIME types before publication. Gates container-preservation-mkv, container-preservation-mp4, container-preservation-routing, container-preservation-refusal and container-preservation-ui bind S11-001 through S11-005. Consequence: current-operation owned output staging only; source and previous outputs remain protected. No extraction, cover-art/edition guarantee, saved-schema change, release or audio acceptance.

## Slice 012 destination capacity checkpoint

Approved R-015 under delegated Slice 012: qualify real destination space exhaustion within a bounded, owned disk image. Gates capacity-failure, capacity-ownership, capacity-retry and capacity-ui bind S12-001 through S12-004. Consequence: generated fixture storage only; no owner-volume filling or file deletion. Production publication and cleanup are expected to remain unchanged.

## Slice 013 output geometry checkpoint

Approved R-016 under delegated Slice 013: enforce original raster dimensions and bounded resized raster fit before publication. Gates geometry-export, geometry-bounds, geometry-refusal and geometry-ui bind S13-001 through S13-004. Consequence: current-operation staged output verification only; no changed filters, stored format, source/prior output mutation or display-aspect guarantee.

## Slice 014 batch publication checkpoint

Approved R-017 under delegated Slice 014: move advanced batch publication off the UI thread, preserve in-flight ownership/cancellation outcomes and expose per-job native access review without changing paths. Gates publication-responsive, publication-cancel-success, publication-failure and publication-access-ui bind S14-001 through S14-004. Consequence: current-operation publication/cleanup only; no replacement, early abandonment, stored phase change, broad permission settings or historical deletion.

## Slice 015 external subtitle checkpoint

Approved R-018 under delegated Slice 015: add one bounded plain UTF-8 SRT to supported zero-start SDR exports, stage captured bytes, and verify decoded added cue text/times plus codec/language/title before publication. Gates external-srt-roundtrip, external-srt-refusal, external-srt-ownership, external-srt-persistence and external-srt-ui bind S15-001 through S15-005. Consequence: current-operation owned staging only, with source/caption/prior-output protection, saved-schema migration and balanced transient read access. No subtitle-content persistence, silent styling flattening or audio/release scope.

## Slice 016 workspace dialog checkpoint

Approved R-019 under delegated Slice 016: attach the five workspace file-command dialogs, preserve replacement confirmation, capture saved intent and refuse stale or duplicate callbacks. Gates workspace-panels-ui, workspace-panels-lifecycle, workspace-session-replacement and workspace-panel-save bind S16-001 through S16-004. Consequence: user_data for explicitly chosen session/reference writes; source and encoded-output bytes remain protected. No queue execution, saved-format migration, audio or release scope.

## Slice 017 display proportion checkpoint

Approved R-020 under delegated Slice 017: independently verify known declared stream display proportions using upright crop dimensions and bounded reduced rational arithmetic. Gates display-aspect-preservation, display-aspect-refusal, display-aspect-unknown and display-aspect-ui bind S17-001 through S17-004. Consequence: current-operation staged-output verification only; unknown source ratios remain explicit, filters and saved settings remain unchanged, and existing source/output protection stays in force.

## Slice 018 frame stepping checkpoint

Approved R-021 under delegated Slice 018: discover decoded source-frame neighbors and require original/filtered timestamps to match the chosen rational identity, retaining the existing preview scope. Gates frame-step-neighbor, frame-step-picture, frame-step-lifecycle and frame-step-ui bind S18-001 through S18-004. Consequence: local-only bounded decoding and ephemeral images; no media writes, saved-format changes, audio or release scope.

## Slice 019 source stability checkpoint

Approved R-022 under delegated Slice 019: compare observed source bytes before inspection and before publication using a regular-file utility reader. Gates source-content-reader, source-content-refusal, source-content-lifecycle and source-content-export bind S19-001 through S19-004. Two additional reads for ordinary SDR; no snapshot or arbitrary filesystem latency guarantee. Audio stays parked.

## Slice 020 source import checkpoint

Approved R-023 under delegated Slice 020: one owned native/fallback source inspector and one latest pending replacement, with explicit cancellation and settled-worker lifecycle. Gates import-native-cancel, import-lifecycle, import-compatibility and import-ui bind S20-001 through S20-004. The user journey is open source, wait or cancel, retain prior work on cancellation, and retry; the authoritative state is the current request identity and worker outcome. A stalled old read returning after a newer source request is the counterexample. Generated local media only; no writes to source data or persistent-format change. Audio and durable permission handling remain separate.

## Slice 021 native publication checkpoint

Approved R-024 under delegated Slice 021: reuse awaited background publication for native Quick Export, preserve true filesystem outcomes under cancellation, and expose finishing status. Gates native-publication-responsive, native-publication-outcome, native-publication-ui and native-publication-regression bind S21-001 through S21-004. The user's authoritative result is the completed filesystem operation, not a late cancellation request. Only current-operation staging is cleaned after settlement; source and existing outputs remain protected. Other native I/O, audio and release remain outside scope.

## Slice 022 duration checkpoint

Approved R-025 under delegated Slice 022: retain a strict 250-millisecond container-duration allowance without percentage growth, explicit unknown source duration and finite-value checks. Gates duration-policy, duration-refusal, duration-compatibility and duration-regression bind S22-001 through S22-004. A shortened real encode that passes because the programme is long is the counterexample. Only current staged outputs are examined; no cadence, source, audio mastering or persistent-format changes.

## Slice 023 native preset accessibility checkpoint

Approved R-026 under delegated Slice 023: clear native preset labels using the accepted pronunciation helper, selected-state values and optional hints. Gates native-preset-labels, native-preset-selection and native-preset-regression bind S23-001 through S23-003. Visible names and native encoding choices stay unchanged; native accessibility inspection is evidence for exported semantics, not spoken VoiceOver acceptance. No new tests mirroring text literals are required.

## Slice 023 dependency repair checkpoint

Approved R-027 under D-037: remove the reproduced subprocess shared-worker starvation while preserving process/pipe settlement, callbacks, bounds and cancellation. Gates runner-fanout and runner-lifecycle bind S23-004/S23-005 in the amended active Slice 023. Generated bytes only, 96 children maximum per fan-out proof, no test scheduling or limit relaxation. Consequence: local_only execution diagnostics and existing process ownership; no encoder argument, media policy, saved-format or audio-algorithm change.


## Workspace recipe checkpoint, 2026-09-30

Approved R-028 under D-038: settings-only recipe and direct correction in the existing workspace. Gates recipe-intent, recipe-correction, recipe-native and recipe-regression bind S24-001 through S24-004. Consequence: local_only presentation and tab navigation. No encoding, source I/O or persisted state changes. Native inspection covers visible/accessibility behavior; owner design feedback and spoken qualification remain separate.


## Restored-source review checkpoint, 2026-09-30

Approved R-029 under D-039: defer restored media reads until explicit matching-source review, preserving saved recipe/name/queue. Gates restored-source-idle, restored-source-review, restored-source-native and restored-source-regression bind S25-001 through S25-004. Consequence: local_only media-read initiation and process-local session presentation. No persisted format or export policy change.

## SDR cadence checkpoint, 2026-10-01

Approved R-030 under D-040: preserve SDR video timestamps through explicit passthrough and filter time base, with generated decoded-frame evidence. Gates cadence-vfr, cadence-matrix, cadence-native and cadence-regression bind S26-001 through S26-004. Consequence: derived user_data through existing no-overwrite publication. No runtime frame-audit guarantee, audio or saved-format change.

## Native export dialog checkpoint, 2026-10-01

Approved R-031 under D-041: attached native export destination selection with captured source/preset and current availability. Gates native-panel-lifecycle, native-panel-export, native-panel-ui and native-panel-regression bind S27-001 through S27-004. Consequence: user_data through the existing protected native export service. No changed encoding, persisted state or audio scope.

## Native output name checkpoint, 2026-10-01

Approved R-032 under D-042: refuse known MP4 name collisions before Replace, with correction, cancellation and retained final publication protection. Gates native-name-validation, native-name-ui, native-name-protection and native-name-regression bind S28-001 through S28-004. Consequence: user_data through existing exclusive output publication. No source mutation, automatic renaming, saved-format or audio change.

## Queue destination review checkpoint, 2026-10-01

Approved R-033 under D-043: native review of distinct pending output folders before batch execution or recovery-record replacement. Gates queue-destination-sequence, queue-destination-protection, queue-destination-native and queue-destination-regression bind S29-001 through S29-004. Consequence: user_data only through existing batch execution after final current matching selection; prior selection is local_only. No persistent permissions, stored-format or audio change.

## Chapter editor checkpoint, 2026-10-01

Approved R-034 under D-044: typed chapter authoring/removal, native draft editing and owned source import, source-specific persistence and actual output verification. Gates chapter-validation, chapter-export, chapter-timing, chapter-persistence, chapter-editor-lifecycle, chapter-native, chapter-coexistence and chapter-regression bind S30-001 through S30-008. Consequence: user_data in saved intent and newly published exports; source bytes remain immutable. No audio/DSP, remux or new HDR transform scope.

Approved R-035 under D-045: bounded disposable APFS failure/retry qualification. Gates apfs-ownership, apfs-failure, apfs-protection, apfs-retry and apfs-regression bind S31-001 through S31-005. Consequence: local_only generated fixture; preexisting media and disks excluded. No relaxed HFS+ contract or generalized storage guarantee.

D-046 extends R-035 regression diagnosis with one bounded read-only hosted test-process observer. Consequence: local_only ephemeral generated CI execution; no owner media, secrets or runtime telemetry. Original tests, scheduling, deadlines and assertions remain authoritative.

D-047 adds one focused hosted comparison under R-035, using unchanged affected non-audio suites before the full test gate. Diagnostic success alone is not acceptance; no product, DSP, fixture, scheduling or deadline changes are included.

D-048 extends R-035 with bounded production-status observations in the existing generated destination test. Every fixture, assertion, time limit and scheduling policy remains unchanged. Worker-priority changes are not yet authorized.

D-049 extends R-035 with at most 32 timing messages around the unchanged production source reader in the existing generated destination test. Forward callbacks without waits or fake results; no executor or worker-priority repair is authorized yet.

Approved R-036 under D-050: preserve requested task priority at the source-check Dispatch boundary, without changing hashing, ownership, cancellation, actor isolation or audio. Gate source-worker-priority binds S31-006 with actual worker QoS, pre-repair failure, existing mutation/cancellation checks and full local/hosted/native regression. Snapshot priority is not a promise of later dynamic priority propagation or bounded filesystem latency.

Approved R-037 under D-052: per-read owned source worker queue preserving requested QoS and existing scan/cancellation behavior. S31-007 uses an opt-in bounded actual-source contention counterexample plus full regression; existing test scheduling/deadlines remain unchanged.

Approved R-038 under D-053: preserve requested priority and own final-publication dispatch. S31-008 requires actual exclusive-publication contention negative/positive checks, unchanged collision/cancellation/cleanup behavior and full local/native/hosted regression.

Approved R-039 under D-055: own regular-source admission dispatch with inherited task priority and a per-ToolRunner initiated control queue for launch/notify/escalation. S31-009 binds bounded actual-operation counterexamples and unchanged source/process lifecycle plus full/native regression.

Approved R-040 under D-057: bounded silent original/filtered motion comparison. S32-001 through S32-006 bind motion-timing, motion-picture, motion-admission, motion-lifecycle, motion-native and motion-regression gates. Consequence: local_only derived media in uniquely owned temporary storage; no publication or changes to user files. Requires parser/sink negative controls, real source/child/player settlement, independent media verification and full local/native/hosted checks.

Approved R-041 under D-059: truthful queue outcome summary and compact review. S33-001 through S33-005 bind queue-outcomes, queue-presentation, queue-actions, queue-ownership and queue-regression. Consequence: user_data through existing execution/publication controls, with a read-only presentation change. No new persistence or automatic execution.

Approved R-042 under D-060: determine whether actual subtitle dispatch and the cancellation test entry waiter are delayed under bounded CPU contention. Need trace: decision is scoped dispatch/event repair versus further investigation; consequence is user_data through existing caption reads plus truthful cancellation evidence. Baseline is failing hosted run 36848579493 and unchanged one-minute gates. Use existing opt-in three-second CPU work, debug-only actual worker observations and test-only entry timing. Accept only meaningful negative/positive evidence with the original assertions and joined fixture lifetime; stop at non-reproduction or a different boundary. No default scheduling, deadlines, source fingerprint algorithm, caption parser or DSP changes. This requirement is part of S33-005, not a separate acceptance bypass.

Approved R-043 under D-061: active app-owned accent/warning text uses appearance-aware colors with reference contrast of at least 4.5:1 in light/dark and 7:1 in increased contrast, including documented tint backgrounds. Primary actions use a separately qualified foreground/fill pair. S34-001 through S34-004 bind palette-reference, palette-native, palette-actions and palette-regression. This is presentation only; no media, credentials or saved-format changes. Actual native rendering and its material limitations remain explicit.

Approved R-044 under D-062: a reversible compact source preview preserves the existing player and encoding intent. App-only preference defaults to the existing height. S35-001 through S35-004 bind preview-layout, preview-continuity, preview-recovery and preview-regression. Consequence is local presentation; no new observer or assurance harness is required.

Approved R-045 under D-064: trimmed external SRT exports intersect and shift captured cues exactly once, with explicit millisecond boundaries and no empty result. Video/audio filters preserve the common source offset, custom chapter metadata matches the output timeline, and runtime verification compares the transformed immutable snapshot. S36-001 through S36-005 bind caption-intersection, caption-timeline, caption-coexistence, caption-trim-native and caption-trim-regression. Consequence: newly exported user media; source bytes and existing destinations remain immutable. Generated numerical timing checks do not constitute owner audio listening or original-mastering acceptance.

Approved R-046 under D-065: diagnose the existing publication observation timeout with bounded test-only events, unchanged assertions/deadlines/scheduling and existing actual worker hooks. S36-005 remains held. Distinguish test observation delay from main-queue or actual publication delay before changing behavior. No audio or media processing change is authorized by this diagnostic extension.

R-046 / D-066 narrows the repair to actor isolation of one pure-storage stress fixture and its stateless helpers. Preserve the same workload and every guard; add a non-main-thread assertion. Default parallel scheduling and all publication time limits remain fixed. Production publication, validation and audio code are unchanged. Hosted correlated diagnostics must still be examined, and temporary traces removed before ordinary-gate acceptance.

Approved R-047 under D-067: explicit verified original-video copy. S37-001 through S37-006 bind copy-intent, copy-audit, copy-timeline, copy-publication, copy-native and copy-regression. Consequence is a newly exported user file, so immutable captured expectations, complete packet comparison, bounded private staging, settled cancellation and exclusive publication are required. Do not infer whole-file losslessness, arbitrary container semantics or owner listening acceptance. Keep all original transcode guards and schemas.

Approved R-048 under D-068: ordered external SRT tracks with per-track immutable capture and output verification. S38-001 through S38-006 bind caption-list-intent, caption-list-plan, caption-list-export, caption-list-refusal, caption-list-native and caption-list-regression. Consequence is saved user intent and newly exported media; version compatibility, complete list/snapshot pairing, explicit stream ordinals, bounded file lifetimes and exclusive publication are required. Existing embedded routing guards remain unchanged; no full embedded-caption payload claim.

R-048 / D-069 keeps byte-exact caption titles through a private bounded FFmetadata stream-section snapshot rather than normalized process arguments. Source evidence is a minimal Foundation Process byte comparison and actual strict-output refusals. Existing ToolRunner and equality policy remain unchanged; include literal Unicode/delimiter output tests and corrected chapter input indices.

R-048 / D-070 replaces the rejected FFmetadata-section implementation with literal bounded title argument files consumed by FFmpeg's documented slash-prefixed option syntax. No extra demux inputs or source stream metadata remapping remain. Preserve the original chapter input formula and exact added-title/cue comparisons; retain failed delimiter and metadata experiments as evidence.

R-048 / D-071 permits bounded temporary cancellation-entry timestamps and a same-runner focused comparison. Preserve ordinary full-suite failure, scheduling, deadlines and all settlement/publication assertions. This is diagnosis, not acceptance or permission to alter unrelated worker scheduling.

R-048 / D-072 isolates actual SubRip snapshot dispatch under bounded CPU contention. A measured failure permits only the matching owned priority-preserving worker repair; no deadline or ordinary scheduling changes. Original snapshot bytes, exclusive creation and settled cancellation remain mandatory.

R-048 / D-073 extends bounded temporary diagnosis to actual batch preparation/verification entry and return boundaries. No task priority, scheduling, deadline or fixture changes; acceptance remains blocked by the ordinary hosted entry failure.

R-048 remains unaccepted after D-073: actual snapshot writes are prompt, but aggregate preparation/encoding consumes the entry window under hosted load. CAPTION-ENTRY-REFRAME.md records the unresolved owner decision; no further harness or product expansion while this gate is open.

R-048 / D-074: owner approval reopens the phase-specific cancellation qualification. Preserve the two-minute case and data/process assertions; 90 seconds for first-verifier preparation, ten seconds for observed-first-to-second verifier entry, ten seconds for settled cancellation. Shared wait logic must reject a deliberate stalled preparation and always join owned work before cleanup. No production or suite-scheduling changes.

R-048 acceptance: all S38-001 through S38-006 gates passed at 2f8cea7 under D-074, ordinary hosted run 36893266046. Sources/workflow match the optimized/native-qualified 6c471b7 product; full local/hosted runs each report 266 tests. Preserve the superseded startup-guard failures as evidence, without a ten-second aggregate throughput claim.

Approved R-049 under D-075: local opt-in licensed full-film video qualification. S39-001 through S39-005 bind film-input, film-video, film-captions, film-native and film-regression. Actual BatchController exports are compared with complete independent frame/PTS and subtitle data. Source/owner recovery state stay protected; no production behavior change or hosted media acquisition.

R-049 / D-076 permits compact JSON formatting after exact complete-field equality showed the original HEVC frame audit exceeded its fixed capture bound. Rerun the entire matrix; retain the first failed matrix and unrelated ordinary hosted cancellation result. No production, audio, cap or time-limit changes.

R-049 / D-077 permits one bounded observation of the existing Fresh analysis cancellation case and existing DEBUG ToolRunner events, with unchanged fixtures, assertions, five-second guard and ordinary scheduling. After two hosted failures, a third failure stops for a reframe; no audio/DSP implementation change is authorized.

Slice 039 is accepted at ordinary qualification head 542fde3, hosted run 36901339753, with byte-equivalent film/local tests at 2fe44cf and unchanged native product Sources at 6c471b7. FULL-FILM-VIDEO-EVIDENCE.md retains the two unexplained earlier hosted cancellation failures and all single-film limits. No cancellation repair, audio acceptance or production completion is claimed.
