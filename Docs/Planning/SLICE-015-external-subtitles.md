# StaxRip Mac Slice 015: Verified external SRT subtitles
Version: 0.1. Date: 2026-09-30. Status: In progress.

SLICE STATE
Milestone: M1 through M4 local implementation, regression and native acceptance passed; hosted pending.
Blocked by: None external. Slice 014 accepted at f20998f, hosted run 36778465280.
Evidence so far: 17 new test functions, 142-test final regression, real native MKV/MP4 verified exports, unchanged input hashes, session round-trip and attached dialog cancellation. See EXTERNAL-SUBTITLE-EVIDENCE.md.
Last audit: 2026-09-30.

## 1. What the slice proves

A user can add one external plain-text SRT to a supported SDR job, choose its language/title, and receive an MKV or MP4 whose added subtitle cue text and millisecond intervals have been independently checked before publication. Source subtitle handling remains separately visible. No source or caption file is overwritten.

## 2. The walkthrough

Open generated zero-start SDR video. In Subtitles, select a generated UTF-8 SRT through an attached native picker, review the additional file, language and title, and set embedded-track handling independently. Check queue reports unsupported or malformed captions before encoding. Save/reopen the session and edit one queued job without affecting others. Encode MKV and MP4, inspect the subtitle stream and verified cue result. Remove the external reference explicitly to omit it. A deliberately altered staged subtitle fails verification and publishes nothing.

## 3. In scope, with build order

M1: Bounded plain SubRip parser, off-main regular-file snapshot and pure cue/timing refusal rules. M2: Optional source-specific external subtitle configuration, sessions v6/journals v5 migration, preset/source-change isolation, shared workspace/queue controls and balanced current-run file access. M3: Explicit input/map/codec planning, fresh preflight, owned snapshot staging, independently extracted cue/metadata verification before publication. M4: Parser, migration, real mux, altered-result, ownership/cancellation and native walkthrough evidence plus regression and hosted check.

## 4. Out of scope

ASS/SSA styling, bitmap/OCR subtitles, multiple external tracks, burn-in, translation, offset/retiming controls, trim or HDR with external captions, playback-default/forced disposition guarantees, audio/DSP, new video codecs, signing, merge and release. Existing embedded tracks keep their current contract, not a new all-track text guarantee.

## 5. Stubs and debts

The first supported external file is UTF-8 plain SRT with nonoverlapping cues and known zero-start timing. Refuse unsupported content explicitly rather than silently flattening it, including surrounding line whitespace that the tested mux/extraction path removes. Subtitle extraction has bounded output and an explicit operation deadline; very large or slow media may need later qualification. No promise of identical typography/player rendering or durable access across launches.

## 6. Modules touched

ExternalSubtitle/SubRip contract, EncodeConfiguration, SessionDocument/BatchJournal, CustomPresets source isolation, WorkspaceModel/WorkspaceView/QueueEditor, QueuePreflight, EncodePlan/BatchController, focused tests and evidence.

## 7. Data subset

One optional absolute local SRT path (bounded and without controls), a supported three-letter language code and bounded plain title. At most 1 MiB input, 10000 sequential cues, 4096 UTF-8 text bytes per cue, finite integer-millisecond intervals bounded by source duration and 48 hours. Text verification compares UTF-8 bytes after explicitly accepted line-ending normalization. Regular non-symlink input only; no special files or protocols. Capture canonical SRT bytes for the current operation, store them only inside its owned staging, and verify against that immutable cue list. Sessions/journals store the path and intent, not subtitle contents or permission handles. A transient shared access holder retains the selected URL for the lifetime of current workspace/queue references and balances security-scoped access; it is excluded from Codable and intent equality. Restored references may require selecting the file again in the editor. Presets cannot store external source references.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S15-001 | Plain multilingual cue content and times survive actual MKV/MP4 exports | Independent extraction and parsed exact comparison | external-srt-roundtrip |
| S15-002 | Unsupported, malformed, oversized, overlapping or mismatched captions cannot publish | Pure boundaries and altered staged-result fixtures | external-srt-refusal |
| S15-003 | Snapshots, cancellation and collisions protect source/caption/prior outputs and cleanup ownership | Real batch fixtures and preserved-byte checks | external-srt-ownership |
| S15-004 | Sessions/recovery preserve intent while presets and source changes do not leak file references | Migration, validation and isolation tests | external-srt-persistence |
| S15-005 | Native add/remove/edit/check/encode flow distinguishes embedded and external tracks | Generated native walkthrough and output inspector | external-srt-ui |

## 9. Verification evidence required

Parser boundaries; regular-file and bounded-read refusal; current/legacy/future saved data; preset isolation; real MKV/MP4 multilingual fixtures including no embedded tracks and selected embedded tracks; fresh snapshot behavior; deliberately altered cue text/times; source/caption/prior output bytes and staging ownership; ordinary regression, optimized build, native flow and hosted result. No new audio listening acceptance.

## 10. Guardrails

No silent setting changes, source rewriting or inherited external file in a reusable preset. Explicitly add input before output options and map the added subtitle stream explicitly; no shell command construction. A successful encoder exit does not bypass cue verification. Existing original media/geometry/container checks remain. A restored session never starts work automatically.

## 11. Definition of done

S15-001 through S15-005 have scoped local/native/hosted evidence and known timing/format/platform limitations are recorded. No whole-program completion or subtitle styling claim.

## 12. What this unlocks

Later subtitle offset/trim, multiple external tracks and styled formats can extend a verified contract under separate briefs rather than relying only on mux success.

Approved for build by: Owner autonomous non-audio delegation, activated under D-028 after Slice 014 closure.

### Native acceptance adjustment, 2026-09-30

The final-build session reopen walkthrough entered a modal state with no visible chooser (File menu commands disabled; main window remained visible). Saving succeeded, and both caption exports completed. To complete the planned save/reopen acceptance, replace only the session open/save standalone modal panels and replacement confirmation with sheets attached to the main workspace. Preserve replacement confirmation and cancel behavior. This is a bounded prerequisite under the existing autonomous authorization, not activation of the deferred general workspace-panel slice. Verify native save/open/cancel and restore without automatic execution; other source/destination/preset panels remain outside this change.
