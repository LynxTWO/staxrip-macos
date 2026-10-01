# StaxRip Mac Slice 024: A live workspace recipe
Version: 0.2. Date: 2026-09-30. Status: Accepted within evidence limits under D-038 / R-028.

SLICE STATE
Milestone: Local/native/hosted checks passed at daf27e6; hosted run 36811284038.
Blocked by: None.
Evidence so far: WORKSPACE-RECIPE-EVIDENCE.md; final product daf27e6, local 195 tests and native correction/keyboard/layout checks.
Last audit: 2026-09-30.

## 1. What the slice proves

A user can review the current advanced configuration beside their source, jump directly to a setting, correct it and see the recipe update before adding a queue item. Current four-row output summary omits material trim, track and subtitle choices. The owner invites a distinctive native design; usefulness of this particular treatment is a design hypothesis, not user research.

## 2. The walkthrough

Open Workspace. Read the recipe's picture, video, audio and subtitle intent. Activate a recipe row to select that settings tab. Change a setting, then undo it; the summary follows current configuration. Review name and destination, add the configuration to the queue and inspect its retained choices. Demo content remains explicitly a demo. Queue review remains the source-compatibility check.

## 3. In scope, with build order

M1: A pure configuration summary that reuses PicturePlan and distinguishes nil/all track selection from an empty selection, removed tracks, external captions, trim and color intent. M2: Native recipe rail, selected-row semantics and direct tab navigation; scrollable output panel with persistent queue action. M3: focused semantic checks, full regression, local app build and native demo/real-source, correction, appearance and queue walkthrough, then hosted acceptance.

## 4. Out of scope

Source probing, validated compatibility predictions, file-size estimates, processing-order promises, encoder changes, queue changes, persistence, audio algorithms/listening, full application redesign, merge, release and credentials.

## 5. Stubs and debts

No stubs in this path. The recipe describes requested settings; it must not claim readiness, measured output geometry or successful verification. Future source-aware plan review is separate.

## 6. Modules touched

WorkspaceView, a new small recipe-summary model and native recipe view, focused tests and planning evidence. WorkspaceModel.config and tab remain authoritative. Existing PicturePlan supplies filter wording; EncodePlan is read-only evidence for stream semantics.

## 7. Data subset

Read current EncodeConfiguration. No serialized fields. Row activation only updates WorkspaceModel.tab; existing editors own mutations and undo. No new source reads or background work.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S24-001 | Intent distinguishes all/selected/empty/removed streams, trim, crop/resize, color, backend and external captions without measured claims | Focused summary edge cases compared with existing plan semantics | recipe-intent |
| S24-002 | Each recipe row opens its settings; edits and undo update intent, and queue retains configuration | Native demo and generated-source walkthrough | recipe-correction |
| S24-003 | Light/dark, minimum window and long summary remain readable; queue action stays reachable; accessible selected labels are meaningful | Native visual, keyboard and accessibility inspection | recipe-native |
| S24-004 | Existing behavior remains intact | Full local and hosted regression plus app build and planning audit | recipe-regression |

## 9. Verification evidence required

Use generated media only. Test semantic counterexamples, not every UI string. Inspect the real native app in both appearances at the supported minimum window and a larger size. Existing full regression remains unchanged, with opt-in exclusions reported. Spoken VoiceOver and owner aesthetic approval remain separate.

## 10. Guardrails

No summary promises source support or estimated output size. No source or prior output replacement. Editing a recipe does not start work. Retain existing queue-action validation and native keyboard controls. Avoid animations or color-only state. Source/encoding/audio policy changes require a new slice.

## 11. Definition of done

S24-001 through S24-004 have scoped evidence and audit passes. Record the final tested head and untested platforms. Owner review can refine the design later; automated/native inspection is not participant research.

## 12. What this unlocks

A shared vocabulary for future plan comparison and result review. Later work can address restored-source access and broader frame-timing qualification independently.

Approved for build by: Owner autonomous non-audio delegation renewed 2026-09-30, with explicit creative design latitude; D-038 / R-028.
