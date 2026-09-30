# Reusable presets and settings history evidence
Date: 2026-09-30. Scope: Slice 006, D-019. Status: Implemented; local native walkthrough and hosted follow-up passed.

## Implementation

My presets provides named source-independent recipes with save, apply, rename, remove, library undo and explicit single-recipe import/export. Recipes retain video codec/rate/color/size/speed, deinterlace and existing audio/subtitle encoding defaults. They omit source/destination paths, queue data, crop/trim and selected stream indices. Applying a recipe retains those source-specific values from the current workspace and never starts processing. HDR source eligibility remains a separate check.

The local version 1 library is limited to 100 recipes and 1 MiB. Names are 1 to 64 characters, at most 1024 UTF-8 bytes, with no control characters or surrounding spaces; folded names and UUIDs must be unique. Preset/session configuration validation rejects unknown enums, invalid bounds and source-bound recipe data. Imports are one recipe at a time, assign a new local UUID and reject duplicate names. Export stages a completed recipe then uses exclusive publication, so existing files are never replaced. Owned staging is removed on success and failure; cleanup failure is reported.

Writes to the library use an atomic replacement under a nonblocking sibling-file lock. A byte comparison with the last loaded snapshot prevents a second instance from overwriting newer settings. Validation, locking, conflict and write failures leave in-memory state unchanged. A malformed library stays on disk; writing is blocked until Reload can read a valid file. Library undo retains up to ten prior snapshots during the app run; Reload clears that history.

Workspace Undo settings and Redo retain at most 100 valid configuration snapshots. Coupled controls can briefly pass through invalid codec/encoder combinations; those intermediate states are excluded. Built-in and saved presets apply as one configuration assignment. Source load/replacement, demo reset and session restore clear settings history. Undo never edits a queued snapshot. Native text-editing undo is not replaced.

## Automated evidence

Six focused CustomPresetTests passed in debug. Cases cover source exclusion and current-source preservation; round trips and persistence across store instances; rename/remove/undo/import/export; refusal to overwrite; duplicate names/IDs and invalid versions/bounds; malformed-file preservation; stale-library conflicts; actual file-lock refusal; failed-write state; bounded configuration undo/redo; atomic preset application; unchanged queued snapshots; and rejection of invalid intermediate history.

The release regression reported 99 tests in 17 suites passed in 9.702 seconds, with 14 opt-in skips. The final export-staging and UTF-8 name bound changes are verified by a subsequent focused run recorded below. No new audio listening or algorithm acceptance is claimed.

## Native validation

After the owner unlocked the Mac, the optimized preview was restarted. The initially empty library was used for two disposable recipes. Save, rename, remove, library undo, export, import under a distinct local name and duplicate-name refusal displayed the expected statuses. Both recipes survived an app restart. Arrow-key list navigation and Escape dismissal worked. The sheet's controls and descriptions were visible without clipping; accessibility exposed named controls, selected rows and status. Owner spoken VoiceOver and other OS/appearance coverage remain separate.

The native run exposed an extra history entry after applying an AV1 recipe: a codec observer materialized default rate settings in a second update, so the first Undo appeared unchanged. Codec and engine controls now perform their related changes in one explicit assignment, with no observers rewriting restored/preset configurations. Both workspace and queue controls use this path. A regression covers codec/encoder/backend/mode transitions and restoration of hardware settings. The corrected native run changed H.264 CRF 18 / MP4 to saved AV1 CRF 28 / MKV; one Undo returned all three fields and one Redo restored them.

Using a generated interlaced source, applying the saved recipe retained four 2-pixel crop edges and a 0.2–1.5-second trim while changing deinterlacing from All frames to Off. The queue editor still showed the earlier All frames snapshot, crop and trim. Source-track preservation is covered by the automated recipe test; this silent fixture did not exercise real track selection. Session restore cleared history. The two test recipes were removed through the library UI, returning the initially empty library to empty. The exported synthetic recipe remains in local scratch only.

The final queue-control build was relaunched and exercised through AV1 → HEVC → Apple hardware → AV1. Hardware selected Target bitrate; returning to AV1 selected Software and retained bitrate intent. The edit was cancelled without changing the queued configuration.

## Hosted validation and remaining scope

The implementation at 1d17698 passed hosted validation in 8m25s: [run 36661841249](https://github.com/LynxTWO/staxrip-macos/actions/runs/36661841249). The native-discovered control fix is a subsequent change; its hosted result is recorded separately when available. Audio Lab presets, source-aware track mapping, document-wide undo, cloud sync and release remain outside this slice.

## Final local receipt

After adding staged exclusive recipe export and the UTF-8 name bound, all six focused release tests passed in 0.013 seconds. Successful and refused export left no owned staging directory. The final optimized ad-hoc app built successfully in 12.27 seconds. It has not been restarted or visually inspected because the Mac is locked. Planning audit reports zero findings across nine recognized documents.

A final file-identity review found that a dangling symbolic link could be mistaken for an absent library. Storage inspection now uses lstat and refuses nonregular files without replacement. The added dangling-link preservation regression passed; all seven focused release tests passed in 0.011 seconds. This is a follow-up to the 99-test full regression, not a claim that the new test ran in that earlier result.

## Native-discovered fix receipt

Eight focused release tests passed in 0.016 seconds. The release regression reported 101 tests in 17 suites passed in 9.656 seconds, with 14 opt-in skips. A final queue binding update reused the tested codec transition helper; the optimized app rebuilt successfully in 11.88 seconds and its native transition check passed as described above. No audio listening or new DSP acceptance is claimed.

Hosted follow-up at 0b4f96a passed in 8m53s: [run 36703925176](https://github.com/LynxTWO/staxrip-macos/actions/runs/36703925176). This includes the native-discovered atomic-control repair. Slice 006 local acceptance is complete within the stated platform and owner-review limits.
