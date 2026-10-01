# Track identity and role inspection evidence
Date: 2026-10-01. Scope: Slice 043 / D-081 / R-053.

## Baseline and contract

Plan 8d7612e precedes implementation; baseline e8c583b has accepted caption playback choices. This change reads existing probe metadata and presents five declared roles. It does not edit media, saved schemas, export rules or selection indices. Missing and invalid flags are never presented as Not set.

Primary definitions: https://www.ffmpeg.org/doxygen/trunk/avformat_8h.html . The source declares intended role, not verified content suitability or player behavior.

## Focused checks

Seven tests in two suites passed in 0.342 seconds: TrackInspectionTests and existing ContainerInspectionTests. The command also named a nonmatching TrackSelectionTests filter; it contributed no tests and is not counted as coverage. Typed checks distinguish all four flag states, absent/invalid partial dictionaries, future unknown flags, case-insensitive names/languages, title-before-name preference, Unicode and bounded/control-character display. The generated actual MKV has default/forced/hearing flags and a declared English caption title; all five presented states match the probe, and complete file bytes/directory listing remain unchanged. Existing chapter/attachment and superseded-inspection behavior also passes. Local log: work/track-roles/focused.log.

## Remaining gates

Native inspector/routing, optimized build and ordinary full local/hosted runs pending. No acceptance claim yet. Heard VoiceOver, player behavior and other metadata flags remain outside scope.
