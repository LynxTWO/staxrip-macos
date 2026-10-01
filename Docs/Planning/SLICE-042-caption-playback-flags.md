# StaxRip Mac Slice 042: Caption playback choices
Version: 0.1. Date: 2026-10-01. Status: Approved for build under D-080 / R-052.

SLICE STATE
Milestone: M1 passed; M2 implementation next.
Blocked by: None within delegated scope.
Evidence: CAPTION-FLAGS-EVIDENCE.md records M1; no product code yet.
Last audit: 2026-10-01.

## 1. What the slice proves

A user adding MKV captions can choose default and forced playback flags and receive a file whose flags were checked before publication. Existing Automatic choices keep their previous behavior. This extends Architecture section 10's video-plan and track choices; without it, users cannot express preferred or forced external captions.

## 2. The walkthrough

Open a source, add two SRT files, choose Default for one and Forced for the other. Read that a chosen default replaces other caption defaults, including retained embedded tracks, and that players can override these hints. Save and reopen a session, reorder or replace a caption file, queue the job and inspect the completed file. A duplicate explicit default or MP4 choice receives a specific correction message without silently changing intent. Original files and existing outputs remain unchanged.

## 3. In scope, with build order

M1: A ten-minute local generated MKV experiment compares ordinary remux defaults with explicit subtitle choices, including two silent audio tracks with no input default, an embedded default/forced track and added SRT tracks. Verify all default/forced bits, preserved unrelated hearing-impaired metadata and complete caption text/timing. No app code until this dependency closes.

M2: Add an optional typed external-caption playback choice: absent means Automatic; explicit values are Optional, Default, Forced, Default and forced. At most one explicit default. An explicit default clears the default bit on all other output captions; forced bits on retained tracks stay unchanged. Otherwise Automatic tracks use the previous default-selection result. Explicit Optional or Forced can remove an automatically assigned default without creating a replacement. Keep unrelated input flags with incremental disposition arguments. Preserve the prior automatic defaults for mapped video/audio streams even though FFmpeg disposition options disable its automatic pass. MKV only for explicit choices; MP4 with Automatic remains unchanged.

M3: Central process-local flag plan and pre-publication default/forced verification for mapped video/audio/caption streams; existing text/title/language/timing checks remain. Add accessible per-track controls and explanation. Save choices through session version 9 and recovery version 8, retaining older reads when the field is absent. Add bounded actual-controller tests and one native generated walkthrough. Ordinary local/hosted regression, optimized build and selected planning audit close the slice.

## 4. Out of scope

MP4 explicit flags, editing embedded-track flags independently, subtitle burn-in, player certification, audio DSP/listening, HDR expansion, public API, dependencies, source deletion, merge and release. No deadline or scheduling changes.

## 5. Stubs and debts

No stub. Flags are container metadata; player selection behavior and preferences remain outside the verified claim. Broader container/track controls connect through the existing plan later.

## 6. Modules touched

ExternalSubtitle typed metadata/equality; ExternalCaptionList validation and replacement; SubtitleOptionsView; EncodePlan and a small CaptionPlaybackPlan; BatchController's existing pre-publication checks; SessionDocument and BatchJournal version validation. Existing actual caption integration, persistence and refusal tests supply the test seams.

## 7. Data subset

Optional playback enum inside each external caption reference. Missing or null decodes as Automatic; unknown values fail. Legacy session versions 1 through 8 and recovery 1 through 7 must reject a non-null choice. New versions validate workspace and every queued reference. No stored permission, path expansion, preset source binding or automatic migration write. A file replacement preserves metadata; changed choices invalidate an outstanding picker intent through equality.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S42-001 | Actual MKV flags match intent without changing prior audio/video defaults or unrelated embedded flags | M1 complete generated metadata/text comparison | caption-flags-feasibility |
| S42-002 | Typed choices survive persistence, reorder and replacement; old and malformed data fail appropriately | Session/recovery, stale picker, equality, duplicate/default and MP4 refusal tests | caption-flags-data |
| S42-003 | Actual controller exports retain complete captions and expected default/forced flags | Generated copy/transcode, embedded/no-embedded and trim combinations, independent output decode | caption-flags-output |
| S42-004 | Altered output flags prevent publication and next-job execution | Actual encoder wrapper corrupts staged flags; unchanged originals and settled staging | caption-flags-refusal |
| S42-005 | Native controls explain choices and correction, persist intent and produce a checked file | Native generated walkthrough with accessibility inspection and independent output probe | caption-flags-native |
| S42-006 | Existing paths remain qualified | Ordinary local/hosted regression, optimized build, selected audit | caption-flags-regression |

## 9. Verification evidence required

R-052 authorizes the bounded M1 local experiment and targeted tests through real existing controllers. Generated media only in CI; no owner media or private paths committed. Compare full caption documents, source/prior bytes and publication state, not just constructed arguments. Silent audio streams may check container metadata; no audio algorithm or listening changes. Native journal backup and guarded restoration occur only with the app normally closed. Record counts, skips, identities and limitations in CAPTION-FLAGS-EVIDENCE.md.

## 10. Guardrails

No explicit flags means no new disposition argument or output contract. Read actual mapped source flags for explicit plans. A missing/nonbinary default or forced field cannot certify intent. Verification failure refuses publication. Preserve track order and all existing checks, cancellation bounds and publication ownership. The historical hosted mastering cancellation recurrence reopens qualification without another blind retry or diagnostic expansion.

## 11. Definition of done

All six gates have scoped evidence; owner state restored. Technical native inspection does not stand for a heard VoiceOver review or player interoperability. No production completion claim.

## 12. What this unlocks

Expressive caption track selection with inspectable results. MP4 and independent embedded-track editing remain later decisions.

Approved for build by: Owner standing autonomous non-audio completion delegation, 2026-10-01; D-080 / R-052. Delegated to AI recommendation.
