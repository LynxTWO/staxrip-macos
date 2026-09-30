# StaxRip Mac Engineering Document
Version: 0.1 Draft. Date: 2026-09-28. Status: In interview.

INTERVIEW STATE
Last completed: Slice 001 accepted; Slice 002 experimental implementation and local listening pack preserved.
Next: Slice 016 attached workspace file dialogs under D-029. Slice 015 closed at b3027f2 with hosted run 36785205441.
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
