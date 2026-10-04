# StaxRip Mac Architecture Document
Version: 0.1 Draft. Date: 2026-09-28. Status: In interview.

INTERVIEW STATE
Last completed: Slice 043 accepted at ce27093; Slice 002 experimental implementation and local listening pack preserved.
Next: Execute Slice 044 Quick Export duration verification under D-082 / R-054.
Open questions: Software license, platform matrix, audio listening and algorithm acceptance.
Statuses pending: Slice 002 paused by owner on 2026-09-29, not accepted. See NON-AUDIO-RESUMPTION.md.

## 1. One-Page Overview

Native local media processing for people who need inspectable encoding and audio results. Core loop: open media, select streams and intent, inspect a plan, execute, verify and publish a new file. Current components are Workspace, Sessions, Native Export, Batch Encoding, Audio Lab, Tool Runner and Publication. The measured report is implemented and accepted. SLICE-002-dialogue-mastering.md is approved but paused and incomplete. NON-AUDIO-RESUMPTION.md records the current pivot. Explicit static HDR10 preservation now uses a bounded full-frame audit and verified software HEVC/MKV path. Automatic speech-aware gain, broader HDR and multichannel mastering remain unfinished.

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

AnalysisCore -> GainPlanner for original Smart/Night processing. DialogueRegions -> GainPlanner for confidence-aware anchoring. ChannelLayout -> renderer for 5.1/7.1 and LFE contracts. ColorPlan -> EncodePlan for PQ/HLG preservation or explicit tone mapping. VerificationReport -> UI for A/B and export diagnostics. PicturePlan -> EncodePlan and PicturePreview is the proposed shared picture-processing extension under D-018. The other proposed interfaces remain subject to their briefs; implemented contracts are recorded in the current checkpoint.

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

Slice 049 / D-100 adds a development-only Rust companion component producer. Bounded
observation hooks leave the native read-only CLI/protocol unchanged. Exact selected
TrackEntry payload/hvcC and escaped RPU payloads retain unknown track fields and every
original encoded association. Optional tee retention copies the entire original
container, including other streams/metadata. Streamed component receipts plus content
rehash support a prototype manifest; source pathname identity and decoded mapping are
explicitly unqualified. No native archive writer command, import, saved format or
conversion admission is added. ORIGINAL-COMPANION-PRODUCER-EVIDENCE.md is the scoped
record; D-099 directory publication remains a separate integration prerequisite.

Slice 049 / D-099 adds unused internal ResultSetStaging for original companion result
publication. Owned same-parent staging and exact requested member size/SHA-256 checks
precede one exclusive directory rename. Cancellation awaits the real worker outcome;
cleanup refuses active/published or substituted stages and never follows links or
recurses. This supplies no archive writer, HDR semantic admission, session or UI change.
Caller writers must settle first. Original/transformed component semantics, storage
review and native integration remain later work. RESULT-SET-PUBLICATION-EVIDENCE.md
records the scoped generated filesystem observations and limitations.

Slice 049 / D-098 adds internal DolbyEditGeometry proposals with explicit coordinate
origins, one composite decoder crop, rational active-region scaling/padding and sample
aspect. This has no UI, metadata writer, persistence or admission effect. Integer
proposals refuse unresolved/fractional geometry. DOLBY-EDIT-GEOMETRY-EVIDENCE.md records
scope; edited-picture statistics and native conversion remain separate gates.

Slice 049 / D-097 currently checks an unbundled minimal FFmpeg development runtime.
The development builder and private dependency explicitly target macOS 14; generated
relocation is qualified for ordinary ad-hoc development only. Complete compatible
source association passed; hardened signed loading and native process/resource
integration remain open. MINIMAL-DECODER-RUNTIME-EVIDENCE.md is the scoped evidence record; existing
app behavior and admission rules are unchanged.

