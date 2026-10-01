# StaxRip Mac Slice 028: Correct native output name collisions
Version: 0.1. Date: 2026-10-01. Status: Approved for build under D-042 / R-032.

SLICE STATE
Milestone: Planning complete; implementation next.
Blocked by: None.
Evidence so far: Native Slice 027 discovery showed a system Replace prompt for an existing generated output, then safely cancelled it with unchanged hashes.
Last audit: 2026-10-01.

## 1. What the slice proves

Quick Export refuses a known existing output name in its save sheet before the system offers replacement. The user receives a correction message and can choose a new name. Final service protection still handles races after selection.

## 2. The walkthrough

Open Export MP4, enter an existing generated filename and press Export. Stay in the sheet with a clear name-collision message and no Replace confirmation. Try the same name without the extension; the intended MP4 path is still protected. Enter a fresh name and complete the existing native export. Cancel remains available throughout. Previous media stays unchanged.

## 3. In scope, with build order

M1: A small MP4 candidate/name check and retained native save-panel delegate at the documented pre-replacement callback. M2: Correct local URL/extension handling, existing file/directory/symlink refusal, meaningful message and accessibility announcement; no automatic renaming. M3: generated validation counterexamples, native explicit/extensionless collision and corrected-name export, existing service race regression, full local/build/hosted gate.

## 4. Out of scope

Other file panels, automatic numbered filenames, source relocation, a new destination layout, queue access policy, persistent permissions, asynchronous filesystem admission, audio, stored schemas, merge and distribution. This callback does not guarantee arbitrary filesystem latency.

## 5. Stubs and debts

No stub inside this name-correction path. A pre-selection name check is not permission, capacity or future availability proof. NativeExportService must independently retain exclusive publication. The known native destination filesystem wait remains unresolved.

## 6. Modules touched

WorkspaceFilePanels, a focused native MP4 name validator/delegate and tests. NativeExportService behavior remains unchanged and is exercised by existing protection tests and native output.

## 7. Data subset

Process-local proposed local URL, optional default MP4 extension, filesystem directory-entry existence and panel message. No source bytes, stored state or filename mutation. The delegate remains strongly owned until sheet completion because AppKit's delegate reference is weak.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S28-001 | Local MP4 names, including extensionless and mixed-case suffixes, are checked at the intended path; existing entries and invalid inputs refuse | Generated name-check tests | native-name-validation |
| S28-002 | Existing explicit/extensionless names stay in the sheet without Replace; correction and cancellation work | Native generated walkthrough and accessibility state | native-name-ui |
| S28-003 | A new name exports and source/prior outputs remain unchanged; race protection remains independent | Native output hashes and existing publication regression | native-name-protection |
| S28-004 | Other panels, native exports and queue remain intact | Full local/hosted suite, build and audit | native-name-regression |

## 9. Verification evidence required

Generated local files only, including an existing MP4 directory entry and dangling symlink. Do not claim validation ordering from a unit test alone: native UI must demonstrate no Replace confirmation. Keep the final no-overwrite race check even after a name passes validation. No timeout relaxation or broad filesystem harness.

## 10. Guardrails

The documented userEnteredFilename callback runs before extension append and replacement confirmation. Never change its returned filename to silently select another output. Return nil on refusal, retain the sheet and announce a correction. Only inspect on confirmed Export, not every typed character. Refuse indeterminate filesystem failures; absence is not a broad access guarantee.

## 11. Definition of done

All four criteria have scoped evidence at the final hosted product/test head. Audio listening remains parked.

## 12. What this unlocks

A consistent native promise: choose a new file, with a correction path when the requested name is taken.

Approved for build by: Owner overnight autonomous non-audio delegation, 2026-10-01; D-042 / R-032.
