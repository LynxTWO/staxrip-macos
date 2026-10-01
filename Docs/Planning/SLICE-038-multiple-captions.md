# StaxRip Mac Slice 038: Ordered external caption tracks
Version: 0.1. Date: 2026-10-01. Status: Approved for build under D-068 / D-069 / D-070 / D-071 / D-072 / D-073 / R-048.

SLICE STATE
Milestone: Ordered capture, mapping, verification and native editor implemented; focused/native checks passed; final regression pending.
Blocked by: Hosted verifier-entry failure remains after snapshot repair; D-073 diagnosis, no acceptance yet.
Evidence so far: MULTIPLE-CAPTIONS-EVIDENCE.md; generated independent decoding, later-track refusal and native save/reopen/export.
Last audit: 2026-10-01.

## 1. What the slice proves

A user can add up to eight external plain SRT tracks, order and label them, and receive an output whose added track count/order/language/title/text/timing were checked before publication.

## 2. The walkthrough

Add two generated SRT files, assign different languages and titles, reorder them, replace/remove one reference, save/reopen the session and export. Review the independently verified tracks. A broken second file identifies which reference needs correction and does not silently disappear.

## 3. In scope, with build order

M1: Bounded canonical reference list with backward-readable single-track sessions and explicit new session/recovery versions. M2: Immutable per-track capture, explicit input/output ordinals and complete verification. M3: Native ordered list, per-reference access review, recipe summaries and generated actual/adversarial/native/regression checks. Eight plain UTF-8 files maximum; existing one-MiB per-file and cue limits remain unchanged. Existing SDR transcode, verified video-copy and trimmed-caption workflows retain their guards.

## 4. Out of scope

ASS styling, burn-in, arbitrary subtitle formats, default/forced dispositions, broader HDR or timelines, embedded-caption retiming/payload certification, audio processing/listening, persistent security bookmarks, merge and distribution.

## 5. Stubs and debts

No new stub. Every added file adds a bounded capture and a separate output verification pass. Arbitrary filesystem cancellation latency, permission persistence, broad player/font behavior and owner listening remain open.

## 6. Modules touched

EncodeConfiguration, SessionDocument, BatchJournal, CustomPreset, source replacement/undo, SubtitleOptionsView, WorkspaceRecipe, QueueView access review, EncodePlan, QueuePreflight, BatchController and external-caption helpers. Retain ToolRunner, source fingerprint, staging and publication owners.

## 7. Data subset

Existing externalSubtitle retains the first reference; an optional bounded additionalExternalSubtitles holds the rest. A canonical list accessor/setter centralizes ordering. Session version 8 and recovery version 7 make old readers reject new multi-track intent. Existing valid versions remain readable. Added data in an old version, an additional list without a first item, excessive/duplicate standardized paths and invalid metadata refuse. Presets remain source-independent and never store references; applying them preserves the current entire list.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S38-001 | Bounded ordered intent round-trips without silently losing tracks | Legacy/new session/journal, schema/version/path/metadata negatives, preset/undo/source-change checks | caption-list-intent |
| S38-002 | Plans capture and map every reference exactly once | Count/order mismatch refusal, input/subtitle/chapter ordinal checks and independent snapshots | caption-list-plan |
| S38-003 | Actual added tracks preserve labels, text and timing in MKV/MP4 | Generated multilingual embedded/custom-chapter, trim and video-copy exports with independent decoding | caption-list-export |
| S38-004 | A bad later track cannot publish or advance the queue | Altered/missing second-track candidate, snapshot freshness, cancellation settlement, protected originals and staging | caption-list-refusal |
| S38-005 | Native users can manage and restore the ordered list | Add/reorder/replace/remove, language/title, save/reopen, correction/access review, actual export and accessibility semantics | caption-list-native |
| S38-006 | Existing behavior remains qualified | Optimized build, ordinary full local/hosted tests and planning audit | caption-list-regression |

## 9. Verification evidence required

Validate list identity/count/order before pairing immutable snapshots with references; never silently zip away unmatched elements. Bound total capture to eight existing one-MiB inputs. First owned snapshot retains external.srt, later names are operation-owned and index-derived. D-069/D-070 carry each title in an owned literal UTF-8 option-argument file, at most eight files of 1030 bytes. This avoids demonstrated process-argument Unicode decomposition and FFmetadata delimiter continuation; retain byte-exact title checks and automatic retained-stream metadata copying. Each added stream must appear at its planned subtitle ordinal with expected codec, language and title; decode that stream and compare exact cue UTF-8 text and millisecond intervals to its own captured/transformed document. Retain all original one-track tests. Assert actual output absence and next Pending on later-track failure, joined tool/file lifetimes on cancel, and exclusive publication. Track labels in UI errors must identify the failing filename/position without fabricating successful checks. Native tests preserve and restore the prior recovery journal after checking their own completed job.

## 10. Guardrails

No silent dropping, automatic incompatible codec conversion or reset, weakened parser/verification limits, default scheduling changes, user-file mutation or publishing before every verification completes. Added file selection must not target a different row after list changes. New schema versions are compatibility boundaries, not automatic migration of owner files.

## 11. Definition of done

All six gates have scoped final-head evidence. Record failed experiments and remaining limitations. No full-program, spoken VoiceOver or release acceptance claim.

## 12. What this unlocks

A single verified export can carry several language/accessibility caption tracks without repeated video generations or manual command-line remuxing.

Approved for build by: Owner autonomous non-audio completion delegation, 2026-10-01; D-068 / D-069 / D-070 / D-071 / D-072 / D-073 / R-048.
