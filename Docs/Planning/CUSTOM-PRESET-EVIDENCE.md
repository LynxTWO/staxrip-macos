# Reusable presets and settings history evidence
Date: 2026-09-29. Scope: Slice 006, D-019. Status: Implemented; native walkthrough blocked by locked Mac.

## Implementation

My presets provides named source-independent recipes with save, apply, rename, remove, library undo and explicit single-recipe import/export. Recipes retain video codec/rate/color/size/speed, deinterlace and existing audio/subtitle encoding defaults. They omit source/destination paths, queue data, crop/trim and selected stream indices. Applying a recipe retains those source-specific values from the current workspace and never starts processing. HDR source eligibility remains a separate check.

The local version 1 library is limited to 100 recipes and 1 MiB. Names are 1 to 64 characters, at most 1024 UTF-8 bytes, with no control characters or surrounding spaces; folded names and UUIDs must be unique. Preset/session configuration validation rejects unknown enums, invalid bounds and source-bound recipe data. Imports are one recipe at a time, assign a new local UUID and reject duplicate names. Export stages a completed recipe then uses exclusive publication, so existing files are never replaced. Owned staging is removed on success and failure; cleanup failure is reported.

Writes to the library use an atomic replacement under a nonblocking sibling-file lock. A byte comparison with the last loaded snapshot prevents a second instance from overwriting newer settings. Validation, locking, conflict and write failures leave in-memory state unchanged. A malformed library stays on disk; writing is blocked until Reload can read a valid file. Library undo retains up to ten prior snapshots during the app run; Reload clears that history.

Workspace Undo settings and Redo retain at most 100 valid configuration snapshots. Coupled controls can briefly pass through invalid codec/encoder combinations; those intermediate states are excluded. Built-in and saved presets apply as one configuration assignment. Source load/replacement, demo reset and session restore clear settings history. Undo never edits a queued snapshot. Native text-editing undo is not replaced.

## Automated evidence

Six focused CustomPresetTests passed in debug. Cases cover source exclusion and current-source preservation; round trips and persistence across store instances; rename/remove/undo/import/export; refusal to overwrite; duplicate names/IDs and invalid versions/bounds; malformed-file preservation; stale-library conflicts; actual file-lock refusal; failed-write state; bounded configuration undo/redo; atomic preset application; unchanged queued snapshots; and rejection of invalid intermediate history.

The release regression reported 99 tests in 17 suites passed in 9.702 seconds, with 14 opt-in skips. The final export-staging and UTF-8 name bound changes are verified by a subsequent focused run recorded below. No new audio listening or algorithm acceptance is claimed.

## Native validation blocker

The comparison feature's native walkthrough completed before the Mac locked. During the subsequent preset walkthrough, the native UI tool reported: “The Mac is locked and automatic unlock could not unlock it.” No native preset actions have been claimed verified. Do not change lock/security settings to bypass this boundary.

On unlock: restart the built preview; save a generated recipe, change workspace settings, apply and undo/redo; rename/remove and undo library change; export/import under distinct names; restart and verify persistence; inspect keyboard and accessibility labels and the sidebar layout. Use disposable generated settings, preserve any existing owner library, and check that crop/trim/track selections and queued snapshots stay unchanged.

## Remaining scope

S6-001 through S6-004 have local automated evidence. S6-005 native acceptance remains blocked. Hosted validation is recorded when available. Audio Lab presets, source-aware track mapping, document-wide undo, cloud sync and release are outside this slice.

## Final local receipt

After adding staged exclusive recipe export and the UTF-8 name bound, all six focused release tests passed in 0.013 seconds. Successful and refused export left no owned staging directory. The final optimized ad-hoc app built successfully in 12.27 seconds. It has not been restarted or visually inspected because the Mac is locked. Planning audit reports zero findings across nine recognized documents.
