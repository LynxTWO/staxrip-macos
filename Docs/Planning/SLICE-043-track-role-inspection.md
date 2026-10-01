# StaxRip Mac Slice 043: Inspect track identity and declared roles
Version: 0.1. Date: 2026-10-01. Status: Approved for build under D-081 / R-053.

SLICE STATE
Milestone: M1 and M2 implemented; focused checks passed; native and ordinary regression next.
Blocked by: None within scope.
Evidence: TRACK-ROLE-EVIDENCE.md records seven focused checks and actual immutable source metadata. Native/regression pending.
Last audit: 2026-10-01.

## 1. What the slice proves

A user can distinguish named caption/audio tracks and inspect their declared default, forced, hearing-accessibility, visual-accessibility and commentary flags inside the app. This closes a decision-information gap at Architecture section 10's inspection/track-routing boundary. It complements the accepted caption playback controls without changing encoding behavior.

## 2. The walkthrough

Open a generated MKV and inspect its tracks. See the source's title and language plus the five reported flags, with clear Set, Not set, Not reported or Invalid value states. Choose tracks uses the same bounded labels and a compact summary of these declared flags. Select a track, cancel and confirm existing choices remain; apply a chosen subset and reopen to see that the original stream indices still own selection. Open the prior generated caption output as a source and inspect its different default/forced flags. Nothing is played, edited in the media file, or exported.

## 3. In scope, with build order

M1: A small read-only track presentation helper reuses ContainerInspection's bounded display and case-insensitive tag lookup. Title uses title then name (for containers exposing a track name); missing labels remain Unspecified. Expose exactly five named flag fields. Integer one is Set, zero is Not set, absent is Not reported, other integers are Invalid value. Compact routing text lists set flags and marks incomplete/invalid metadata without converting unknown to false. These values remain reported hints, not verified accessibility content or player behavior.

M2: Integrate helper in MediaInspectorView and TrackRoutingView. Keep existing indices, nil/explicit selection meaning, cancel/apply behavior, controller/probe ownership, card limits, accessibility fields and keyboard exits. Show flag definitions where they aid decisions. Sanitize existing language/title/codec/layout labels in the touched routing rows using the same current display bound.

M3: Focused pure metadata and actual generated read-only tests, native inspector/routing walkthrough, ordinary local/hosted regression, optimized build and selected planning audit. Reuse the existing generated caption fixture for native observation; no new corpus or benchmark service.

## 4. Out of scope

Media flag editing, encoding/publication, saved schemas, new track selection rules, audio DSP/listening, player qualification, source parsing changes, broad inspector redesign, dependencies, deadline/scheduling changes, merge and release.

## 5. Stubs and debts

No stub. These five flags are a selected metadata view, not an exhaustive disposition listing or a content certification. Heard VoiceOver and broader platform/player checks remain separate.

## 6. Modules touched

ContainerInspection or adjacent TrackInspection helper; MediaInspectorView; TrackRoutingView; focused tests through existing MediaProbe and generated local sources. No BatchController, EncodePlan, export, session or journal behavior changes.

## 7. Data subset

Only process-local presentation of existing probe stream index, codec, language/title/name/layout strings and five disposition integers. No new stored data. Display truncation and control-character replacement do not mutate source metadata. Unknown values stay explicit.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S43-001 | Displayed identity and five flags faithfully distinguish set, unset, absent and invalid data | Bounded/Unicode/control-character/case-insensitive title and language checks; all flag states and compact-summary checks | track-role-presentation |
| S43-002 | Actual probed roles correspond to generated file metadata without writes | Real MKV source with title, default, forced and hearing flags, source digest/listing unchanged | track-role-source |
| S43-003 | Native inspector and routing communicate flags and retain selection ownership | Generated source/output views, keyboard dismissal, cancel/apply/reopen subset review; owner journal unchanged | track-role-native |
| S43-004 | Existing behavior remains qualified | Ordinary local/hosted regression, optimized build, selected audit, no export/schema/scheduling changes | track-role-regression |

## 9. Verification evidence required

R-053 authorizes bounded generated tests through existing read-only probe seams and one native inspector/routing walkthrough. Consequence class: user_data for informed output-track selection. Existing actual no-mutation and selection tests remain. No listening, export or journal replacement required. Record direct observations, build identities, test counts/skips and limitations in TRACK-ROLE-EVIDENCE.md.

## 10. Guardrails

Never label missing/invalid flags as Not set. Flags describe source declarations, not measured content or guaranteed player selection. Do not change saved indices, source files, permissions or conversion defaults. No generic metadata parser or new runtime. If the historical hosted mastering cancellation failure recurs, reopen qualification without another blind retry or diagnostic expansion.

## 11. Definition of done

All four gates have scoped evidence and source/journal preservation is confirmed. No heard accessibility, codec capability or player-interoperability claim.

## 12. What this unlocks

Informed review of imported and exported track roles. Independent embedded metadata editing and broader track recipes remain later decisions.

Approved for build by: Owner standing autonomous non-audio completion delegation, 2026-10-01; D-081 / R-053. Delegated to AI recommendation.