Current approved implementation: Slice 004, implemented within HDR10-EVIDENCE.md limits; hosted run 36607764563 passed at 16a889c. Native cleanup and Slice 003 hosted checks also passed. No merge or release is authorized. Latest accepted build boundary: SLICE-023-native-preset-accessibility.md under D-036/D-037, product head 543b991 and hosted run 36808673370. Slice 024 is accepted at daf27e6 under D-038 / R-028 with hosted run 36811284038. Slice 025 is accepted at 42c8c07 under D-039 / R-029 with hosted run 36812490982. Slice 026 is accepted at f06d431 under D-040 / R-030, hosted run 36813735721. Slice 027 is accepted at 70d0ac6 under D-041 / R-031, hosted run 36815249560. Slice 028 is accepted at 70c17da under D-042 / R-032, hosted run 36817176434. Slice 029 is accepted at 485ea85 under D-043 / R-033, hosted run 36818937608. Slice 030 has scoped acceptance at 0105d5c plus diagnostic-only ded74f6 under D-044 / R-034, hosted run 36824096245. Earlier intermittent hosted destination-review timing remains unresolved in CHAPTER-EDITOR-EVIDENCE.md. Slices 014 through 022 have scoped acceptance receipts linked from the planning index. Slice 005 has local evidence in PICTURE-PREVIEW-EVIDENCE.md. Owner approved it and delegated subsequent reversible non-audio slice decisions on 2026-09-29.

Slice 001 remains accepted with evidence in MEASURED-ANALYSIS-EVIDENCE.md. Slice 002 remains paused by owner request, not accepted. Preserve MASTERING-EVIDENCE.md, the verified v2 listening pack and unresolved D-015 findings. Audio resumes when the owner can review it with headphones.

## Slice 004 implementation checkpoint, 2026-09-29

Owner approved D-017 and Slice 004. HDR10Audit supplies an immutable process-local color/timing contract to EncodePlan. BatchController binds it to source identity, audits the staged output and publishes only on comparison success. Session v5 and journal v4 retain explicit color intent, with legacy SDR defaults. The native shared video controls and queue results expose scope and costs. HDR10-EVIDENCE.md is the coverage policy and evidence ledger. This supersedes earlier active-slice and unimplemented-HDR wording; audio remains parked.

Current approved build boundary: SLICE-031-apfs-capacity.md under D-045 through D-056 / R-035 through R-039. Scope includes a bounded generated APFS fixture, publication recovery wording, owned priority-preserving source/admission/publication workers, owned subprocess control and qualified regression diagnostics. Existing owner volumes and DSP changes are excluded. All nine criteria have scoped acceptance at a940665 and plain hosted run 36840667407.

Latest accepted boundary: SLICE-032-motion-preview.md at 5e9effa, hosted run 36845548454. The bounded renderer and app-owned player/temporary-file lifecycle reuse PicturePlan, source identity, ToolRunner and native AVPlayerView. MOTION-PREVIEW-EVIDENCE.md records the scoped acceptance and limits.

Current approved boundary: SLICE-033-queue-outcomes.md. Add read-only outcome presentation and compact native review to the existing QueueView. Controller, file-access, session and journal contracts remain unchanged.

D-060 / R-042 extends Slice 033 only at actual external-caption I/O dispatch and the cancellation test's entry-observation boundary. Queue presentation qualification remains intact, but full acceptance is held after hosted run 36848579493. Contrast discovery is retained locally and is not active implementation.

Slices 033 and 034 now have scoped acceptance at 3d14456 and 34d6c0d respectively, with hosted runs 36851151827 and 36854310994. This closes the earlier D-060 hold. Queue and appearance evidence records remaining filesystem and accessibility limits. No slice is currently awaiting implementation.

Current approved boundary: SLICE-035-compact-preview.md under D-062 / R-044. WorkspaceView changes only the existing preview frame and footer; NativeVideoPreview and its AVPlayer identity remain intact. One app-only size preference is separate from sessions and encoding intent.

Slice 035 is accepted at 24e8f2b with hosted run 36856655748. COMPACT-PREVIEW-EVIDENCE.md records the native continuity proof and rejected border experiment.

Current approved boundary: SLICE-036-trimmed-captions.md under D-064 / R-045. ExternalSubtitle owns cue intersection, EncodePlan owns this combination's timing filters, ChapterPlan selects source/output metadata time explicitly, and BatchController writes the plan-owned caption snapshot. Existing verifier and exclusive publication remain the final authority.

