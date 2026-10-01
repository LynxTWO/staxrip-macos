# StaxRip Mac Slice 030: Author and verify chapter lists
Version: 0.1. Date: 2026-10-01. Status: Accepted within recorded scope under D-044 / R-034.

SLICE STATE
Milestone: Local/native and final hosted acceptance complete at 0105d5c plus diagnostic-only ded74f6.
Blocked by: None within this slice.
Evidence so far: CHAPTER-EDITOR-EVIDENCE.md; hosted run 36824096245 passed 222 tests. Earlier destination-review timeout remains explicit reliability debt.
Last audit: 2026-10-01.

## 1. What the slice proves

Users can remove chapters or author a source-timeline chapter list, keep it in their session and queue, and export only after the resulting chapter titles and ranges pass independent output inspection. The native editor keeps uncommitted changes separate from the current recipe.

## 2. The walkthrough

Open generated chaptered media, visit Chapters, and edit a draft. Load source chapters, rename a title and change a range. Cancel once to retain the original recipe. Apply a valid custom list, add an independent queue copy and save/reopen the session. Export through destination review and inspect the resulting titles/ranges. An incompatible MP4 gap or invalid range explains the correction before encoding.

## 3. In scope, with build order

M1: Bounded typed chapter edits, millisecond authoring and source-timeline validation; pure generated metadata/expected-output planning; owned staging and independent chapter verification. M2: Session version 7 and recovery version 6 with legacy compatibility/refusal, source reset, preset exclusion/retention, independent queue edits and bounded saving. M3: Native Chapters settings and recipe shortcut, draft editor and owned/cancellable explicit source import. M4: Generated structural, persistence, lifecycle and actual MKV/MP4/trim/caption/HDR-path checks; native walkthrough, full local/build/hosted acceptance.

## 4. Out of scope

Nested chapters, Matroska editions, chapter artwork, arbitrary chapter tags, importing external chapter files, automatic scene recognition, chapter seek accuracy across players, general nonzero/unknown timeline origins, audio/DSP, new HDR transformations, remux, merge and public distribution.

## 5. Stubs and debts

No stub in authoring, cancellation, persistence or output verification. Existing source-preservation behavior remains the default: untrimmed source chapters retained, trimmed source chapters omitted. Custom lists explicitly clip to the trim interval and offset to output time. Source timestamps imported for editing are rounded to milliseconds with a visible notice. A metadata range is not a verified video frame position.

## 6. Modules touched

EncodeConfiguration, chapter options/planning/editor modules, EncodePlan, ContainerPreservation, BatchController, SessionDocument, BatchJournal, CustomPresets, WorkspaceModel/View/Recipe, QueueEditor and application operation ownership. QueuePreflight remains read-only through the same argument-only planner.

## 7. Data subset

Optional chapter edits distinguish legacy preservation from Remove or Custom. Custom entries have stable IDs, literal bounded titles and integer millisecond source ranges. Maximum 1000 entries per list, 10000 aggregate persisted entries, seven-day bounds and 4096 UTF-8 bytes per title. Reject control characters and duplicate IDs. Session and recovery writes remain within the existing 5 MB read boundary. Custom presets cannot carry source chapter edits; applying a preset retains current chapter intent.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S30-001 | Invalid bounds, titles, IDs, ordering and ambiguous textual times refuse; metadata punctuation remains literal | Structural/parser and actual title tests | chapter-validation |
| S30-002 | Authored/default/removed chapters and custom trims produce verified expected titles/ranges in MKV and MP4; incompatible MP4 gaps refuse | Generated actual exports and counterexamples | chapter-export |
| S30-003 | Exact trim boundaries omit nonintersecting entries; fractional offsets retain supported precision; altered output chapters refuse | Discovery regression and verification counterexamples | chapter-timing |
| S30-004 | Versioned documents retain edits, old mislabeled data refuses, presets/source changes cannot carry stale source intent | Persistence, undo/reset and queue-copy tests | chapter-persistence |
| S30-005 | Source import owns cancellation and stale results; Cancel/failure retains configuration/draft and Apply requires current intent | Controlled reader/editor lifecycle tests | chapter-editor-lifecycle |
| S30-006 | Native editor and fifth recipe section are readable, labelled and keyboard reachable; edit/cancel/apply/session/queue/export works | Generated native walkthrough | chapter-native |
| S30-007 | Additional captions keep their input mapping; current static HDR10 path retains its existing audit and chapter verification | Focused combined-input and HDR regression | chapter-coexistence |
| S30-008 | Prior behavior and protection remain intact | Full local/hosted suite, app build and audit | chapter-regression |

## 9. Verification evidence required

Generated media only. Use escaped Unicode/punctuation titles and independent output chapter reads, including deliberately wrong titles/times/counts. Cover full and fractional trims, exact boundary contacts, excluded lists and unsupported source origins. Keep source/prior outputs unchanged and clean only owned staging. Native batch testing preserves/restores the prior recovery journal after app exit. No lowered tolerances, deadline relaxation or new exclusions to force acceptance.

## 10. Guardrails

Only a successful Apply changes the current chapter recipe. Import is explicit and draft replacement is named. A cancelled/failed import retains prior draft; late callbacks cannot overwrite newer work. Closing the editor cancels its owned read, with application lifetime ownership until settlement. User text never becomes a command or raw metadata section. Custom entries with no positive trim intersection are excluded before FFmpeg can invent zero-length boundary entries; unrepresentable remaining ranges refuse. Generated metadata uses microsecond time base for trim offsets, while authored ranges remain millisecond integers. Preserve final exclusive publication and output audits.

## 11. Definition of done

All eight criteria have scoped evidence at the final tested product head. No claim of broad chapter/player, HDR or film compatibility beyond recorded fixtures. Audio listening remains parked.

## 12. What this unlocks

An editable, persistent navigation structure for exported films, with explicit trim behavior and verified delivery.

Approved for build by: Owner overnight autonomous non-audio delegation, 2026-10-01; D-044 / R-034.
