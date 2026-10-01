# StaxRip Mac Slice 036: Trimmed external captions
Version: 0.1. Date: 2026-10-01. Status: Approved for build under D-064 / R-045.

SLICE STATE
Milestone: Implemented at e2d1152; native/local gates passed, final-head hosted gate held after one existing publication observation timeout.
Blocked by: S36-005 investigation under D-065 / D-066 / R-046; no owner action required.
Evidence so far: SUBTITLE-TRIM-RESEARCH.md and SUBTITLE-TRIM-EVIDENCE.md; actual caption/video/audio/chapter timelines, native correction/export and local 247 tests.
Last audit: 2026-10-01.

## 1. What the slice proves

A selected video interval can retain the visible parts of an external plain caption track, with verified output timing instead of silently losing boundary cues.

## 2. The walkthrough

Choose a generated zero-start SDR source, external SRT, removed embedded subtitles and re-encoded or omitted audio. Enter millisecond-precision trim bounds. Check queue, inspect the clipped-cue summary, then encode to a new file. Verify actual decoded cues. Try an interval with no captions and correct the range without losing the reference.

## 3. In scope, with build order

M1: Pure bounded cue intersection and precision validation. M2: Plan-owned transformed snapshot, explicit filtered video/audio timing for this combination, and output-time custom chapter metadata. M3: Refusal and summary text, actual export/decoded timing tests, native walkthrough and regression.

## 4. Out of scope

Embedded subtitle retiming, styled or overlapping cues, multiple external tracks, nonzero/unknown source video timelines, HDR, copied-audio trimming, original mastering, listening, saved schema changes, dependencies, merge and release.

## 5. Stubs and debts

D-065 records boundary diagnostics; D-066 isolates one pure-storage stress fixture from the UI actor, retaining every workload bound and assertion. No new stub. Broad real-film, discontinuous audio, long-film sync and cross-player qualification remain open. A generated reference is narrower than arbitrary media support.

## 6. Modules touched

ExternalSubtitle, EncodePlan, BatchController snapshot selection, ChapterPlan metadata timing, SubtitleOptionsView and PictureOptionsView help and focused tests/evidence. Keep source capture/access and publication contracts unchanged.

## 7. Data subset

Existing configuration trim and external caption reference. Immutable in-memory clipped cue document and internal chapter metadata timeline selector; no persisted new fields.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S36-001 | Cue intersection preserves text, clips both boundaries, shifts once and refuses empty/invalid precision | Unit references, adjacent/outside/crossing/Unicode cases and existing bounds | caption-intersection |
| S36-002 | Actual MKV/MP4 captions and video frames match the selected interval; re-encoded audio keeps its intended alignment | Independent extraction, decoded frame timestamps and numerical generated audio timing; direct-seek counterexample | caption-timeline |
| S36-003 | Chapters, snapshot freshness, non-caption trim and untrimmed captions retain their contracts | Combined actual caption/chapter export and existing regressions | caption-coexistence |
| S36-004 | User can correct a refused range and export a verified generated result | Native preflight, correction and queue export; protected input/output hashes | caption-trim-native |
| S36-005 | Existing behavior remains qualified | Full local/hosted tests, optimized build and planning audit | caption-trim-regression |

## 9. Verification evidence required

Use generated fixtures only. Verify emitted cue text and millisecond ranges independently of process exit. Decode video timestamps instead of trusting nominal rate. Check audio timing numerically without listening or changing mastering. Include a delayed-track reference and combined custom chapters. Preserve originals and existing output collision behavior. Any changed timeline must invalidate the old expected snapshot.

## 10. Guardrails

No silent setting changes or dropped empty subtitle track. Keep refusal actionable. Never mutate the original caption file. Only the new external-caption-plus-trim path replaces global seek; other paths retain current behavior. Runtime caption verification remains before publication.

## 11. Definition of done

All five gates have final-head scoped evidence and retained coverage limits. No full-program or listening acceptance claim.

## 12. What this unlocks

Captioned clip exports inside the existing advanced queue, with one shared temporal contract.

Approved for build by: Owner autonomous program-completion delegation, 2026-10-01; D-064 / R-045.
