# StaxRip Mac Slice 044: Verify Quick Export duration
Version: 0.1. Date: 2026-10-01. Status: Accepted under D-082 / R-054.

SLICE STATE
Milestone: All four scoped gates passed at f385cec; hosted run 36916404356 accepted.
Blocked by: None within scope.
Evidence: NATIVE-DURATION-EVIDENCE.md records the negative control, focused/native verification and ordinary local/hosted acceptance.
Last audit: 2026-10-01.

## 1. What the slice proves

Quick Export refuses to save a result whose reported total duration differs from the source by 250 milliseconds or more. This extends Architecture section 10's native export boundary using the existing output-duration rule, without adding a second encoding engine. It closes a concrete runtime verification gap; no current AVFoundation truncation defect is claimed.

## 2. The walkthrough

Open a generated local video, choose an Apple preset in Quick Export and choose a new MP4 destination. The app explains its total-duration check before export. It records valid source duration before creating staging, waits for Apple's export completion, reads staged video and duration, then saves only after verification. Existing cancellation, duplicate-name correction and safe retry remain. An invalid or materially shortened/extended result produces an error and leaves the destination absent; the user may explicitly retry. This does not certify frame completeness, individual-track timing, A/V sync or color.

## 3. In scope, with build order

M1: Add a bounded DEBUG-only test boundary after completed writing and before result inspection, then demonstrate that the existing readable-video check accepts generated shorter/longer replacements. Preserve those failing negative-control results. The callback cannot bypass the real verifier and is excluded from optimized builds.

M2: Capture a finite, positive source duration through AVFoundation asynchronous loading. Represent that immutable value in a small native duration contract, reusing OutputDurationCheck's unchanged strict 0.250-second allowance for the staged result. Keep the actual export callback, cancellation checks, process-local activity lifetime, finishing notification, publication and cleanup ownership intact. Explain total-duration verification and its limits in Quick Export.

M3: Pure invalid-source duration and strict-bound checks, generated real service/controller shorter/longer refusal and explicit retry, existing native preset/cancellation/publication tests, native walkthrough, ordinary local/hosted regression, optimized build and planning audit. The fault fixture owns only its temporary files; no media or paths are committed.

## 4. Out of scope

Full decoded completeness, source fingerprinting, per-track/A/V timing, native HDR/color/codec preservation, new export APIs or presets, audio DSP/listening, session/journal schemas, scheduling/deadline changes, dependencies, merge and release.

## 5. Stubs and debts

No stub. Declared aggregate asset duration is narrower than the duration of every decoded track. It does not resolve all AVFoundation preset behavior or source mutation. Broader native preservation requires its own decision.

## 6. Modules touched

NativeExportService and adjacent native duration contract; QuickExportView explanatory text; focused native-export tests through AVFoundation and existing generated fixtures. Existing OutputDurationCheck policy remains unchanged. ExportController and publication contracts retain current ownership.

## 7. Data subset

One finite, positive Double value captured from source asset duration, held only for the current export. No stored fields or retained source copies. Staged result duration is read after the writer's completion and before publication. Test-only substitution uses generated disposable media at the existing lifecycle boundary.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S44-001 | Invalid source timing is refused and known duration uses the fixed strict allowance | Finite/positive source admission, boundary/long-duration comparisons, existing duration-policy checks | native-duration-policy |
| S44-002 | Actual shorter/longer staged video cannot be published, but a normal explicit retry succeeds | Old-policy negative control; actual generated replacements through service/controller; destination absent, source/prior output unchanged, owned cleanup and retry | native-duration-refusal |
| S44-003 | Native workflow and guidance accurately describe the limited check | Actual Quick Export success, visible/accessibility text, independently probed duration, preserved source and owner journal | native-duration-ui |
| S44-004 | Existing native lifetimes and other product behavior remain qualified | Existing three-preset exports, cancellation/cleanup/publication cases, full local/hosted suite, optimized build and selected audit | native-duration-regression |

## 9. Verification evidence required

R-054 authorizes a single DEBUG-only pre-verification substitution seam, finite generated media and existing test/controller ownership. Consequence class: user_data, because a newly saved result otherwise may be reported complete without a duration check. Preserve failing tests; do not relax deadlines, fixture scheduling or duration policy. No new observer service, media library, performance campaign or manual listening is needed. Record actual checks, skips, identity, negative control and native limits in NATIVE-DURATION-EVIDENCE.md.

## 10. Guardrails

No unknown source duration may silently become a successful verified export. No output is saved before timing verification. Report failed cleanup through existing outcome rules. Cancelled writers must settle before cleanup; dispatched publication keeps its actual result. Stop qualification if the historical hosted mastering cancellation failure recurs, without a blind retry or new diagnostic expansion.

## 11. Definition of done

All four scoped gates have recorded evidence. No full-decoding, A/V sync, playback, HDR or heard accessibility claim. Owner media and recovery state remain unchanged by the walkthrough.

## 12. What this unlocks

A consistent minimum duration check across queue and native exports. Broader native source stability and representative media validation remain later decisions.

Approved for build by: Owner standing autonomous non-audio completion delegation, 2026-10-01; D-082 / R-054. Delegated to AI recommendation.