D-065 / R-046 holds Slice 036 acceptance after an existing hosted publication observation timeout. Diagnostic changes remain in the test gate and existing DEBUG task-local hooks; no publication or audio implementation change is approved yet. Video-copy discovery is retained locally, not an active implementation slice.

Slice 036 now has scoped acceptance at product content e2d1152 / ordinary qualification 331d1d8 with hosted run 36863640437. D-066 resolved the qualification hold through one pure-storage test fixture's actor isolation, without a production publication/validation change. All temporary diagnostics are removed. SUBTITLE-TRIM-EVIDENCE.md records actual output timelines and the complete failure/repair receipts.

Current approved boundary: SLICE-037-video-copy.md under D-067 / R-047. EncodePlan carries a process-local video-copy contract alongside existing output checks; an owned bounded packet manifest supplies complete source/output comparison before publication. Existing configuration enum values express the operation without a new persisted field. BatchController remains the lifecycle/publication owner.

Slice 037 is accepted at 22dc1ed under D-067 / R-047, with native output/recipe checks, ordinary local 254-test acceptance and hosted run 36868164452. Packet timing tolerance remains at one source/output tick, each at most one millisecond; VFR Matroska conversions that change packet durations are refused. See VIDEO-COPY-EVIDENCE.md.

Current approved boundary: SLICE-038-multiple-captions.md under D-068 / R-048. EncodeConfiguration centralizes a bounded ordered reference list while retaining the existing first-reference field. SessionDocument and BatchJournal provide explicit new-version boundaries. EncodePlan owns added stream ordinals and immutable export snapshots; BatchController remains the sole execution/publication owner.

Slice 038 has scoped acceptance at 2f8cea7 under D-068 through D-074 / R-048, ordinary hosted run 36893266046. D-074 changes test-phase budgets only; production boundaries and owned cancellation/publication remain those of 6c471b7.

Current approved boundary: SLICE-039-full-film-video.md under D-075 / R-049. A bounded opt-in test exercises the existing export owner and independent FFmpeg/ffprobe references; production architecture remains unchanged. Fixed reviewed media identity and per-run owned journals/output roots keep qualification separate from owner state.

Slice 039 is accepted at ordinary qualification head 542fde3, hosted run 36901339753, with byte-equivalent film/local tests at 2fe44cf and unchanged native product Sources at 6c471b7. FULL-FILM-VIDEO-EVIDENCE.md retains the two unexplained earlier hosted cancellation failures and all single-film limits. No cancellation repair, audio acceptance or production completion is claimed.

Current approved boundary: SLICE-040-ten-bit-video-copy.md under D-078 / R-050. Extend VideoCopyContract admission for one declared ten-bit HEVC SDR format, route its existing packet-copy plan around encoding-only pixel restrictions, and update native scope guidance. Controllers, storage and verification ownership stay unchanged. M1 feasibility precedes implementation.

Slice 040 is accepted at 23583c3 under D-078 / R-050, ordinary hosted run 36904515988. All six gates have scoped actual-controller, native, independent output and ordinary regression evidence in TEN-BIT-COPY-EVIDENCE.md. Existing cancellation and broader color/player limitations remain explicit.

Current approved boundary: SLICE-041-export-sleep-lifetime.md. A shared process-local activity factory is acquired and ended by existing queue/native export owners. No storage, audio, publication, scheduling or security-policy redesign.

Slice 041 is accepted at c54f915 under D-079 / R-051, hosted run 36907486989. EXPORT-SLEEP-EVIDENCE.md binds the five gates to actual temporary system assertions, settled export lifetimes, native/local/hosted results and owner-state restoration. Display/lock, manual sleep, power loss, Audio Lab and broader platforms remain outside this scope.


Current approved boundary: SLICE-042-caption-playback-flags.md under D-080 / R-052. A typed optional caption choice feeds an immutable flag plan in EncodePlan and verified output in BatchController. Sessions/recovery have explicit version boundaries; captions keep their current source and snapshot ownership.

Slice 042 is accepted at ba5ba2c under D-080 / R-052, hosted run 36911094620. CAPTION-FLAGS-EVIDENCE.md binds all six gates to generated flag/text/default coexistence, refusal, saved intent, native output and ordinary local/hosted checks. Player behavior, MP4 explicit flags and heard accessibility remain outside scope.

