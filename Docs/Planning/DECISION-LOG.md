# StaxRip Mac Decision Log
Version: 0.1 Draft. Date: 2026-09-28.

## Index

| ID | Date | Decision | Status | Superseded by |
| --- | --- | --- | --- | --- |
| D-001 | 2026-09-28 | Native offline product | Confirmed | |
| D-002 | 2026-09-28 | Typed local analysis seams | Confirmed | |
| D-003 | 2026-09-28 | Analysis before gain changes | Confirmed | |
| D-004 | 2026-09-28 | Speech model selection | Superseded | D-013 |
| D-005 | 2026-09-28 | Later preservation work | Deferred | |
| D-006 | 2026-09-28 | Public repository | Confirmed | |
| D-007 | 2026-09-28 | Hosted checks and local hardware tests | Proposed | |
| D-008 | 2026-09-28 | Project license | Open | |
| D-009 | 2026-09-28 | Full-film performance targets | Assumed | |
| D-010 | 2026-09-28 | SignalForge reuse first | Superseded | D-011 |
| D-011 | 2026-09-28 | Swift meter adaptation | Confirmed | |
| D-012 | 2026-09-28 | Slice 001 owner approval | Confirmed | |
| D-013 | 2026-09-28 | Manual speech before automatic suggestions | Confirmed | |
| D-014 | 2026-09-28 | Original mastering and preview boundary | Confirmed | |
| D-015 | 2026-09-28 | Planner and limiter feasibility | Open | |
| D-016 | 2026-09-28 | Listening material rights | Confirmed | |
| D-017 | 2026-09-29 | Bounded static HDR10 preservation | Confirmed | |
| D-018 | 2026-09-29 | On-demand filtered picture comparison | Confirmed | |
| D-019 | 2026-09-29 | Reusable presets and settings undo | Confirmed | |
| D-020 | 2026-09-30 | Validated source orientation | Confirmed | |
| D-021 | 2026-09-30 | Read-only queue preflight | Confirmed | |
| D-022 | 2026-09-30 | Report batch staging cleanup | Confirmed | |
| D-023 | 2026-09-30 | Inspect chapters and attachments | Confirmed | |
| D-024 | 2026-09-30 | Verify retained container contents | Confirmed | |
| D-025 | 2026-09-30 | Qualify full destination failures | Confirmed | |
| D-026 | 2026-09-30 | Verify resized raster dimensions | Confirmed | |
| D-027 | 2026-09-30 | Responsive batch publication and access review | Confirmed | |
| D-028 | 2026-09-30 | Verified external plain SRT subtitles | Confirmed | |
| D-029 | 2026-09-30 | Attached workspace file dialogs with captured intent | Confirmed | |
| D-030 | 2026-09-30 | Verify declared display proportions | Confirmed | |
| D-031 | 2026-09-30 | Step filtered previews by decoded timestamp | Confirmed | |

## D-001: Native offline product
Date: 2026-09-28
Status: Confirmed

Decision: Keep SwiftUI/AppKit and local processing.

Because: Owner requirement and existing application.

Options considered: retain current behavior; adopt the stated scoped change. Detailed reuse alternatives are in SIGNALFORGE-REUSE.md.

Consequences: implementation follows the approved slice boundary; an Open or Proposed decision is not approval.

Revisit when: A new platform is requested.

## D-002: Typed local analysis seams
Date: 2026-09-28
Status: Confirmed

Decision: Keep internal Swift analysis/report interfaces, as implemented under the owner-approved Slice 001 and D-011. Future GainPlan details are proposed under D-014.

Because: Separates UI, measurement and rendering without presuming a rewrite.

Options considered: retain current behavior; adopt the stated scoped change. Detailed reuse alternatives are in SIGNALFORGE-REUSE.md.

Consequences: implementation follows the approved slice boundary; an Open or Proposed decision is not approval.

Revisit when: The reuse spike finds a lower-cost tested boundary.

