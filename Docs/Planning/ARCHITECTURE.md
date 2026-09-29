# StaxRip Mac Architecture Document
Version: 0.1 Draft. Date: 2026-09-28. Status: In interview.

INTERVIEW STATE
Last completed: Slice 001 accepted; Slice 002 experimental implementation and local listening pack preserved.
Next: Native export cleanup PR validation and owner readback of SLICE-003-video-inspection.md.
Open questions: Software license, platform matrix, audio listening and algorithm acceptance.
Statuses pending: Slice 002 paused by owner on 2026-09-29, not accepted. See NON-AUDIO-RESUMPTION.md.

## 1. One-Page Overview

Native local media processing for people who need inspectable encoding and audio results. Core loop: open media, select streams and intent, inspect a plan, execute, verify and publish a new file. Current components are Workspace, Sessions, Native Export, Batch Encoding, Audio Lab, Tool Runner and Publication. The measured report is implemented and accepted. SLICE-002-dialogue-mastering.md is approved but paused and incomplete. NON-AUDIO-RESUMPTION.md records the current pivot. Automatic speech-aware gain, HDR preservation and multichannel export are not implemented.

## 2. System Context

The user owns media and destinations. The app reads local sources, writes owned staging data and publishes new files. FFmpeg/ffprobe run with user privileges. Apple frameworks supply playback and native export. GitHub holds source and checks; Apple notarization receives release binaries, not user media. No runtime cloud processing or user accounts are present. See MAP-EVIDENCE.md for examined boundaries and limits.

## 3. Product Shape and Platforms

DECISION: D-001 Native offline product
STATUS: Confirmed
CHOICE: Keep SwiftUI/AppKit and local media processing.
BECAUSE: Owner requirement and existing implementation agree.
OPTIONS CONSIDERED: Native retains current workflows; web rewrite adds a second runtime without a stated need.
REVISIT WHEN: The owner requests another platform.

Declared macOS floor is 14. Distribution target is a directly downloaded signed app. English is the current UI language. Source visibility is public by owner instruction. License remains Open under D-008; public visibility does not select a software license.

## 4. Module Map

| Module and owner | Responsibility and data | Evidence / downstream edge |
| --- | --- | --- |
| WorkspaceModel / UI | Source, configuration, queued intent | WorkspaceModel.swift; views call controllers |
| SessionDocument / BatchJournal | Versioned intent and last-batch recovery | Validation precedes applying intent; no auto-execution |
| NativeExportService | Apple preset operation and cancellation | AVFoundation, then Publication |
| EncodePlan / BatchController | Validated argument plan, state transitions | MediaProbe, ToolRunner, staged validation |
| AudioEngine / AudioController | Selected-track analysis and mastering | FFmpeg, independent Audio Lab state |
| AudioAudit | Individual channels and selected passages | Diagnostic measurements only |
| ToolRunner / MediaProbe | Argument-only process execution and bounded output | Homebrew tools, local files |
| ExportPublication | Exclusive publication | Same-volume hard link, no replacement |

Owner of each module is the project maintainer. Implemented AnalysisReport/StreamingLoudness own measurement trajectories, report schemas and manual-region analysis. Proposed GainPlanner consumes those reports, not UI text or media tags. UI depends on services; services depend on typed plans and adapters.

## 5. Interfaces and Contracts

DECISION: D-002 Typed local analysis seams
STATUS: Confirmed
CHOICE: Internal Swift analysis/report types implemented in Slice 001; no public SDK. D-014 proposes the next GainPlan and VerificationReport contracts.
BECAUSE: Allows an independent meter and speech detector to be tested separately from rendering.
OPTIONS CONSIDERED: Swift adaptation keeps one build; a narrow Rust bridge can reuse SignalForge directly; Python service adds deployment cost. D-011 records the completed Swift selection.
REVISIT WHEN: Measured performance or reuse requirements justify another runtime.

Reports carry source identity, decoder settings, layout, timebase, algorithm version and uncertainty. A changed source invalidates a cached plan. Model output is validated structured data, never executable commands. Persisted formats need explicit schema versions and migration tests.

## 6. Core Data Flow

Existing: explicit user action -> probe -> validate copied configuration -> stage -> encode -> inspect output -> exclusive publish -> record completion. Source playback is unfiltered. Proposed analysis: source -> explicitly configured PCM decoding -> independent meter plus channel audit -> optional user-confirmed speech regions -> local report. Planned mastering adds constrained gain planning, linked rendering and independent output checks. Cancellation and measurement failure do not publish a result.

## 7. Data Domain Overview

Existing entities: EncodeConfiguration, QueueJob, SessionDocument, BatchJournal, AudioSettings, LoudnessReport. Implemented AnalysisReport v1 and proposed mastering data are described in EDD section 5. Long media must use bounded memory; volume and throughput targets are assumptions to measure, not current guarantees.

## 8. Technology Selection