Current approved boundary: SLICE-043-track-role-inspection.md under D-081 / R-053. Shared read-only stream presentation connects MediaInspectorView and TrackRoutingView to existing MediaProbe data. Export, persistence and stream-selection ownership remain unchanged.

Slice 043 is accepted at ce27093 under D-081 / R-053, hosted run 36914015358. TRACK-ROLE-EVIDENCE.md records all four gates, the corrected accessibility-label finding and unchanged source/recovery bytes. No content suitability, heard VoiceOver or player qualification is implied.

Current approved boundary: SLICE-044-native-export-duration.md under D-082 / R-054. NativeExportService records finite source duration, reads staged duration after writer completion and applies the existing strict OutputDurationCheck before publication. A process-local native contract and bounded DEBUG-only fault seam retain existing controller, staging and publication ownership.

Slice 044 is accepted at f385cec under D-082 / R-054, hosted run 36916404356. NATIVE-DURATION-EVIDENCE.md records all four gates, real shortened/extended-output refusal, successful retry, optimized native output and ordinary local/hosted checks. Aggregate duration is narrower than decoded completeness, individual-track timing, A/V sync and source stability.

Current approved boundary: SLICE-045-dynamic-app-icons.md under D-083 / R-055. Build resources own native layered/fallback identity; a process-local Dock presentation reads existing controller state and AppDelegate provides native navigation. Processing, cancellation, publication and persisted state owners remain unchanged.

Slice 045 checkpoint:product 260f5fd and hosted run 36921033338 qualified the initial fallback bundle and read-only Dock state/API. The owner subsequently explicitly approved Icon Composer agreement EA1954 (April 16, 2025), which was accepted. Native layered source, three Composer appearance previews and actual compilation are now implemented; an extensionless compiler-matched icon key fixes Finder choosing the flat fallback. Updated bundle and regression receipts are in DYNAMIC-ICON-EVIDENCE.md. Visible Dock/menu, closed-window navigation and heard VoiceOver remain open; no full slice acceptance, merge or release.

Slice 049 / D-091/D-092 now distinguishes original encoded preservation, compatible HEVC Profile 8.1 or AV1 Profile 10 conversion, and HDR10 fallback/new HDR10+ authoring. Source census and bounded encoder feasibility are documented separately from product admission. The first implemented prerequisite is HEVCBufferLimits: optional persisted suggested/manual intent, level/tier planning in HEVCBufferPlanner, independent enabled-source inspection in its native view, and explicit x265 VBV/HRD parameters in EncodePlan. BatchController remains the sole execution/publication owner. Session 10, recovery 9 and preset library 2 protect the new intent; legacy unrestricted recipes remain unrestricted. Companion archival and crop/resize metadata transformation are planned, not admitted workflows.

At D-093/D-094, Tools/DolbyMetadataAudit was a development-only prerequisite, outside the app bundle. D-095 admits only the fixed bundled read-only inspection helper, as described below. Its protocol requires complete archive metadata, source recheck, receipt plus successful exit; it does not authorize or qualify video conversion. Native integration must independently verify extraction completeness, frame/timing mapping, transformations and dependency packaging.


D-094 / Slice 049 extends the development-only Rust reader with complete bounded Matroska HEVC packet observations. Source bytes, signed PTS and every RPU retain their original association; unsupported packet/timing interpretations refuse. No additional crate, app bundling or runtime/copy/transcode admission. BOUNDED-MATROSKA-DOLBY-EVIDENCE.md records packet/reference agreement and display-order versus decoding-order limits. Native integration, frame/POC mapping and resulting-picture crop/resize statistics remain separate gates.


D-095 adds the native read-only Dolby inspection tab. DolbyInspectionController owns
one cancellable task and waits for replaced work to settle; DolbyInspection owns the
security-scoped lease, bounded helper stream, independent FFprobe packet proof and
final off-actor SourceFingerprint. The helper's compact protocol retains aggregate
metadata without a full-film packet/metadata array in the UI. A complete receipt,
exit zero, matching selected hvcC and every ordered encoded payload/PTS are required.
No BatchController execution, EncodePlan admission, persistence or publication
ownership changes. Geometry declarations remain distinct from decoded-picture and
edited-metadata qualification. The builder verifies/copies all 69 dependency texts
and signs the nested helper before the app; running builds download nothing.


