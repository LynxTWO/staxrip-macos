# Production planning context
Version: 0.1 Draft. Date: 2026-09-28.

Source: owner requests in the project conversation; current source at ded2ad3; existing LOUDNESS-DESIGN.md and RELEASE-SCOPE.md. Protocol: Scaffold Kit v0.4 branch, revision e0b8df1acee6a9ab62e7351afc9a1ef6bcb9b30e. Its bundled Conductor retains a 0.3 header; the loader, updated build gate and templates come from the v0.4 revision. No claim that main or a release tag is v0.4.

## Intake and triage

Build a native macOS video/audio workstation with trustworthy encoding and original dialogue-aware loudness processing. Users choose a target, inspect what will change, process locally, and receive a measured result without overwriting their source. Smart mastering should respect programme intent; Night / Venue should reduce disruptive changes without flattening all contrast. Metadata is a diagnostic input, never proof of measured dialogue loudness. Public code does not publish users' media or credentials.

- Shape: existing desktop app, SwiftUI and AppKit.
- Tier: T2 product; security, privacy and permissions receive T3-depth treatment because local media and paths can be personal.
- Team: owner plus coding assistant; existing delegation permits routine recommendations.
- Run mode: fast-run draft using prior answers and flagged proposals. No new application implementation in this planning turn.
- Depth: standard, with audio measurement details where needed.
- Platform: macOS 14+ is the declared package floor; current evidence is narrower. Intel support remains a proposed validation target, not a tested promise.
- Timeline: staged, no calendar commitment. Budget: no new paid services or purchases authorized by this plan.
- Confirmed: native Mac, local processing, two mastering workflows, direct measurement, public repository, PR tracking.
- Proposed: meter/report first, then dialogue planning, multichannel, HDR, production qualification.
- Open: software license, final platform matrix, corpus rights, speech model choice, Developer Program eligibility.

## Slice growth tally

The original normalizer now needs five explicit supporting capabilities: meter integration and validation, speech identification, constrained gain planning, multichannel preservation, and comparative listening evidence. HDR adds a separate color/timing path. Neither bundle belongs in one PR. Publication and signing are operational work, not evidence that the audio algorithm works.

## Proposed sequence

| Order | Slice | User outcome | Exit evidence |
| --- | --- | --- | --- |
| 001 | Independent analysis report | Inspect measured programme, channel and manual-dialogue results with confidence and provenance | Standards fixtures, cross-meter comparison, cancellation and saved-report round trip |
| 002 | Dialogue-aware stereo master | Review detected dialogue and an editable gain plan, compare level-matched excerpts, export Smart or Night result | Annotated speech evaluation, gain constraints, final encoded measurements, listening review |
| 003 | Multichannel master | Process explicit 5.1 and 7.1 layouts with linked gain and separate LFE policy | Channel impulses, order/layout checks, image/phase preservation, downmix tests |
| 004 | HDR and color pipeline | Choose preserve HDR or explicit SDR conversion with truthful preview | 10-bit PQ/HLG fixtures, primaries/transfer/matrix/range checks, decoded levels and metadata tests |
| 005 | Production qualification | Install, use, recover and update a signed app on supported Macs | Full films, long-run failures, accessibility, clean-machine setup, signing/notarization and rollback |

Model-based work in 002 starts with a bounded model/license/performance spike before selecting a dependency. HDR dynamic metadata and object-based audio are separate future scopes, never silently flattened under a preservation label. Each later slice gets its own approved brief.

## Reuse update

Owner identified SignalForge as a source of existing work. D-010 and SIGNALFORGE-REUSE.md make a bounded reuse investigation the first milestone. Independent means separate from the current mastering path and checked against independent evidence; it does not require inventing standard metering algorithms again.

## Production prerequisites beyond the five headline stages

The existing RELEASE-SCOPE.md ledger remains authoritative for unresolved features. Before qualification, create focused briefs for filtered preview/frame stepping; rotation/remux and timestamp handling; per-track recipes, external subtitles, chapter/attachment editing; audio-session persistence, custom presets and undo. These are not silently included in the meter slice or declared complete by packaging. Each needs a user-visible walkthrough and evidence before the release ledger can close. Qualification then covers VFR/anamorphic and long-film A/V sync, subtitle retiming, crash/multi-instance recovery, disk-full and removable/network destinations, stale staging ownership, codec quality/speed and supported OS/hardware accessibility.

HDR stage acceptance must distinguish 10-bit PQ/HLG preservation from SDR tone mapping. Confirm source/output color primaries, transfer, matrix, range, mastering/content-light metadata when present, codec/profile/pixel format and timing. Compare decoded reference frames and inspect on an HDR-capable display. Dynamic HDR metadata is unsupported unless a separate brief proves preservation; reject or explicitly convert it. Multichannel stage requires declared layouts, common gain envelopes that preserve spatial relationships, separate LFE treatment and no count-only channel inference. Dialogue metrics and LFE diagnostics must never be mislabeled as standard programme LUFS.