## D-003: Analysis before gain changes
Date: 2026-09-28
Status: Confirmed

Decision: Analysis precedes original gain planning. Daniel approved and accepted Slice 001, then explicitly accepted planning the manual-speech mastering sequence. The detailed Slice 002 build boundary still needs its own approval.

Because: Gain changes require trustworthy measurements.

Options considered: retain current behavior; adopt the stated scoped change. Detailed reuse alternatives are in SIGNALFORGE-REUSE.md.

Consequences: implementation follows the approved slice boundary; an Open or Proposed decision is not approval.

Revisit when: Meter evidence or user needs change the sequence.

## D-004: Speech model selection
Date: 2026-09-28
Status: Superseded
Superseded by: D-013

Decision: No automatic detector chosen; compare local candidates before slice 002.

Because: Movie speech, music overlap and language coverage need evidence.

Options considered: retain current behavior; adopt the stated scoped change. Detailed reuse alternatives are in SIGNALFORGE-REUSE.md.

Consequences: implementation follows the approved slice boundary; an Open or Proposed decision is not approval.

Revisit when: The bounded model/license spike is complete.

## D-005: Later preservation work
Date: 2026-09-28
Status: Deferred

Decision: Multichannel rendering and HDR each get separate briefs after stereo analysis/mastering.

Because: Channel layout and color preservation require independent acceptance tests.

Options considered: retain current behavior; adopt the stated scoped change. Detailed reuse alternatives are in SIGNALFORGE-REUSE.md.

Consequences: implementation follows the approved slice boundary; an Open or Proposed decision is not approval.

Revisit when: The preceding slice closes or priorities change.

## D-006: Public repository
Date: 2026-09-28
Status: Confirmed

Decision: Publish source visibility and continue focused PRs; do not merge or release automatically.

Because: Explicit owner instruction on 2026-09-28.

Options considered: retain current behavior; adopt the stated scoped change. Detailed reuse alternatives are in SIGNALFORGE-REUSE.md.

Consequences: implementation follows the approved slice boundary; an Open or Proposed decision is not approval.

Revisit when: Owner changes publication scope.

## D-007: Hosted checks and local hardware tests
Date: 2026-09-28
Status: Proposed

Decision: Use public standard hosted runners plus local tests; isolate any future self-hosting from signing.

Because: The retried hosted check passed; daily-use public PR execution adds exposure.

Options considered: retain current behavior; adopt the stated scoped change. Detailed reuse alternatives are in SIGNALFORGE-REUSE.md.

Consequences: implementation follows the approved slice boundary; an Open or Proposed decision is not approval.

Revisit when: A required hardware check cannot run hosted.

## D-008: Project license
Date: 2026-09-28
Status: Open

Decision: Select project license after dependency review; no license is implied by visibility.

Because: Public code reuse terms need an explicit choice.

Options considered: retain current behavior; adopt the stated scoped change. Detailed reuse alternatives are in SIGNALFORGE-REUSE.md.

Consequences: implementation follows the approved slice boundary; an Open or Proposed decision is not approval.

Revisit when: Owner selects a compatible license.

## D-009: Full-film performance targets
Date: 2026-09-28
Status: Assumed

Decision: Start with 512 MiB analysis working memory and cancellation within five seconds.

Because: Full PCM retention is unsuitable for long movies.

Options considered: retain current behavior; adopt the stated scoped change. Detailed reuse alternatives are in SIGNALFORGE-REUSE.md.

Consequences: implementation follows the approved slice boundary; an Open or Proposed decision is not approval.

Revisit when: M1 profiles the candidate.

## D-010: SignalForge reuse first
Date: 2026-09-28
Status: Superseded
Superseded by: D-011

Decision: Compare a focused Swift adaptation with a minimal Rust bridge before writing a meter anew.

Because: Owner identified existing reusable work; see SIGNALFORGE-REUSE.md.

