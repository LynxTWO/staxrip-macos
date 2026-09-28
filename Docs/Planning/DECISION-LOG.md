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
| D-014 | 2026-09-28 | Original mastering and preview boundary | Proposed | |
| D-015 | 2026-09-28 | Planner and limiter feasibility | Open | |
| D-016 | 2026-09-28 | Listening material rights | Open | |

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
Status: Proposed

Decision: SLICE-002-dialogue-mastering.md defines mono/stereo original gain planning with explicit programme or manual-speech reference, linked rendering, lossless output, full staged preview and independent verification. Its detailed defaults and bounds await owner approval.

Because: Existing reports are informational and existing mastering uses FFmpeg. The user needs an audible, reviewable result without coupling the first original renderer to models, lossy codecs or video remux.

Options considered: keep only the FFmpeg foundation; original manual mastering with lossless preview; combine automatic speech, new mastering and all output formats. Recommend the bounded middle option.

Consequences: Proposed R-007 authorizes only S2-001 through S2-009 upon brief approval. No report v1 break, video session schema, public API, paid tool, cloud processing, release or merge is introduced. The growth tally is in MASTERING-RESEARCH.md.

Revisit when: The owner amends the brief, M1 is infeasible, or listening exposes a required scope change.

## D-015: Planner and limiter feasibility
Date: 2026-09-28
Status: Open

Decision: Slice 002 M1 must choose and preregister smoothing, gain/hold bounds, look-ahead, limiter, latency compensation and a finite render/refinement limit before the dependent renderer is built. One working day maximum for this spike after build approval.

Because: Loudness compliance alone does not establish transparent or comfortable processing. A custom limiter cannot be assumed better than a tested reusable component.

Options considered: a Swift planner with an existing local limiter; Swift planner and narrowly implemented oversampled limiter; continue the legacy FFmpeg path outside the new engine. Evidence and dependency rights choose the first two or stop for revision.

Consequences: No new dependency is installed by this plan. Record rights and numerical/latency evidence before integration. Do not widen registered acceptance tolerances to fit results.

Revisit when: M1 ends, a limiter fails peak tests, or iteration exceeds its fixed bound.

## D-016: Listening material rights
Date: 2026-09-28
Status: Open

Decision: Before Slice 002 M2 listening acquisition/use, establish a small local manifest of source permissions, hashes, excerpt times, languages and intended use. Generated numerical fixtures do not prove speech quality.

Because: Local research permission and redistribution rights are different. Public CI must not receive private or restricted media.

Options considered: redistributable licensed examples; user-authorized local excerpts with no redistribution; newly recorded consented speech. Use permitted material that covers S2-008; request an owner decision if coverage cannot be obtained.

Consequences: Owner-only listening is a scoped screen, not a formal listener study. No personal film title, path or audio is committed to the public repository. Corpus failure blocks quality acceptance, not an excuse to invent results.

Revisit when: The manifest is established or required coverage cannot be licensed.