### 8.1 Client
D-001 retains SwiftUI and AppKit. No UI rewrite.
### 8.2 Language
D-002 keeps Swift interfaces; D-011 selects a focused SignalForge-derived Swift implementation after the D-010 investigation. Accelerate is a candidate optimization only after correctness.
### 8.3 Backend
Confirmed under D-001: none remote. FFmpeg remains a local decoding/rendering adapter.
### 8.4 Database
D-002 uses versioned report files before a database. Existing sessions use JSON.
### 8.5 Authentication
No application login. Build credentials stay in Keychain, outside application data.
### 8.6 AI layer
D-013 defers automatic speech-model selection until manual-speech mastering is evaluated. Activity detection identifies candidate speech; it does not isolate dialogue from simultaneous music. Manual correction and low-confidence refusal are required before gain decisions depend on it.
### 8.7 Notifications and messaging
Existing in-app operation status. Email, push and analytics are excluded.
### 8.8 Hosting and builds
D-007 proposes free public hosted macOS checks plus local hardware verification. Signing is a separate trusted operation; see SIGNING-AND-CI.md.

## 9. Integration Map

| Integration | Direction | Failure behavior |
| --- | --- | --- |
| Apple media frameworks | Local decode/encode | Explicit failure; no mislabeled FFmpeg settings |
| FFmpeg / ffprobe | Local subprocess and files | Missing capability or nonzero exit blocks publication |
| Optional speech model | Future local inference | Unknown/low-confidence state and manual correction |
| GitHub | Source and test evidence | Local tests continue if hosted checks fail |
| Apple notary service | Approved release upload | No notarized-release claim without acceptance and ticket verification |

## 10. Extension Points

AnalysisCore -> GainPlanner for original Smart/Night processing. DialogueRegions -> GainPlanner for confidence-aware anchoring. ChannelLayout -> renderer for 5.1/7.1 and LFE contracts. ColorPlan -> EncodePlan for PQ/HLG preservation or explicit tone mapping. VerificationReport -> UI for A/B and export diagnostics. These are proposed interfaces, not current features.

## 11. Scale and Performance Posture

D-009 is Assumed: a two-hour 48 kHz stereo movie should be analyzable without retaining whole PCM in RAM. A 512 MiB analysis working-set target and cancellation within five seconds are provisional. The Slice 001 two-hour profile passed at 106.7 MiB on Apple M5. This does not establish memory or throughput for the new renderer; S2-007 requires a separate full-pipeline profile.

## 12. Deployment Topology

Developer preview -> locally verified candidate -> hosted checks -> licensed dependency review -> approved signing/notarization -> clean-machine Gatekeeper test -> owner-approved release. Retain previous signed artifacts for rollback; no automatic downgrade of incompatible saved data. No release is authorized by this planning document.

## 13. Failure and Degraded Modes

| Failure | Response | Recovery |
| --- | --- | --- |
| Silence or unmeasurable programme | Unknown measurement, no invented LUFS | Change source or export without processing |
| Uncertain dialogue | Mark regions/confidence; no automatic dialogue gain | User corrects regions |
| Unknown surround layout | Reject preserving-layout export | Explicitly choose a supported mapping |
| HDR metadata ambiguity | Reject preservation promise | Select an explicit conversion or another source |
| Existing output / disk error | Leave destination unchanged | Choose a new destination and retry |
| Interrupted process | Review interrupted intent | Explicit recovery; no blind resume |

## 14. Architecture Guardrails

No source overwrite. No silent fallback between engines or preservation modes. No centre-channel-equals-dialogue assumption. No LFE contribution to a BS.1770 programme value. No model-derived command text. No media upload to speech services. No public-PR execution on the signing Mac. Existing privacy and ownership rules in AGENTS.md remain in force.

## 15. Current Build Boundary

Owner pivot, 2026-09-29: Slice 002 is paused, not accepted. Native export cleanup hardening has local evidence and is awaiting hosted validation. SLICE-003-video-inspection.md is the proposed next build boundary; it is read-only and does not add HDR encoding. This checkpoint supersedes active-slice wording below; retained audio evidence is unchanged.

Slice 001 is Done with evidence; its owner functional/spoken acceptance and limitations are recorded in MEASURED-ANALYSIS-EVIDENCE.md. The guidance refinement is part of that closure. Current boundary: SLICE-002-dialogue-mastering.md. Slice 002 is now the active approved boundary, approved by Daniel Boyd on 2026-09-28. D-013 confirms manual speech before automatic suggestions. D-014 confirms the detailed mastering/preview boundary; D-015 remains open after real-film numerical failures; D-016 records listening-source permission. Native implementation and resource evidence are in MASTERING-EVIDENCE.md. A local six-excerpt comparison pack is prepared for wider research requests; 3 LU performance, listening and owner acceptance remain open. HDR, surround, signing and release remain outside this boundary.