Options considered: retain current behavior; adopt the stated scoped change. Detailed reuse alternatives are in SIGNALFORGE-REUSE.md.

Consequences: implementation follows the approved slice boundary; an Open or Proposed decision is not approval.

Revisit when: One-day M1 investigation selects a candidate or requires a revised brief.

## Change rule

Add a new entry to supersede an accepted decision; link both directions. Receipts live in MAP-EVIDENCE.md and SIGNING-AND-CI.md. No decision became Confirmed by silence.

## D-011: Swift meter adaptation
Date: 2026-09-28
Status: Confirmed
Supersedes: D-010

Decision: Adapt the small SignalForge numerical core in Swift, with MIT attribution, explicit unavailable states and bounded PCM consumption. EBU LRA and report integration are new local work. The owner approved the bounded selection in slice 001.

Because: The Rust sequence path lacks LRA/traces and a C ABI; importing its analysis crate adds decoding, FFT and resampling dependencies that this app does not need. The same numerical components can be tested in the existing build.

Consequences: Maintain numerical parity through fixtures instead of an ABI. Keep standard fixtures outside Git and carry license notices in development bundles. See MEASURED-ANALYSIS-EVIDENCE.md for current results and limits.

Revisit when: Maintenance divergence, measured performance or shared consumers justify extracting a common Rust core.

## D-012: Slice 001 owner approval
Date: 2026-09-28
Status: Confirmed

Decision: Daniel Boyd explicitly approved SLICE-001-measured-analysis.md on 2026-09-28 in the project conversation. The slice is active; other slices remain proposals.

Consequences: Implement, verify and provide the native walkthrough inside the approved boundary. Final owner walkthrough approval is still required before marking the slice Done.

Revisit when: New scope is proposed or a required gate cannot be satisfied.

## D-013: Manual speech before automatic suggestions
Date: 2026-09-28
Status: Confirmed
Supersedes: D-004

Decision: Plan manual, user-confirmed speech mastering before integrating automatic suggestions. Model selection is deferred until the manual reference works. Daniel explicitly accepted this sequence after the measured-report walkthrough. This confirms sequence, not approval of the newly written detailed brief.

Because: It separates gain-planning correctness from errors in speech detection. The owner can inspect and correct the anchor.

Options considered: manual first; model first; both together. Manual first was recommended and accepted.

Consequences: Automatic speech no longer blocks Slice 002. Unknown language/model quality remains recorded in U-001 and must close before later model-dependent work.

Revisit when: Manual mastering passes or the owner requests automatic suggestions first.

## D-014: Original mastering and preview boundary
Date: 2026-09-28
Status: Confirmed

Decision: SLICE-002-dialogue-mastering.md defines mono/stereo original gain planning with explicit programme or manual-speech reference, linked rendering, lossless output, full staged preview and independent verification. Daniel approved the complete brief on 2026-09-28.

Because: Existing reports are informational and existing mastering uses FFmpeg. The user needs an audible, reviewable result without coupling the first original renderer to models, lossy codecs or video remux.

Options considered: keep only the FFmpeg foundation; original manual mastering with lossless preview; combine automatic speech, new mastering and all output formats. Recommend the bounded middle option.

Consequences: R-007 authorizes only S2-001 through S2-009 under the approved brief. No report v1 break, video session schema, public API, paid tool, cloud processing, release or merge is introduced. The growth tally is in MASTERING-RESEARCH.md.

Revisit when: The owner amends the brief, M1 is infeasible, or listening exposes a required scope change.

## D-015: Planner and limiter feasibility
Date: 2026-09-28
Status: Open

Decision: Use the preregistered MASTERING-M1.md Swift shared envelope with the existing local FFmpeg alimiter, three candidates maximum. Eight focused tests passed, including five-rate impulse timing/peak tests, constant PCM identity, energy pooling, phase-opposed stereo, noise hold and safe refusal. No numerical tolerance changed. Listening quality remains unproven. The real-film failures reopened planner feasibility; MASTERING-M1.md records the bounded feedback and smoothing experiments. Generated success is not whole-film acceptance.

