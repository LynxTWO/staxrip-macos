# StaxRip Mac Engineering Document
Version: 0.1 Draft. Date: 2026-09-28. Status: In interview.

INTERVIEW STATE
Last completed: Slice 044 accepted at f385cec; Slice 002 experimental implementation and local listening pack preserved.
Next: Execute Slice 045 native identity and live Dock status under D-083 / R-055.
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

Approved R-050 under D-078: declared ten-bit SDR HEVC copy through existing strict metadata/packet/publication contracts. S40-001 through S40-006 bind plan, complete pictures, track coexistence, refusal, native and regression gates. Generated references must remain ten-bit and retain meaningful low-order samples. No DSP, schema, deadline or general transcode expansion.

Slice 040 is accepted at 23583c3 under D-078 / R-050, ordinary hosted run 36904515988. All six gates have scoped actual-controller, native, independent output and ordinary regression evidence in TEN-BIT-COPY-EVIDENCE.md. Existing cancellation and broader color/player limitations remain explicit.

Approved R-051 under D-079: temporary automatic-system-sleep prevention tied to actual video-export lifetime. S41-001 through S41-005 bind system assertion, queue lifecycle, native service, native UI and ordinary regression. Consequence: local_only energy use; bounded per-process system observations and existing actual-export seams only.

Slice 041 is accepted at c54f915 under D-079 / R-051, hosted run 36907486989. EXPORT-SLEEP-EVIDENCE.md binds the five gates to actual temporary system assertions, settled export lifetimes, native/local/hosted results and owner-state restoration. Display/lock, manual sleep, power loss, Audio Lab and broader platforms remain outside this scope.


Approved R-052 under D-080: typed MKV caption playback choices, explicit session/recovery versions and pre-publication default/forced checks. S42-001 through S42-006 bind feasibility, data, output, refusal, native and ordinary regression. Consequence: user_data; bounded generated experiment and existing actual-export seams only.

Slice 042 is accepted at ba5ba2c under D-080 / R-052, hosted run 36911094620. CAPTION-FLAGS-EVIDENCE.md binds all six gates to generated flag/text/default coexistence, refusal, saved intent, native output and ordinary local/hosted checks. Player behavior, MP4 explicit flags and heard accessibility remain outside scope.

Approved R-053 under D-081: read-only track identity and five declared roles. S43-001 through S43-004 bind bounded presentation, actual immutable source, native selection and ordinary regression checks. Consequence: user_data; existing probe and native seams only.

Slice 043 is accepted at ce27093 under D-081 / R-053, hosted run 36914015358. TRACK-ROLE-EVIDENCE.md records all four gates, the corrected accessibility-label finding and unchanged source/recovery bytes. No content suitability, heard VoiceOver or player qualification is implied.

Approved R-054 under D-082: Quick Export total-duration verification. S44-001 through S44-004 bind strict native timing policy, actual shorter/longer staged refusal and retry, native walkthrough and ordinary regression. Consequence: user_data. One DEBUG-only pre-verification generated-file substitution seam is authorized; no decoded-frame, A/V sync, DSP or broader runtime observer scope.

Slice 044 is accepted at f385cec under D-082 / R-054, hosted run 36916404356. NATIVE-DURATION-EVIDENCE.md records all four gates, real shortened/extended-output refusal, successful retry, optimized native output and ordinary local/hosted checks. Aggregate duration is narrower than decoded completeness, individual-track timing, A/V sync and source stability.

Approved R-055 under D-083: original layered native icon plus generated older-system fallback, shared branding and truthful read-only Dock status/navigation. S45-001 through S45-004 bind artwork, bundle, status and ordinary regression. Consequence: local_only. Bounded actual native render/export evidence and state checks; no pixel-mirror tests, new observers, DSP or lifecycle changes.

Slice 045 checkpoint: product 260f5fd and hosted run 36921033338 qualified the initial fallback bundle and read-only Dock state/API. The owner subsequently explicitly approved Icon Composer agreement EA1954 (April 16, 2025), which was accepted. Native layered source, three Composer appearance previews and actual compilation are now implemented; an extensionless compiler-matched icon key fixes Finder choosing the flat fallback. Updated bundle and regression receipts are in DYNAMIC-ICON-EVIDENCE.md. Visible Dock/menu, closed-window navigation and heard VoiceOver remain open; no full slice acceptance, merge or release.

Approved R-056 under D-084: Slice 046 exposes bounded Dolby Vision/chroma/audio-profile declarations and conversion consequences, and refuses recognized dynamic HDR in unqualified transcoding even when color tags are missing. Gates: hdr-declarations, conversion-information, format-native and format-regression. Private test source names/paths stay out of code and public evidence. FORMAT-PRESERVATION.md records the subsequent preservation/conversion sequence; it does not advertise those future paths as implemented.

Approved R-057 under D-085: Slice 047 AV1 Main 8/10-bit declared BT.709 limited-range SDR copying through the existing strict contract/controller. Gates: feasibility, plan, complete actual output, native and ordinary regression. Retain full packet/configuration, independent complete-picture/PTS/caption/chapter comparisons, source/prior-output protection and original timing/resource bounds. No generic HDR or unknown metadata admission.

