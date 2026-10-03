# Slice 046: Inspect HDR and spatial audio before choosing conversion
Version: 0.1.
Date: 2026-10-03. Status: Approved for build under D-084 / R-056.

## Outcome and walkthrough

Open a source, inspect HDR declarations and chroma placement, then choose audio tracks with their actual reported codec profiles visible. Dolby Vision layers, RPU presence, profile, level, version and base compatibility ID are shown without inferring FEL/MEL or a supported conversion. AAC/Opus guidance explains loss of object metadata. An unqualified dynamic-HDR transcode fails with a specific reason even if color tags are absent or misleading.

## Scope and build order

M1: Preserve the bounded ffprobe Dolby configuration fields in the existing typed probe. Add declared-format presentation to the native inspector and audio routing/settings. Unknown, invalid and duplicate declarations stay explicit. No filename/title-based format inference.

M2: Add a shared dynamic-HDR transcode refusal before SDR/static-HDR planning, and an audio conversion consequence in the actual plan summary for selected tracks only. Existing copy admission, processing, cancellation, publication and persisted formats remain unchanged.

M3: Typed boundary and adversarial planner checks, native inspector/routing inspection, optimized build and ordinary regression. Keep private media names/paths out of code, fixtures, public evidence and commits.

## Gates

| Gate | Required evidence |
| --- | --- |
| hdr-declarations | Exact decoded fields, missing/invalid/repeated records and no FEL/MEL inference |
| conversion-information | Recognized dynamic metadata refuses SDR/static HDR10 before encoding; selected spatial-audio conversion explains object loss |
| format-native | Native fields, routing profile, clear guidance and accessibility values |
| format-regression | Swift tests, optimized build, ordinary hosted checks and clean private-name scan |

## Limits

This slice does not implement Dolby Vision, HDR10+, HLG, AV1 preservation or any new re-encoding path. Header declarations are not full-frame measurements. Existing copying checks do not yet certify complete audio or embedded subtitle payloads. Audio listening remains parked. Slice 045's visible Dock qualification remains open independently.

Approved by: Owner explicit preservation/conversion request and autonomous implementation delegation, 2026-10-03. Verification uses generated data and existing local native seams. No new dependency, model, observer, deadline, merge or release.

Checkpoint: declarations/refusal checks, optimized bundle and native accessible field/profile/notice inspection pass. Ordinary local regression passed 289 tests; hosted initial 37108911207 passed 289 tests. Native inspection led to a shared static-text role/combined-label repair. Hosted qualification of that repair remains open; no acceptance of broader format preservation, heard VoiceOver or release follows.
