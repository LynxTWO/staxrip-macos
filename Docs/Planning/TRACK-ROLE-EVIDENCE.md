# Track identity and role inspection evidence
Date: 2026-10-01. Scope: Slice 043 / D-081 / R-053.

## Baseline and contract

Plan 8d7612e precedes implementation; baseline e8c583b has accepted caption playback choices. This change reads existing probe metadata and presents five declared roles. It does not edit media, saved schemas, export rules or selection indices. Missing and invalid flags are never presented as Not set.

Primary definitions: https://www.ffmpeg.org/doxygen/trunk/avformat_8h.html . The source declares intended role, not verified content suitability or player behavior.

## Focused checks

Seven tests in two suites passed in 0.342 seconds: TrackInspectionTests and existing ContainerInspectionTests. The command also named a nonmatching TrackSelectionTests filter; it contributed no tests and is not counted as coverage. Typed checks distinguish all four flag states, absent/invalid partial dictionaries, future unknown flags, case-insensitive names/languages, title-before-name preference, Unicode and bounded/control-character display. The generated actual MKV has default/forced/hearing flags and a declared English caption title; all five presented states match the probe, and complete file bytes/directory listing remain unchanged. Existing chapter/attachment and superseded-inspection behavior also passes. Local log: work/track-roles/focused.log.

## Native finding and correction

At product 7b4494c, the expanded role fields visually showed the correct names and values, but the accessibility tree inherited the disclosure group's label for all five rows. This fails the native clarity gate. Move the contextual accessibility label onto the disclosure's label view so each field retains its own Default, Forced, Hearing accessibility, Visual accessibility or Commentary name. This is a UI-only correction, not a metadata or selection change. Final native reinspection is required before acceptance.

The same initial native walkthrough confirmed Escape closes the inspector. Both audio indices and the caption began selected; unchecking audio index 1 then Cancel retained all three; applying that subset and reopening retained only audio index 2 and caption index 3. Source metadata showed default/forced/hearing set on caption index 3, with visual/commentary unset. No export was launched.

Full local regression at 7b4494c: 278 tests in 67 suites passed in 210.796 seconds; 25 existing opt-in/tool-dependent skips. Optimized build at that head passed in 17.49 seconds. The label-only correction is ce27093; no helper, selection or test code changed. Its optimized build passed in 18.12 seconds.

## Final native walkthrough

At ce27093, opened the prior generated caption output in the optimized app. Its three subtitle titles/languages were Unspecified/Unspecified, French/fra and English/eng. Their default/forced states were 0/1, 1/1 and 0/1; the embedded track retained its hearing-accessibility declaration. Expanding French showed five individually named accessibility fields with correct Set/Not set values and explanatory hints. Native screenshots showed the matching visible labels. The disclosure retained its source-track context without renaming the child fields. Escape dismissed the sheet.

Choose tracks showed the same bounded labels and summaries. Applying an unchecked French track and reopening retained indices 1 and 3. Unchecking index 1 and escaping cancelled the draft; reopening still showed 1 and 3 selected. The app was quit normally. Whole-file SHA-256 checks of both source and prior output matched the pre-walkthrough record, and the owner's recovery journal remained byte-identical. No export, playback, session save or journal restoration was performed in this slice. Private receipt: work/track-roles/native/verified.json. This is native visual/accessibility-tree and keyboard evidence, not a heard VoiceOver result.

## Remaining gate

Ordinary hosted regression is pending. No full acceptance claim yet. Heard VoiceOver, player behavior and other metadata flags remain outside scope.