Because: Loudness compliance alone does not establish transparent or comfortable processing. A custom limiter cannot be assumed better than a tested reusable component.

Options considered: a Swift planner with an existing local limiter; Swift planner and narrowly implemented oversampled limiter; continue the legacy FFmpeg path outside the new engine. Evidence and dependency rights choose the first two or stop for revision.

Consequences: No new app runtime dependency is installed by this plan. The owner-authorized NumPy/SciPy investigation uses an isolated local research environment and has not been integrated into the app. Record rights and numerical/latency evidence before integration. Do not widen registered acceptance tolerances to fit results. A six-excerpt owner pack is now prepared at separately declared wider requests; its existence does not resolve the failed 3 LU request or close this decision.

Revisit when: M1 ends, a limiter fails peak tests, or iteration exceeds its fixed bound.

## D-016: Listening material rights
Date: 2026-09-28
Status: Confirmed

Decision: LISTENING-MANIFEST.md records official Sintel CC BY 3.0 permissions before local acquisition. Acquired-source hashes are recorded; comparison excerpt selections remain pending. Generated fixtures do not prove speech quality; English-only material does not establish multilingual quality.

Because: Local research permission and redistribution rights are different. Public CI must not receive private or restricted media.

Options considered: redistributable licensed examples; user-authorized local excerpts with no redistribution; newly recorded consented speech. Use permitted material that covers S2-008; request an owner decision if coverage cannot be obtained.

Consequences: Owner-only listening is a scoped screen, not a formal listener study. No personal film title, path or audio is committed to the public repository. Corpus failure blocks quality acceptance, not an excuse to invent results.

Revisit when: The manifest is established or required coverage cannot be licensed.

## D-017: Bounded static HDR10 preservation
Date: 2026-09-29
Status: Confirmed
Owner approval: 2026-09-29, “Yes, I approve.”

Decision: Start with explicit software HEVC/MKV preservation for stable 10-bit limited-range PQ/BT.2020 sources, a complete source frame audit and complete staged-output verification. SLICE-004-static-hdr10.md defines the boundary. Tone mapping, HLG, dynamic metadata and hardware encoding remain separate.

Because: HDR10-FEASIBILITY.md demonstrates numerical lossless round-trip and static metadata retention locally, while the current queue does not verify color. A single-frame probe cannot establish whole-stream stability or coverage.

Options considered: simply relax the SDR guard; implement all HDR modes together; add one explicitly bounded checked workflow. Propose the bounded workflow.

Consequences: New internal color intent and typed audit data, backward-compatible session default, extra source/output scan time, no new dependency. Metadata preservation is narrower than visual correctness or universal HDR compatibility.

Revisit when: The audit cannot reliably identify the declared supported metadata, fixtures fail, or a later HDR workflow is approved.

## D-018: On-demand filtered picture comparison
Date: 2026-09-29
Status: Confirmed
Owner approval: Approval of the presented brief and delegation of autonomous non-audio development, 2026-09-29.

Decision: SLICE-005-filtered-picture-preview.md proposes a source/filtered still comparison using shared queue picture operations and actual timestamps. Initial coverage is explicit SDR BT.709 with bounded local rendering.

Because: WorkspaceView currently displays unfiltered source playback, so users cannot inspect crop, resize or deinterlace effects before encoding.

Options considered: matched still comparison; encoded motion sample; source-only frame stepping. Recommend still comparison first, with temporal-filter identity checked before UI implementation.

Consequences: Shared typed picture plan, temporary image ownership and stale-result handling. No persistence migration or dependency. Motion playback, exact frame navigation, compression comparison, HDR and audio stay outside this brief.

Revisit when: Owner approves or changes the brief, or M1 cannot establish frame identity within its bounded investigation.

## Autonomous continuation, 2026-09-29

