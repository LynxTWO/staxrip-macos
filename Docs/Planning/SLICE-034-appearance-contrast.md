# StaxRip Mac Slice 034: Readable semantic appearance
Version: 0.1. Date: 2026-10-01. Status: Approved for build under D-061 / R-043.

SLICE STATE
Milestone: Reference and call-site discovery complete; implementation not started.
Blocked by: None. Slice 033 accepted at 3d14456 with hosted run 36851151827.
Evidence so far: Fixed accent counterexample, native light-mode observation, AppKit dynamic-color documentation and actual tint call sites.
Last audit: 2026-10-01.

## 1. What the slice proves

Small accent and warning text remains readable in both appearances, while primary actions retain legible labels and the app's teal identity.

## 2. The walkthrough

Inspect workspace navigation, recipe and Add to queue in light and dark. Open Queue with a generated existing-output collision; read the attention count and badge. Review primary actions, edit a generated job with the keyboard, and dismiss without changing its recipe. Compare increased-contrast color resolution without changing the owner's system settings.

## 3. In scope, with build order

M1: Shared appearance-aware accent and warning colors, plus separate primary-action foreground/fill. M2: Replace relevant warning and prominent-action call sites, including the custom queue action as a complete pair. M3: Resolved-color reference checks, native appearance/action checks and full regression.

## 4. Out of scope

Encoding, audio processing/listening, file access, session schemas, layout redesign, chart-series semantics, system secondary/disabled colors, display calibration, full accessibility certification, merging and release.

## 5. Stubs and debts

No new stub. Translucent materials depend on composited backgrounds; opaque reference contrast does not establish every desktop or display condition. Existing filesystem-open/cancellation and durable-access limits remain in the release ledger.

## 6. Modules touched

Shared palette, app tint and native view color/action modifiers; focused color checks and evidence. Action closures, guards and keyboard shortcuts remain unchanged.

## 7. Data subset

Appearance identity and static sRGB palette values only. No media or user data collection.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S34-001 | Accent/warning reference contrast is at least 4.5:1 in light/dark and 7:1 in increased contrast; primary action labels remain legible | Actual dynamic NSColor resolution, old counterexample and alpha-composited used tint pairs | palette-reference |
| S34-002 | Native light/dark workspace and queue attention views remain readable and coherent | Native visual and accessibility inspection | palette-native |
| S34-003 | Native prominent behavior, existing actions, labels and keyboard shortcuts remain intact | Focused native edit/dismiss and queue action check | palette-actions |
| S34-004 | Prior behavior remains qualified | Full local/hosted tests, optimized ad-hoc build and planning audit | palette-regression |

## 9. Verification evidence required

Resolve colors under actual Aqua, Dark Aqua and increased-contrast appearances. Use sRGB relative luminance and documented opaque window/control/reference surfaces, with foreground tint through 12 percent for active accent/warning pairs. The recipe number chip uses system primary text at 24 percent, so it is not an accent-text pair. Check the custom queue keyboard hint separately. Native material rendering is visually inspected without claiming physical-display measurements. Use generated queue files and preserve outputs and the prior journal.

## 10. Guardrails

Text and icons continue to convey status independently of color. Never infer successful encoding from a color. Retain native focus and disabled behavior for existing prominent controls. Do not change owner system accessibility settings to manufacture evidence.

## 11. Definition of done

All four gates have scoped evidence at the product head, with limitations recorded. No completion claim for the entire application.

## 12. What this unlocks

A consistent readable visual foundation for later workspace layout work.

Approved for build by: Owner overnight autonomous non-audio and design delegation, 2026-10-01; D-061 / R-043.
