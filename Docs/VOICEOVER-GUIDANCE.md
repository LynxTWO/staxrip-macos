# Layered VoiceOver guidance

Approved by Daniel Boyd on 2026-09-28 in the project conversation. This is an accessibility refinement to the measured-report walkthrough and the existing encoding controls, not a new audio-processing slice.

## Contract

Keep familiar visible names. Speak a concise purpose and a separate current value. Put codec expansions and consequences in optional hints, with a visible Encoding terms reference available from the sidebar. Native controls provide their roles. Do not hard-code “button” into labels, override system VoiceOver verbosity, or introduce a separate speech engine.

- Presets identify themselves as presets; H.264's hint explains AVC / Advanced Video Coding. Original preset names remain Voice Control input labels.
- CRF, bitrate and loudness fields explain units and consequences. Native editable values remain intact.
- Measurements expose separate labels and values, including unavailable reasons. Channel positions are expanded. Speech fields and removal actions identify the interval number.
- Charts retain Swift Charts' native accessible data representation, with a concise title and explanation of the two window lengths. Detailed chart navigation still needs VoiceOver listening verification.
- Source hashes stay available behind a disclosure, avoiding an unsolicited 64-character reading.
- Audio Lab posts one native completion, cancellation or error announcement when an operation ends while the view is present. Progress remains queryable; individual updates do not post announcements. It does not move keyboard focus.
- Queue removal explicitly removes the configuration, not the media. Move actions identify the source and direction.
- An interval beyond the file duration identifies the interval and valid upper bound.

## Acceptance record

Daniel confirmed the prior functional walkthrough: “Everything works!” This is functional acceptance, not a claim that VoiceOver pronunciation or the new guidance has passed a listening walkthrough.

Verification for this refinement: build, existing regression suite, and native accessibility inspection of preset hints, glossary, measurements and numbered interval controls. Actual pronunciation, announcement timing, chart interaction and comfort across VoiceOver voices/settings remain a listening check. This document is not an accessibility certification.

## Listening checklist

1. Navigate the three presets with hints enabled. Hear a short preset name, native role, and optional explanation without duplicated role words.
2. Open Encoding terms; navigate headings and explanations, then close with Escape. Focus should return to the opener.
3. In Audio Lab, read the four measurements. Hear their names, signed values and appropriate units. For silence, hear the unavailable reason.
4. Add two intervals. Identify which start, end and remove action belongs to each. Read the saved interval results.
5. Start, cancel and retry measurement. Check that progress can be queried and a final status is announced without stealing focus or repeated progress speech.
6. Explore both chart series. Check that time/value information is useful and the entire trace is not automatically spoken.
7. Repeat with hints disabled. Labels, values and essential status must still identify the controls. Full definitions remain available in Encoding terms.

References: [Apple accessible descriptions](https://developer.apple.com/documentation/swiftui/accessible-descriptions), [native announcement notification](https://developer.apple.com/documentation/appkit/nsaccessibility-swift.struct/notification/announcementrequested).

## Implementation verification, 2026-09-28

The debug build and existing regression suite passed (47 tests in eight suites; optional EBU corpus and long-profile tests skipped in this run). Native inspection confirmed the three preset hints, CRF hint/value, glossary headings and Escape dismissal, numbered interval fields/removal, four separate metric items, and separate front-left/front-right readings with expanded peak units. Inspection caught SwiftUI merging adjacent static readings; explicit accessibility groups preserve their individual labels and values. Actual speech output and announcement delivery were not captured, so the listening checklist above remains open.