Owner explicitly requested autonomous reasonable decisions until program completion, excluding audio tests, or interruption in the morning. This supersedes repeated approval requests for reversible non-audio slice selection. Continue to write concrete briefs and decision/evidence records before implementation; record subsequent scope choices as delegated. No merger, release, credential changes, license selection or owner visual/listening acceptance is inferred. Stop for a genuine external blocker, preserve audio work, and report remaining production gaps honestly.

## D-019: Reusable presets and settings undo
Date: 2026-09-29
Status: Confirmed

Decision: Build SLICE-006-custom-presets.md under owner delegation for autonomous reasonable non-audio work.

Because: Reusing validated encoding settings and recovering accidental edits improves the existing native workflow without requiring audio listening or another display/hardware platform.

Options considered: source-independent recipes with explicit exclusions; full-session clones carrying paths and stream indices; defer presets for another codec. Choose recipes and bounded settings undo.

Consequences: Local validated library with conflict protection, explicit import/export and no queue/media execution. No license or release choice.

Revisit when: A recipe needs source-aware mappings, Audio Lab values or cloud sync.

## D-020: Validated source orientation
Date: 2026-09-30
Status: Confirmed

Decision: Build SLICE-007-source-orientation.md under the owner's autonomous non-audio delegation.

Because: Advanced queue export refuses rotated sources, including ordinary portrait clips. The shared picture plan makes consistent crop/preview geometry possible without saving source orientation in recipes.

Options considered: implicit FFmpeg autorotation; explicit validated source transforms; manual arbitrary rotation. Choose explicit right-angle transforms with full matrix validation. The extra parser and output check prevent a mirrored or perspective matrix from being mistaken for a pure angle. No data migration or dependency is needed. Existing source/output protection remains.

Consequences: Initial scope is progressive, square-pixel 8-bit SDR with deinterlacing Off for rotated sources. Both preview sides are upright; crop follows upright coordinates. Unsupported transformations fail explicitly. HDR remains unrotated only.

Revisit when: Real-camera fixtures require mirrored, anamorphic, translated or per-frame transforms, or owner requests manual orientation controls.

## D-021: Read-only queue preflight
Date: 2026-09-30
Status: Confirmed

Decision: Build SLICE-008-queue-preflight.md under autonomous non-audio delegation.

Because: An overnight queue can currently complete earlier jobs before discovering a preventable source, output or configuration issue in a later item. Users need a review action before spending encoding time.

Options considered: optional read-only review; mandatory full decode/encode dry run; continue discovering problems only during execution. Choose a bounded preliminary review with explicit deferred HDR and hardware checks. This adds no saved format, dependency or automatic execution. A full dry run would be expensive and still could not promise future filesystem state.

Consequences: Per-item current observations, cancellation, invalidation on intent changes and no output/recovery writes. Execution remains authoritative. No licensing, release or listening decision.

Revisit when: Scheduling, disk-space estimates or full-media preflight become a separately scoped requirement.

## D-022: Report batch staging cleanup
Date: 2026-09-30
Status: Confirmed

Decision: Build SLICE-009-batch-cleanup.md under autonomous non-audio delegation.

Because: BatchController silently discards removal failures after encoding. An overnight batch can otherwise leave temporary data without explaining what happened, unlike the native exporter.

Options considered: keep best-effort removal; reuse bounded native cleanup with explicit outcome reporting; sweep old staging on launch. Choose reporting and the shared primitive. Sweeping old data needs a separate ownership and recovery design.

Consequences: A published file remains Completed, while a cleanup warning stops the current batch and persists in existing status detail. Cancellation and encoder failures retain their primary outcome. No new stored fields, dependency, release or audio scope.

Revisit when: Explicit stale-staging recovery or filesystem-specific qualification is scoped.

## D-023: Inspect chapters and attachments
Date: 2026-09-30
Status: Confirmed

Decision: Build SLICE-010-container-inspection.md under autonomous non-audio delegation.

