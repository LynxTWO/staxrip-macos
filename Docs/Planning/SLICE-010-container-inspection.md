# StaxRip Mac Slice 010: Chapters and attachments in the inspector
Version: 0.1. Date: 2026-09-30. Status: Complete within recorded limits.

SLICE STATE
Milestone: M1 through M3 complete; focused, regression, native and hosted product checks passed at 087adcc.
Blocked by: None external.
Evidence so far: CONTAINER-INSPECTION-EVIDENCE.md records four focused tests and the existing four video-inspection checks.
Last audit: 2026-09-30.

## 1. What the slice proves

A user can inspect a movie's reported chapter titles/times and embedded attachment information in the native app before choosing an encoding workflow. Chapter absence, missing tags, malformed timing and cover art remain distinct; viewing metadata does not extract files or certify preservation.

## 2. The walkthrough

1. Open a generated movie and choose Inspect media tracks.
2. Switch between Tracks, Chapters and Attachments without losing the source context.
3. Read a chapter's title, start/end and reported identifier; inspect an attachment's filename and declared MIME type, or identify cover art.
4. Open a source with no chapters/attachments and see explicit empty states. Missing or invalid metadata is reported rather than invented.

## 3. In scope, with build order

M1: Add optional chapter metadata to the existing bounded probe response and request show_chapters. Add a small pure presentation model with safe bounded text and timing status. Protect inspection generations so a cancelled earlier source cannot overwrite a newer result.
M2: Native inspector sections for tracks, chapters and attachments, counts, empty states and accessibility. Do not render/extract attachments. Bound displayed rows with an explicit notice.
M3: Generated chapter/attachment fixture and missing/malformed metadata tests, unchanged source/directory evidence, regression, native section navigation and hosted validation.

## 4. Out of scope

Chapter editing/import/export, chapter playback seeking, retiming, attachment extraction or font loading, remux, output preservation verification, container mutation, new saved-session fields, audio tests/listening, release and merge.

## 5. Stubs and debts

No metadata label is treated as payload validation or output preservation. Existing chapter/attachment routing is unchanged. The first 200 entries per section are shown with a count/limit notice; full editing and searchable navigation remain separate work. Probe stdout remains capped at 4 MiB and truncation fails rather than presenting a partial probe as complete.

## 6. Modules touched

MediaProbe in ToolRunner.swift, BatchController inspection generation, a pure ContainerInspection presenter, MediaInspectorView, the Workspace inspector button label, focused tests and documentation. No encoding plan or output publication change.

## 7. Data subset

Process-local optional chapters with identifier, reported start/end strings, tick values/time base and tags; existing attachment stream tags and attached-picture disposition. Rendered text replaces control characters and limits length, with a clear notice. Do not treat a filename tag as a local file path. Use stable presentation indices so duplicate reported identifiers cannot collapse rows.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S10-001 | Generated chapter titles/times and attachment names/types appear without source or directory mutation | Real ffprobe fixture plus before/after bytes/listing | container-inspection-data |
| S10-002 | Missing/invalid/duplicate metadata, empty lists and excessive text/counts have truthful bounded presentation | Pure fixtures covering unavailable timing, end before start, control characters, duplicate IDs and row cap | container-inspection-bounds |
| S10-004 | A superseded or cancelled inspection cannot publish metadata under a newer source | Overlapping controlled probes and cancellation test | container-inspection-identity |
| S10-003 | Native section navigation, counts and readable accessible rows work for populated and empty sources | Native generated-media walkthrough and AX inspection | container-inspection-ui |

## 9. Verification evidence required

Focused generated data and malformed metadata tests, shared regression to confirm probe callers still work, native populated and empty inspection, optimized build and hosted result. This is metadata inspection evidence only; no output-preservation or attachment-content claim.

## 10. Guardrails

No extraction, execution, font registration, path navigation or network fetch from metadata. Chapter times are reported values, not verified frame positions. Unknown timing is never displayed as zero. Keep first non-cover-video routing unchanged. Preserve audio pause and no-release boundary.

## 11. Definition of done

S10-001 through S10-004 have local and hosted evidence and remaining limits are documented. Owner spoken VoiceOver and other platforms remain separate qualification.

## 12. What this unlocks

A later chapter editor and preservation verifier can use observed source metadata with explicit transformation rules. Attachment preservation and safe extraction need their own ownership policy.

Approved for build by: Owner autonomous non-audio delegation on 2026-09-29, reaffirmed 2026-09-30; activated under D-023 after Slice 009 closure.
