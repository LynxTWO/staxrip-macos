# StaxRip Mac Slice 035: Compact source preview
Version: 0.1. Date: 2026-10-01. Status: Done with evidence under D-062 / R-044.

SLICE STATE
Milestone: All four gates accepted at 24e8f2b; hosted run 36856655748.
Blocked by: None within scope.
Evidence so far: COMPACT-PREVIEW-EVIDENCE.md, native clock continuity, local/hosted 244 tests, optimized build and audit.
Last audit: 2026-10-01.

## 1. What the slice proves

The user can give settings more room without losing source playback position. The existing full preview remains the default.

## 2. The walkthrough

Open a generated silent video, start playback, select Compact preview, and continue watching at the same position. Expand with Option-Command-P. Repeat at the minimum window width in both appearances. Relaunch to check the display preference, then restore a saved source and verify that its review action remains available.

## 3. In scope, with build order

M1: One app-only Boolean preference, 150/230-point frame selection and descriptive footer control. M2: Native playback, layout, keyboard, persistence and recovery checks. D-063 input qualification is recorded as a rejected experiment. M3: Optimized build and full local/hosted regression.

## 4. Out of scope

Encoding, audio/listening, source access, player replacement, new transport, saved session schemas, automatic layout thresholds, dependencies, merge and release.

## 5. Stubs and debts

No new stub. Existing native media compatibility and filesystem-access limitations remain unchanged.

## 6. Modules touched

WorkspaceView frame and footer. The D-063 border experiment was rejected without a retained product change. NativeVideoPreview is inspected but does not need modification.

## 7. Data subset

One app-only display preference, default false. No media paths or session fields.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S35-001 | Compact and full preview controls remain clear at minimum width in light/dark; shortcut is equivalent | Native screenshot and accessibility/keyboard walkthrough | preview-layout |
| S35-002 | Resizing preserves actual playback position and continued playback; preference survives relaunch | Generated silent movie with observable time, native playback and restart | preview-continuity |
| S35-003 | Restored-source and unavailable-preview cards keep full-height remedies; resize never changes encoding intent | Branch inspection and native restored-source review | preview-recovery |
| S35-004 | Existing behavior remains qualified | Full local/hosted suite, optimized build, planning audit | preview-regression |

## 9. Verification evidence required

Use generated media only. Compare actual native time before and after resizing while playing. Do not infer continuity from object identity alone. Retain the same player branch and avoid new lifecycle hooks. Test app-only preference independently of saved recipe state. Native screenshots and accessibility trees qualify the scoped controls, not heard VoiceOver or a whole-app accessibility claim.

## 10. Guardrails

Retain source playback's unfiltered label and explicit unavailable/review guidance. Do not shrink remedy cards or hide required actions. Keep the user's size choice reversible. No owner audio review is requested.

## 11. Definition of done

All four criteria have scoped evidence at the final product head. Record failures and remaining limits; do not claim program completion.

## 12. What this unlocks

More settings space in the existing workspace, without creating another playback implementation.

Approved for build by: Owner overnight autonomous non-audio and design delegation, 2026-10-01; D-062 / R-044.
