# StaxRip Mac Slice 006: Reusable presets and settings undo
Version: 0.1. Date: 2026-09-29. Status: Implemented; local native verification passed; follow-up hosted check pending.

SLICE STATE
Milestone: M1-M2 implemented; M3 automated checks and native walkthrough pass; hosted follow-up pending.
Blocked by: None locally. Hosted validation of the native-discovered fix is pending.
Evidence so far: CUSTOM-PRESET-EVIDENCE.md.
Last audit: 2026-09-30.

## 1. What the slice proves

A user saves a named encoding recipe, reuses it on another source without copying source-specific crop/trim/track indices, and can undo an accidental settings change. This extends the existing configuration/session boundary. Owner requested autonomous reasonable non-audio decisions after approving Slice 005; D-019 records this delegated choice.

## 2. The walkthrough

1. Adjust encoding settings and open My presets.
2. Save a named recipe. The sheet explains that source paths, destinations, crop/trim and stream selections are excluded. Video codec/rate/color/size/speed, deinterlace and existing audio/subtitle encoding defaults are included.
3. Relaunch, select the saved recipe, review its summary and apply. Current source-specific fields and queued snapshots remain unchanged.
4. Use Undo settings or Redo settings to reverse workspace configuration changes. Applying a built-in or saved preset is one change. No claim of document-wide or text-editing undo.
5. Rename or remove a saved recipe. Undo the last library change while the app remains open. Duplicate names and invalid imports give a repairable error.

## 3. In scope, with build order

| Milestone | Scope |
| --- | --- |
| M1 | Version 1 validated recipe/library format, at most 100 entries and 1 MiB; local atomic persistence with cross-process conflict detection and locking; bounded settings history |
| M2 | Native library sheet, save/apply/rename/remove/library undo, explicit single-recipe import/export; readable and accessible summaries |
| M3 | Malformed-file, write-failure, duplicate/conflict, privacy and history tests; native save/restart/apply/undo walkthrough; regression and hosted check |

## 4. Out of scope

Audio Lab/DSP presets, paths/media, queue/job history undo, text-field undo replacement, automatic execution, cloud sync, arbitrary FFmpeg options, tool installation, merge and release. Existing source-specific picture values stay attached to the current source. HDR settings are still subject to the explicit export validator; applying a preset never certifies a source.

## 5. Stubs and debts

No fake preset list. If the local library is malformed, preserve it and block writing until it can be read; Reload provides a retry after external repair. No silent reset or overwriting another process's newer library. Imported recipe is an explicit user action, with no media processing.

## 6. Modules touched

New CustomPreset/CustomPresetStore and PresetLibraryView. WorkspaceModel configuration history and atomic built-in preset application; WorkspaceView buttons/sheet. SessionDocument.validate reused without a schema change. Existing app lifecycle wiring owns the library. Tests exercise generated data only.

## 7. Data subset

Recipe UUID, trimmed name of 1 to 64 characters without control characters, validated source-independent EncodeConfiguration. Canonical case-insensitive names must be unique. Reject source-specific fields in imported recipes rather than silently carrying them. No paths or job data in recipe/library files. Local library is stored in the app's Application Support directory, atomically updated after validation under a process lock. Compare with the loaded byte snapshot before each write; on a changed file require Reload. Failed write leaves in-memory state unchanged.

Settings history retains at most 100 distinct configuration snapshots; preset application is one snapshot. Undo/redo never execute media or mutate queued configurations. Source/session replacement clears history to avoid restoring another source's track/crop/trim intent. Library undo retains at most ten prior library snapshots during this app run. Import/export uses explicit file panels; export refuses existing files. Applying or saving a recipe shows a concise statement of its source-specific exclusions.

## 8. Acceptance criteria

| ID | Criterion | Verification | Gate |
| --- | --- | --- | --- |
| S6-001 | Reusable configuration excludes source paths, destinations, crop/trim and stream indices while preserving declared recipe settings | Round-trip and apply tests across different current configurations; encoded JSON inspection | preset-scope |
| S6-002 | Library survives restart; names/versions/bounds and configurations are validated | File round-trip; duplicates, future versions, oversized and malformed data refuse | preset-storage |
| S6-003 | Conflict or write failure preserves prior disk/in-memory state | Two store instances, stale baseline, lock failure and failed write cases | preset-conflict |
| S6-004 | Undo/redo and built-in/saved preset application behave as one change; source/session switches clear settings history | Model tests, independent queued snapshots, bounded history | preset-history |
| S6-005 | Native save/apply/rename/remove/undo and import/export have clear status and accessible labels | Native walkthrough and keyboard/accessibility inspection; owner spoken feedback separate | preset-ui |

## 9. Evidence required

Focused generated-data tests, appropriate regression, native app walkthrough, local file-format and privacy checks, hosted result. No benchmark or audio-listening work. Record skipped tests and remaining owner/platform coverage.

## 10. Guardrails

Do not silently reset a corrupted library, overwrite an existing export, persist media paths, alter queued jobs on preset application, or replace native text-editing undo. No schema changes to saved sessions. Source and prior output protection remains mandatory.

## 11. Definition of done

All local S6 gates have evidence, native core/error paths are exercised, hosted status is recorded and documentation states remaining owner/platform validation.

## 12. What this unlocks

Source-aware recipe mapping, per-track recipes and a later explicitly scoped Audio Lab preset format. Those remain separate decisions.

Approved for build by: Owner delegation on 2026-09-29, recorded in DECISION-LOG.md Autonomous continuation. Scope chosen by the agent under that delegation.