D-096 adds the unbundled development Tools/DolbyFrameReference. An installed-FFmpeg
software decoder exposes opaque packet provenance and raw frame-RPU digests without
automatic codec cropping. A bounded disk spool requires source/configuration/packet
agreement, one validated RPU per supported picture packet, complete decoder coverage
and final source rehash; no native execution/admission or new dependency is bundled.
DECODED-DOLBY-ASSOCIATION-EVIDENCE.md retains the generated and private outcome.
Codec conformance/container/user/Dolby active-area transforms stay separate; original
EL pairing, general POC, picture statistics, rendering and edited conversion stay open.


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


D-105 adds an unused internal Swift original-companion transaction coordinator. It pins
source identity, owns a unique private stage, awaits trusted settled producer and
independent semantic phases, validates matching bounded source/stage/member receipts,
and rechecks source identity immediately before exclusive publication. Cancel/refusal
awaits phase settlement before owned cleanup; a substituted stage yields a reviewable
cleanup error without recursive deletion. An admitted commit reports its actual outcome
including late cancellation. Trusted callbacks must settle their workers and supply true
receipts; no runtime validator or native writer is installed. A test-only adapter runs
the actual development writer and independent checker on generated fixtures through
native publication. Native lease/provenance/resource/signing, owner review, stable import,
crash/storage and decoded association remain gates. See
COMPANION-TRANSACTION-SETTLEMENT-EVIDENCE.md.


D-106 adds an unused strict native CompanionWriterProtocol parser before process
integration. Single-owner bounded ready/start/staged state requires expected operation,
retention, captured source/stage IDs and source size, fixed component limits, resource
bounds and no claimed semantic verification. Its private ASCII JSON subset rejects
duplicate/unknown keys, escapes, unsupported numbers, oversized/deep collections and
trailing/incomplete/nonzero results. The controller declares joined EOF/status through
finish; this parser cannot establish process/pipe settlement, executable provenance,
source/disk hashes or original semantics. Generated tests admit actual unbundled writer
stdout in both modes and compare receipt observations with disk; Python capture is
explicitly test-only. No app writer action/packaging or native bridge exists. See
NATIVE-COMPANION-PROTOCOL-EVIDENCE.md.


D-107 adds an unused internal CompanionWriterProcess: one dedicated native worker owns
POSIX spawn group/PID, finite ready/start stdin and bounded nonblocking stdout/stderr,
strict D106 receipt parsing, cancellation/deadline, signal/reap and pipe closure. Direct
child remains unreaped until EOF or abort; no monitor can signal after reaping. DEBUG
only generated tool capability binds fixed basename/explicit expected digest and source/
stage/executable observations; no release capability/signature policy is installed.
Actual generated writer both modes and ready/active-copy/late cancellation passed. It
returns a process receipt, never independent semantic/disk admission, cleanup or publication.
OwnershipFailure requires retaining stage for review; D105 must not clean up an unsettled
phase. Native semantic admission/transaction integration, leases/resources/signing and
stable/crash/storage gates remain. See NATIVE-COMPANION-PROCESS-EVIDENCE.md.


D-108 adds unused native CompanionDiskCheck integrity settlement: dedicated cancellable
read worker owns pinned source/stage/component descriptors, exact fixed membership,
owner/mode/single-link checks, independent bounded SHA256 and byte-for-byte original
container comparison. Final path/descriptor observations refuse source/stage/component
changes. Receipt explicitly does not verify original metadata semantics. The shared
CompanionUnsettledOwnership marker makes D105 retain its stage instead of discarding
when any phase reports unsettled ownership; D107 OwnershipFailure conforms. Generated
tests compose actual native writer/disk checks with the independent Python semantic
checker only as a test oracle through native publication. No native runtime original
semantic validator, app action, release writer capability/packaging or lease/resource/
signing admission follows. See NATIVE-COMPANION-DISK-EVIDENCE.md.