D-086 narrows the hosted Slice 047 repair to deterministic inspector completion ownership. The production reader remains the default; actual process/metadata coverage is retained. No latency, mastering, admission or executor policy change; final repair qualification remains required.

D-087 moves only independent AV1 test fixture/reference work off MainActor, retaining real controller actor boundaries and the unchanged two-minute matrix bound. Native reviewed export is verified; final ordinary regression remains required. No product policy or test deadline change.

Slice 047 accepted at 356337b under D-085/D-086/D-087: all five gates, native export and final ordinary hosted run 37113569693 passed. Prior failures remain in AV1-COPY-EVIDENCE.md. D-088 repairs the observed last-window termination within Slice 045 / R-055, preserving the single workspace and existing explicit-Quit guards; native/regression receipts remain required.

R-058 under D-089 binds Slice 048 M1's read-only native container configuration capture: header-structure, header-native, header-protection and header-regression. Local-only internal prerequisite, no runtime HDR admission or saved-format change. Strict structural/resource bounds and opaque-byte/identity comparisons close the typed-probe gap before original-signal export work.

Hosted 37115174217 recurred at the historical cancellation and unchanged AV1 matrix bounds; D-077/D-087 stop applies and hosted acceptance reopens. HOSTED-QUALIFICATION-REFRAME.md contains the concrete owner decision. Slice 048 M1 separately passed eight focused parser checks, native full-file configuration comparisons and optimized build; ordinary regression remains pending, so neither M1 nor HDR preservation is accepted yet.


D-090 investigation completed at diagnostic head 0ab9d28: hosted 37126143385 passed the original 291-test workload and preview build. Existing opt-in skips remain. Cancellation settled in 0.322058 seconds; AV1 reported 115.182 seconds within its unchanged bound. Neither earlier failure reproduced, and no cause is established. Temporary tracing is retired to byte-identical c435e6d product/tests. AV1/last-window ordinary qualification remains reopened; HOSTED-QUALIFICATION-REFRAME.md records the next environment/qualification decision. No additional observation/rerun, assertion change, merge or release.


R-059 / D-091 prioritizes Slice 049 dynamic HDR conversion: complete RPU source classification, actual native enhancement/encoder feasibility, explicit conversion intent and loss disclosure before admission. Preserve the existing generic refusal until a qualified contract exists. No timing investigation expansion, owner media identity, parked listening, merge or release.

D-092 extends the R-059 prerequisite with editable HEVC VBV suggestions, explicit saved-intent versions and actual encoder signaling checks. Companion archival must retain original RPU/EL plus matching signal identity and frame/timing association; crop/scale require qualified metadata/statistics treatment. HEVC-BUFFER-LIMITS-EVIDENCE.md and DYNAMIC-HDR-FEASIBILITY-EVIDENCE.md keep product controls separate from bounded research and unknown rendering/archival admission.

D-093 / Slice 049 adds development-only Tools/DolbyMetadataAudit with pinned MIT libdovi, bounded incremental archive parsing, complete source recheck and adversarial tests. No app/runtime/dependency admission changes. See BOUNDED-DOLBY-READER-EVIDENCE.md; extraction/frame association and picture-edit gates stay open.


D-094 / Slice 049 extends the development-only Rust reader with complete bounded Matroska HEVC packet observations. Source bytes, signed PTS and every RPU retain their original association; unsupported packet/timing interpretations refuse. No additional crate, app bundling or runtime/copy/transcode admission. BOUNDED-MATROSKA-DOLBY-EVIDENCE.md records packet/reference agreement and display-order versus decoding-order limits. Native integration, frame/POC mapping and resulting-picture crop/resize statistics remain separate gates.


D-095 admits a fixed bundled read-only native Matroska HEVC inspector with protocol 3,
complete encoded-packet/hash/timestamp proof, selected configuration agreement and a
final source fingerprint. The active-area UI explicitly separates container crop,
display units and Level 5 luma offsets. Generated protocol/lifecycle/actual helper
checks, ordinary regression, licensed nested-helper build and a focused native
walkthrough are the required boundary; evidence is recorded separately. This does
not close conversion, decoded-picture/POC, brightness, archive publication,
crop/resize, rendering or hosted timing-reliability gates.


D-097 requires explicit macOS 14 compile/link declarations and actual Mach-O inspection
for the development executable and candidate libraries. Generated relocation validates
loader paths and runtime identities separately from hardened signed loading. No
whole-process memory guarantee is inferred from per-allocation bounds or resource
observations. Complete compatible source association passed; dependency/native
distribution is not admitted. See MINIMAL-DECODER-RUNTIME-EVIDENCE.md.

