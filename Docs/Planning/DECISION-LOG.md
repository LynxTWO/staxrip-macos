# StaxRip Mac Decision Log
Version: 0.1 Draft. Date: 2026-09-28.

## Index

| ID | Date | Decision | Status | Superseded by |
| --- | --- | --- | --- | --- |
| D-001 | 2026-09-28 | Native offline product | Confirmed | |
| D-002 | 2026-09-28 | Typed local analysis seams | Proposed | |
| D-003 | 2026-09-28 | Analysis before gain changes | Proposed | |
| D-004 | 2026-09-28 | Speech model selection | Open | |
| D-005 | 2026-09-28 | Later preservation work | Deferred | |
| D-006 | 2026-09-28 | Public repository | Confirmed | |
| D-007 | 2026-09-28 | Hosted checks and local hardware tests | Proposed | |
| D-008 | 2026-09-28 | Project license | Open | |
| D-009 | 2026-09-28 | Full-film performance targets | Assumed | |
| D-010 | 2026-09-28 | SignalForge reuse first | Superseded | D-011 |
| D-011 | 2026-09-28 | Swift meter adaptation | Confirmed | |
| D-012 | 2026-09-28 | Slice 001 owner approval | Confirmed | |

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
Status: Proposed

Decision: Keep Swift request/report interfaces; choose meter implementation after D-010.

Because: Separates UI, measurement and rendering without presuming a rewrite.

Options considered: retain current behavior; adopt the stated scoped change. Detailed reuse alternatives are in SIGNALFORGE-REUSE.md.

Consequences: implementation follows the approved slice boundary; an Open or Proposed decision is not approval.

Revisit when: The reuse spike finds a lower-cost tested boundary.

## D-003: Analysis before gain changes
Date: 2026-09-28
Status: Proposed

Decision: Slice 001 delivers a usable measured report; slice 002 adds original gain planning.

Because: Gain changes require trustworthy measurements.

Options considered: retain current behavior; adopt the stated scoped change. Detailed reuse alternatives are in SIGNALFORGE-REUSE.md.

Consequences: implementation follows the approved slice boundary; an Open or Proposed decision is not approval.

Revisit when: Meter evidence or user needs change the sequence.

## D-004: Speech model selection
Date: 2026-09-28
Status: Open

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
