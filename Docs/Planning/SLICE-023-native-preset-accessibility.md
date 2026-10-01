# StaxRip Mac Slice 023: Spoken native preset choices
Version: 0.3. Date: 2026-09-30. Status: Approved for build under D-036 / R-026.

SLICE STATE
Milestone: Local/native verification passed; hosted regression investigation active.
Blocked by: Hosted regression has not passed; attempt 1 recorded clustered timeouts.
Evidence so far: NATIVE-PRESET-ACCESSIBILITY-EVIDENCE.md records local release/debug and native success plus the failed hosted attempt.
Last audit: 2026-09-30.

## 1. What the slice proves

Quick Export preset cards identify their native engine, codec and size choice with short accessible names, explicit selection and optional explanatory hints. Reuse the pronunciation the owner approved for workspace presets.

## 2. The walkthrough

Open Quick Export and inspect the three native preset choices. Select each and verify one selected value, a readable spoken codec label and an optional hint explaining Apple preset behavior and the separation from workspace settings. Visible names and the resulting encoder selection stay unchanged.

## 3. In scope, with build order

M1: Reuse AccessibilityLanguage.spokenCodecs for native preset labels and add native-only hints. M2: Explicit selected/not-selected accessibility value and visible-name input labels for voice control. M3: Build, existing regression suite, native accessibility-tree and visible selection inspection, and hosted acceptance.

## 4. Out of scope

Encoding changes, general accessibility audit, system VoiceOver preferences, automated speech/listening acceptance, audio mastering, other preset views, dialogs, persistence, merge or release.

## 5. Stubs and debts

Exported accessibility text can be inspected automatically; the owner's spoken VoiceOver review remains separate. Do not describe accessibility-tree evidence as a heard pronunciation test.

## 6. Modules touched

AccessibilityLanguage, QuickExportView and scoped evidence only.

## 7. Data subset

Derived accessible labels, selected-state value, input aliases and optional hints. No stored state or new schema. NativePreset remains the selection authority.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S23-001 | H.264 native choices export H two six four and distinct size labels | Native accessibility tree | native-preset-labels |
| S23-002 | Exactly one preset exposes Selected after each activation; hints distinguish native behavior | Native activation and accessibility inspection | native-preset-selection |
| S23-003 | Visible names and existing encode behavior remain intact | Visible layout, existing regression/build and hosted checks | native-preset-regression |

## 9. Verification evidence required

Inspect all three choices and selection transitions in the rebuilt app. Retain visible names and input aliases. Run the existing regression suite and build; no implementation-mirroring test is needed for this reversible text/semantics change. Spoken VoiceOver remains an owner check.

## 10. Guardrails

Keep short names separate from optional explanations. Do not use a label that promises every source exports at the preset's nominal raster. Do not change system accessibility settings or native encoder options.

## 11. Definition of done

S23-001 through S23-003 have scoped local/native/hosted evidence and the planning audit passes. Spoken qualification remains explicit.

## 12. What this unlocks

Consistent native/workspace codec pronunciation and clearer independent preset choices.

Approved for build by: Owner autonomous non-audio delegation under D-036 / R-026, 2026-09-30, after Slice 022 closure; reuses the previously owner-approved codec pronunciation.

## Verification amendment, 2026-09-30

R-026 permits one bounded, isolated diagnostic of the existing ToolRunner implementation after hosted attempt 1 recorded clustered worker timeouts. Compare 16 and 96 generated child processes with stdout/stderr payloads, exact byte/status outcomes and a 45-second external watchdog per case. Use only ignored scratch files, no private media or repository payloads. Record process state and clean up only the diagnostic's identified live children after a deadline. This tests a worker-contention hypothesis, not a general concurrency guarantee. No application or CI behavior change is authorized by this diagnostic amendment; a demonstrated repair needs a recorded scope decision before implementation. Existing regression assertions and limits stay intact.

Approved for build by: Owner autonomous non-audio delegation under D-036 / R-026, 2026-09-30; bounded hosted-gate diagnosis only.

## Dependency repair amendment under D-037 / R-027

The hosted gate failed twice and an isolated probe independently demonstrated shared-worker starvation in ToolRunner. Before accepting this slice, replace the blocking process/pipe ownership with readiness-driven draining and await exit plus both EOFs. Only ToolRunner and its focused tests join the product scope. Encode commands, output verification, persistence and audio algorithms stay unchanged. Add S23-004 (runner-fanout): 96 generated children return complete stdout/stderr and exit status without starving shared workers. Add S23-005 (runner-lifecycle): cancellation, launch refusal, truncation and final streamed bytes preserve settled-process semantics. Existing full regression, native advanced export/cancel and hosted checks are required after repair. Baseline 16 passed / 96 timed out after 45 seconds is the negative control; it was externally terminated with identified child cleanup.

Approved for build by: Owner autonomous non-audio delegation under D-037 / R-027, 2026-09-30. This extends the active slice for its demonstrated runtime dependency; no new slice is active.

R-027 diagnostic refinement: after the final-test-head hosted run timed out only in the existing 12-export anamorphic matrix, allow at most 96 phase-only progress records inside that existing test to identify its failure phase. Keep all media cases, assertions and the 120-second limit unchanged. This is test diagnosis within the active regression gate, not a performance policy change.