Because: The native inspector does not expose chapters or useful embedded-file metadata. Making container contents visible is a bounded prerequisite for later chapter editing and preservation verification. Existing inspection tasks can also race across source changes.

Options considered: metadata-only inspection using the current probe; immediate chapter editing and attachment extraction; defer container features. Choose inspection and request identity protection. Generated MKV and MP4 spikes confirmed chapters, attachments and cover-art disposition are available without dependencies or schema changes.

Consequences: Read-only bounded native sections with truthful missing/invalid metadata and stale-request protection. No extraction, font loading, chapter seeking, output-preservation guarantee, audio acceptance or release decision.

Revisit when: Chapter edits, remux or safe attachment extraction become an explicit slice.

## D-024: Verify retained container contents
Date: 2026-09-30
Status: Confirmed

Decision: Build SLICE-011-container-preservation.md under autonomous non-audio delegation after Slice 010 hosted closure.

Because: Successful encoding alone does not establish that retained flat chapters and embedded attachments survived. Generated CLI spikes show MP4 changes chapter gaps, while MKV preserves them.

Options considered: trust exit status; compare bounded metadata and attachment SHA-256 before publication; full container conformance. Choose scoped comparison using existing ffprobe without new dependencies.

Consequences: Reject unsupported MP4 chapter gaps before encoding and staged mismatches before publication. Missing/empty chapter titles are equivalent; other title content is exact. Existing trim and attachment mapping rules remain. No audio, release or merge scope.

Revisit when: Chapter editing, editions or remux preservation are scoped.

## D-025: Qualify full destination failures
Date: 2026-09-30
Status: Confirmed

Decision: Execute Slice 012 using a bounded disposable disk image under autonomous non-audio delegation.

Because: Actual capacity exhaustion remains an explicit output-safety gap after publication and cleanup verification.

Options considered: error injection alone; a small isolated filesystem filled with generated data; filling a physical disk. Choose the isolated fixture and real production queue path. Never fill owner storage directly.

Consequences: Local opt-in integration and native qualification, exact-mount ownership checks, no default hosted image mounting, no audio or release scope.

Revisit when: Removable/network filesystems or capacity estimation are scoped.

## D-026: Verify resized raster dimensions
Date: 2026-09-30
Status: Confirmed

Decision: Build Slice 013 under autonomous non-audio delegation after Slice 012 closure.

Because: EncodePlan leaves expected width and height absent for resized presets, so successful encoding can publish the wrong raster size. Generated scale outputs show rounding and pixel aspect need careful separation.

Options considered: trust filter arguments; hard-code one filter version's rounding; independently verify bounded raster fit with an explicit less-than-two-pixel rounding allowance. Choose the invariant check without changing filters or claiming display-aspect preservation.

Consequences: Verify output dimensions before publication and report scoped dimensions. Existing HDR/orientation and container checks remain. No schema, audio, release or merge change.

Revisit when: Explicit anamorphic display geometry or different scale algorithms are scoped.

## D-027: Responsive batch publication and access review
Date: 2026-09-30
Status: Confirmed

Decision: Build Slice 014 under autonomous non-audio delegation after Slice 013 closure.

Because: A native process sample found the app main thread blocked in the exclusive publication link syscall. Selecting the generated destination with the native folder picker resolved the next run, exposing a need for responsive controls and explicit per-job access review.

Options considered: leave synchronous publication; add an early timeout; dispatch the same primitive and await its true outcome. Choose background execution without abandoning the in-flight operation, so cleanup and cancellation cannot hide a successfully published result.

Consequences: Batch-only wrapper, ephemeral finishing state, preserved cancellation outcome and native access panels that never rewrite intent. Existing persisted Verifying phase and journal schema stay unchanged. Other I/O sites and exporters remain explicit limitations.

Revisit when: Other filesystem waits or durable bookmark persistence are scoped.

## D-028: Verified external plain SRT subtitles
Date: 2026-09-30
Status: Confirmed

