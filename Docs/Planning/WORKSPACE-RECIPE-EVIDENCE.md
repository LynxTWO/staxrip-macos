# Workspace recipe evidence

Date: 2026-09-30. Accepted Slice 024 under D-038 / R-028. Product head daf27e6 has local regression and native evidence. Hosted gate 36811284038 passed at the final product/test head.

## Scope and authority

Owner renewed autonomous non-audio work and invited creative design. This slice changes presentation and navigation only. WorkspaceModel.config remains authoritative, PicturePlan supplies filter wording, existing editors own mutations and undo, and queue snapshots remain independent. The recipe is explicitly settings-only; source compatibility remains in Check queue. No output-size, measured geometry or readiness prediction was added.

## S24-001: configuration intent

Three focused tests passed in 0.002 seconds. Cases distinguish nil/all tracks from empty selections and explicit omission, selected stream IDs, external captions despite embedded omission, filename-only caption labels, bounded resize wording, trim endpoint/chapter intent, hardware mode without software speed, and undo/redo versus independent queued configuration. They do not assert every UI string. The summary implementation was compared with EncodePlan stream selection and PicturePlan filter order.

## S24-002 and S24-003: native journey

On macOS 27.0.1, the app showed four live recipe cards. Activating Picture selected its editor and scrolled the main pane to the controls. Incrementing top crop from 0 to 2 updated the card; Undo restored both the control and recipe. Audio and Subtitles cards also selected their editors. The final build's Option Command 1, 3, 4 and 2 shortcuts each selected the matching tab and card. Shortcuts are visible and exported in accessibility hints. No system keyboard or VoiceOver setting changed.

The first native check exposed an accessibility regression: grouping the entire button with ignored children removed its button role and the separate help modifier displaced its explanatory hint. The final view retains the native button role, explicit selected trait, Editing value and full hint. H.264 uses the shared digit-by-digit pronunciation helper. These are accessibility-tree and input observations, not heard VoiceOver acceptance.

Visual inspection covered light and dark appearances at the larger window and at the minimum content size of 1120 by 750 points (native quarter tiling, 2240 by 1556 pixel window image including title area). The recipe and destination scroll independently of the main editor; the output-name link and queue action stay visible. The name link scrolls to filename, container and folder controls. A long generated caption filename wraps without truncation. Owner aesthetic feedback and other display/platform coverage remain open.

A generated 60-second source was explicitly selected through the native picker. H.264 Quality updated the recipe and MP4 suffix. A long-named generated SRT appeared in the recipe. Keyboard filename editing updated the persistent destination link. Command J added one configuration without encoding; the duplicate name disabled Add to queue with a correction message. Queue showed H.264, CRF 18, MP4, SDR, AAC and the same added SRT. Check queue reported one preliminary pass, with zero audio tracks in this video-only source and one captured caption cue. This illustrates the distinction between requested settings and source inspection. The temporary queue entry was removed; source SHA-256 stayed unchanged and the proposed output remained absent. No earlier recovery record was replaced.

## S24-004: regression receipts

| Head/scope | Result |
| --- | --- |
| Initial implementation 7b23ec8 release | 195 tests / 39 suites passed in 37.752 seconds |
| Native semantics/destination correction 0a874a8 release | 195 tests / 39 suites passed in 38.327 seconds |
| Final keyboard implementation daf27e6 release | 195 tests / 39 suites passed in 38.379 seconds |
| Final ad-hoc app build | Passed in 16.06 seconds; launch and all four keyboard shortcuts verified |
| Hosted 36810704264 / 7b23ec8 | Passed: 195 tests in 423.868 seconds; superseded product head |
| Hosted 36811006329 / 0a874a8 | Passed: 195 tests in 470.990 seconds; superseded product head |
| Hosted 36811284038 / daf27e6 | Passed: Swift 6.1.2, 195 tests in 469.903 seconds |

Full local regression retained 16 existing opt-in skipped entries. No deadlines, media assertions or test scheduling changed. Existing audio regressions ran, but new audio work and owner listening remain parked. Ignored receipts are the workspace-recipe logs and workspace-recipe-native fixture/check records in the work directory. No generated media, local paths or binaries are committed. Draft PR 41 is unmerged.

S24-001 through S24-004 are accepted within the recorded scope. Hosted macOS 15 and local macOS 27 are distinct evidence; other platforms, spoken review and owner aesthetic feedback remain open.