D-096 adds the unbundled development Tools/DolbyFrameReference. An installed-FFmpeg
software decoder exposes opaque packet provenance and raw frame-RPU digests without
automatic codec cropping. A bounded disk spool requires source/configuration/packet
agreement, one validated RPU per supported picture packet, complete decoder coverage
and final source rehash; no native execution/admission or new dependency is bundled.
DECODED-DOLBY-ASSOCIATION-EVIDENCE.md retains the generated and private outcome.
Codec conformance/container/user/Dolby active-area transforms stay separate; original
EL pairing, general POC, picture statistics, rendering and edited conversion stay open.


D-098 adds a bounded pure geometry prerequisite under R-059. Input coordinate origins,
orientation/progressive sampling, actual decoder raster, sample aspect and output
raster are explicit and validated. Coded/container declarations and decoder-applied
windows do not silently become duplicate pixel crops. Preserve rational edges and
refuse integer proposals without qualified rounding. Clipping/resizing facts do not
certify brightness. Generated actual pixel and ordinary regression/build gates are
recorded in DOLBY-EDIT-GEOMETRY-EVIDENCE.md; no edited export or metadata write follows.


D-099 selects a bounded original-companion publication prerequisite under R-059.
Callers establish semantic media/archive/manifest receipts and settle producers before
an owned stage streams exact file membership/size/hash verification. Only a same-parent
exclusive directory rename commits; no fallback or existing-result replacement.
Generated collision/corruption/link/special/cancel/cleanup/competition checks and default
app regression/build are required. Cancellation before commit admission refuses;
admitted publication reports the syscall outcome after descriptors settle. This is
content verification, not a complete archive or future-carriage qualification.


D-100 retains original escaped RPU bytes, hvcC and selected TrackEntry payload with
encoded packet ordering/indices/signed timestamps intact. Full mode copies the entire
original container; metadata-only excludes picture payloads and outside-track metadata.
Archive-specific track capture has a 1 MiB bound and is disabled for the native CLI.
Component byte/hash receipts, independent content rehash and writer/flush refusals are
required; source pathname identity and decoded frame/EL association remain external
integration obligations. Prototype components/manifest are not a stable import format.
No owner archive, queue, native admission or parked listening follows.


D-101 adds a read-only generated-development verifier for prototype original companion
packages. An independent bounded EBML walk locates the original selected TrackEntry;
actual track/configuration, fresh trusted reader audit, ordered packet/RPU index and
archived payload bytes must agree with the supplied source. Before/after content and
filesystem identity checks are observations, not an immutable snapshot. Refusal,
interruption and a bounded helper deadline settle owned processes before returning.
The producer manifest remains unmodified and unbound; a separate result records the
validator boundary. No stable importer, native archive feature, publication, decoded
picture/EL reconstruction, future carriage or signed-distribution admission follows.


D-102 adds a generated-development source-bound companion producer core. It owns
concrete File handles, opens the original source read-only/no-follow, validates
empty distinct regular write-only output descriptors before writing, and compares
source descriptor/path identity after the existing streamed content recheck. One-way
cooperative cancellation checks I/O and final receipt boundaries. Owned handles close
on return; partial files remain owned by the staging caller for settled cleanup.
Source-bound receipts remain separate from unmodified prototype manifests. Trusted
caller exclusive creation, output pathname ownership, semantic disk reread, native
worker/process policy and D-099 publication integration remain required. No new
native CLI command, UI/session schema, decoded/EL admission or dependency follows.


D-103 adds a generated-development writer into a trusted caller's precreated empty
private stage. It pins the immediate parent/stage, creates fixed regular 0600 components
with descriptor-relative exclusive no-follow opens, consumes them through D-102 and
exclusively writes the unchanged prototype manifest after the producer settles. It then
rereads exact disk membership, original created identities and content hashes, retains
read descriptors through final path checks and checks the source identity receipt again.
A staged receipt does not establish independent semantic verification or publication.
The caller creates/owns the stage, joins its worker before cleanup and later supplies
native process/resource policy plus D-101 semantic settlement and D-099 publication.
No directory creation/deletion, native command/UI/session change, decoded/EL conversion,
stable importer, crash durability or hard physical I/O deadline is added. MacOS generated
execution is exercised; Linux conditional compilation is not qualification. See
OWNED-COMPANION-STAGE-EVIDENCE.md.


D-104 adds a separate feature-gated, unbundled development companion writer executable
and an explicit trusted development process caller. The bounded ready/start/staged
protocol correlates an operation; controller-provided source/stage file identities
must match before source component writes. The caller pins source/stage, requires
strict receipt bounds and successful exit, rereads disk members and final identities,
and terminates/joins its owned process before return on refusal/cancellation/deadline.
It never deletes or publishes the stage. Independent D-101 semantic verification and
D-099 exclusive publication remain required. No native caller, bundled reader command,
UI/session change or dependency is added. Process cancellation terminates rather than
cooperatively signalling the core; partial files remain owned by the caller. Generated
checks establish ready-wait cancellation and late-completion refusal, not active physical
copy interruption or native resource/signing/lease policy. See
COMPANION-WRITER-PROCESS-EVIDENCE.md.