Decision: Build Slice 015 under autonomous non-audio delegation after Slice 014 hosted closure.

Because: External subtitles are an explicit release-ledger gap. Generated MKV/MP4 spikes preserve plain multilingual cues but silently alter overlapping intervals, markup and line-edge spaces. Successful muxing and stream counts alone are insufficient.

Options considered: unrestricted subtitle import; one bounded plain SRT with exact staged cue verification; defer subtitles until a full styled-subtitle editor. Choose one source-specific external SRT, captured fresh per attempt, with independently decoded text/timing checks before publication.

Consequences: Explicit plain-format/timeline refusals; separate embedded-track and additional-file controls; balanced transient file access; sessions v6 and journals v5; no source references in presets. Keep existing output ownership and verification. No styling, burn-in, retiming, HDR/trim with external captions, audio acceptance, signing, merge or release scope.

Revisit when: Multiple external tracks, subtitle retiming/styling or durable bookmark access become their own scoped work.

## D-029: Attached workspace file dialogs with captured intent
Date: 2026-09-30
Status: Confirmed

Decision: Build Slice 016 under autonomous non-audio delegation after Slice 015 hosted closure.

Because: Slice 015 reproduced an invisible standalone session chooser and fixed it with an attached sheet. Source, destination and queue-reference dialogs still use standalone modal loops. A common callback lifecycle should also protect workspace intent when asynchronous source loading or other changes occur while a chooser is open.

Options considered: keep mixed panel styles; replace every app dialog; scope only five workspace file commands with a small injectable presenter and request identity. Choose the bounded workspace scope, retaining the replacement confirmation and existing data validation.

Consequences: Attached source/folder/session/reference dialogs; one in-flight workspace request; captured save contents; cancelled, duplicate and stale callbacks cannot change newer intent. Existing document I/O remains bounded synchronous work. Audio, presets, Quick Export, persistent bookmarks and broad I/O migration are excluded.

Revisit when: Other dialogs, durable permission recovery or broader filesystem responsiveness are scoped.

## D-030: Verify declared display proportions
Date: 2026-09-30
Status: Confirmed

Decision: Build Slice 017 under autonomous non-audio delegation after Slice 016 hosted closure.

Because: Generated files can share raster dimensions while a changed sample aspect ratio alters their displayed shape. Twelve software crop/fit exports preserve exact rational display proportions, giving an independent validation contract beyond frame width and height.

Options considered: assume square pixels; rewrite every source to square pixels; compare declared source/output display fractions while keeping genuinely unknown source metadata explicit. Choose the last option without changing filters or inventing missing information.

Consequences: Exact reduced-rational stream geometry verification when a valid source ratio exists; explicit unavailable result for unknown source ratio; wrong or missing output ratio fails a known contract. No new persistent fields, picture filters, audio, broader HDR/orientation or release scope.

Revisit when: Pixel-shape overrides, square-pixel conversion, frame-varying metadata or broader anamorphic-film qualification are scoped.

## D-031: Step filtered previews by decoded timestamp
Date: 2026-09-30
Status: Confirmed

Decision: Build Slice 018 under autonomous non-audio delegation after Slice 017 hosted closure.

Because: Current filtered preview requires typed time requests. Generated variable-rate gaps demonstrate that a guessed reciprocal-FPS step can skip or repeat pictures, while decoded rational timestamps identify adjacent frames and match full-history filtered pixels.

Options considered: fixed frame-rate offsets; native player stepping disconnected from filtered images; bounded decoded-timestamp discovery followed by verified full-history rendering. Choose the third, preserving the existing preview scope and temporal context.

Consequences: Previous/next preview controls, bounded streaming neighbor discovery, source identity and rational result checks, explicit trim boundaries and stale/cancel/failure behavior. No motion playback, accelerated seeking, new encoding behavior, audio, saved-schema change or distribution action.

Revisit when: Motion preview, durable indexes, broader picture formats or long-source performance are scoped.
