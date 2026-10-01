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

## Ordinary regression and acceptance

Hosted pre-label run 36913229041 at 7b4494c passed all 278 tests in 556.936 seconds, build 88.86 seconds. Final ordinary hosted run 36914015358 at ce27093 passed all 278 tests in 606.103 seconds, build 92.17 seconds. Each has 25 existing opt-in/tool-dependent skips. Local full regression at 7b4494c passed 278 tests across 67 suites in 210.796 seconds, with the same 25 skips; no repeated full local run was needed for the single label-placement correction, which was rebuilt and directly verified in the native app. Hosted macOS 15 arm64/Swift 6.1.2 and local macOS 27.0.1/Swift 6.4 use Swift language mode 5. Existing NativeExport Sendable and ChapterPersistenceTests asynchronous Thread.isMainThread warnings remain, without a warning-free claim.

All four gates are accepted at product ce27093 under D-081 / R-053: typed/source, native and ordinary regression checks match their scope. Selected planning audit: zero findings across 46 documents; git diff check passed. Private hosted logs are work/track-roles/hosted-before-label.log and hosted-final.log. The earlier hosted mastering cancellation issue did not recur in either run; its cause remains unresolved. No merge or release occurred.

Heard VoiceOver, player behavior, other metadata flags and broader platform coverage remain outside scope. This presentation change does not verify accessibility content or add codec support.
