# StaxRip Mac Slice 037: Verified original-video copy
Version: 0.1. Date: 2026-10-01. Status: Accepted within recorded evidence under D-067 / R-047.

SLICE STATE
Milestone: All six gates accepted at 22dc1ed; native and ordinary local/hosted checks passed.
Blocked by: None within scope.
Evidence so far: VIDEO-COPY-RESEARCH.md and VIDEO-COPY-EVIDENCE.md; packet, decoded-pixel and timing references plus shifted/missing-packet counterexamples.
Last audit: 2026-10-01.

## 1. What the slice proves

A user can change the container or track recipe without re-encoding the first video, and receive a result whose original encoded video and presentation timing were checked before publication.

## 2. The walkthrough

Choose Copy original in the advanced video controls. Review that video encoding controls are inactive and audio/subtitle choices still apply. Correct an incompatible picture setting explicitly. Check queue, choose a new MKV or MP4, and run. Inspect the verified result. Save/reopen the recipe and switch back to a video encoder without losing stored rate settings.

## 3. In scope, with build order

M1: Validated codec/encoder pair, explicit copy-settings/source contract and bounded streaming packet manifest. M2: Shared plan routing, source capture and pre-publication verification. M3: Native controls/recipe guidance, generated actual and adversarial outputs, ordinary local/hosted regression.

Initial sources: MP4/QuickTime or Matroska, first non-attached H.264/HEVC video, known zero-start finite duration up to 48 hours, positive even original dimensions, progressive 8-bit yuv420p SDR, known square pixels and identity orientation. Output MKV or MP4. No picture transformations. Existing audio, subtitle, external SRT and chapter choices retain their existing guards.

## 4. Out of scope

HDR, ten-bit, other codecs/source containers, rotated/interlaced/anamorphic sources, trim, arbitrary edit lists or unknown timelines, additional video streams, mastering/listening, new persisted fields, dependencies, merge and release. Container bytes, every metadata field and decoder timestamp representation are not promised identical.

## 5. Stubs and debts

No new stub. Copied video is narrower than whole-file losslessness: AAC/Opus still re-encode selected audio. Packet auditing adds complete source/output scans and up to 128 MiB of private temporary audit storage. Arbitrary filesystem cancellation latency and real-film/player qualification remain open.

## 6. Modules touched

EncodeConfiguration helpers, SessionDocument validation, shared video controls in WorkspaceView/QueueEditor/VideoRateOptionsView, WorkspaceRecipe, EncodePlan, QueuePreflight, BatchController and a process-local video-copy packet contract/manifest. Reuse source identity, ToolRunner, caption/chapter/container checks and exclusive publication.

## 7. Data subset

Existing codec string Copy original paired with encoder copy. Existing rate, quality, speed and backend values remain stored and are explicitly inactive in copy mode. Older readers reject this unknown pair rather than silently treating a new optional field as absent. No session, journal or preset schema field is added. Audit records exist only in operation-owned staging.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S37-001 | Copy intent round-trips and incompatible settings/sources refuse with remedies | Session/preset/journal and plan tests; encoder availability is not required for copied video | copy-intent |
| S37-002 | Bounded streaming audit requires complete matching payloads, presentation times and packet durations | Fragmented input, malformed/duplicate/missing records, count/size/hash/timing/metadata negatives and cancellation | copy-audit |
| S37-003 | Actual H.264 and VFR HEVC copies work in both containers with existing track/chapter/caption routing | Independent decoded pixel hashes/frame times and generated audio alignment; protected originals | copy-timeline |
| S37-004 | Successful tool exit cannot publish an altered candidate | Real altered staged output, existing destination protection, cleanup and later-job state | copy-publication |
| S37-005 | Native users can select, correct, save/reopen and complete this workflow | Light/dark native controls, accessibility labels, incompatible-picture correction and actual verified export | copy-native |
| S37-006 | Existing behavior remains qualified | Optimized build, full ordinary local/hosted tests and planning audit | copy-regression |

## 9. Verification evidence required

Capture selected source video packet size, SHA-256, integer presentation timestamp and positive packet duration. Require a complete ordered match, identical extradata and relevant video/display/color metadata. Compare presentation times and packet durations within the larger source/output tick, each at most one millisecond; this is per-packet precision, never an accumulating tolerance. Bound lines to 512 bytes, packet count to two million, packet size to 64 MiB and manifest to 128 MiB. Use fixed-width records (56 bytes: timestamp, duration, size and SHA-256) and bounded I/O buffers rather than retaining every packet in RAM. Enforce successful child completion, nonempty/complete framing, finite supported time bases/timelines and full record count. Keep descriptor ownership and file work off the UI actor; await subprocess and file settlement before cleanup. Check source identity around processing as before. Negative references must catch both a 125 ms shift and a missing packet despite apparently acceptable codec/duration.

## 10. Guardrails

No silent filter removal, settings reset, codec fallback or fast-success claim. Preliminary checking does not fabricate a full packet audit. A copy refusal leaves correction possible. Native Quick Export stays independent. Production privacy, source protection, cancellation ownership, staged verification and no-overwrite publication remain authoritative.

## 11. Definition of done

All six gates have final-head scoped evidence. Record failed experiments and coverage limits. Do not claim full-program, hearing/accessibility, mastering or production-release acceptance.

## 12. What this unlocks

Verified video reuse inside the existing advanced queue, so a track or container change need not introduce video generation loss.

Approved for build by: Owner autonomous non-audio program-completion delegation, 2026-10-01; D-067 / R-047.
