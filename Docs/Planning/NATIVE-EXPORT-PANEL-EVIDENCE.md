# Native export destination dialog evidence

Date: 2026-10-01. Slice 027 under D-041 / R-031. Product head 70d0ac6 has local and native evidence. Hosted run 36815249560 passed at that head.

## S27-001: request lifecycle

Quick Export now uses WorkspaceFilePanels through WorkspaceModel. It shares the established single request ID, one-shot selection callback, saved-intent comparison and source-load identity checks. The chosen native preset must remain current, and the view's audio/batch availability predicate is checked before presentation and after selection. NativeExportService is unchanged; its caller no longer owns a nested runModal save panel.

Focused counterexamples cover cancellation, refused presentation, retry, duplicate and old callbacks while a newer request is open, changed source URL, unchanged persisted intent with a new load identity, changed preset/settings, unavailable source, pending source review and competing execution. Cancel and refused/stale callbacks retain a previous result rather than clearing it. The initial generation fixture called cancelSourceLoad while idle, which correctly did not change identity; it was corrected to change the generation through showDemo and restore identical persisted intent. No product guard was weakened to pass that fixture.

## S27-002: actual execution and file protection

A generated 160 by 96 MP4 was exported through the actual panel callback and NativeExportService. A duplicate callback targeted another path but did not create it; another request during execution was refused. The first export completed as H.264. A cancelled later selection retained its result. Selecting the already existing output caused the established export failure without changing either the source bytes or prior output bytes. No staging or duplicate output remained.

## S27-003: native walkthrough

The macOS 27.0.1 ad-hoc app opened a generated 640 by 360, 24 fps, two-second MP4 and selected the native 720p preset. Export MP4 presented an attached destination sheet. During the sheet, the native File menu disabled Open Source, Save Session, Open Session and Add Configuration to Queue. Keyboard cancellation restored the commands and retained the source, selected preset and ready status.

Reopening and choosing a new generated filename completed export. Independent ffprobe inspection reported H.264, 640 by 360 and 2.000000 seconds; the native preset did not upscale this smaller source. A further save-sheet cancellation kept the completed result and preset visible. Source SHA-256 was unchanged, with no extra output or staging. No queue recovery record or user media was changed by this walkthrough.

A separate naming discovery entered the generated existing output in the native panel and observed the system Replace confirmation. Both that confirmation and the original sheet were cancelled; source/output hashes and completed result stayed intact. This confirms the remaining wording limitation without accepting a replacement.

## S27-004: regression receipts

| Scope | Result |
| --- | --- |
| Focused lifecycle and real native export | 3 tests passed in 0.093 seconds |
| Full local release | 203 tests / 41 suites passed in 37.895 seconds |
| Ad-hoc app build | Passed in 15.47 seconds |
| Hosted 36815249560 / 70d0ac6 | Swift 6.1.2, 203 tests passed in 440.625 seconds; native panel suite 11.935 seconds |

Existing opt-in exclusions and all prior assertions/deadlines remain unchanged. Ignored native-panel logs and native-panel-native verification.json retain the local observations. Draft PR 44 is unmerged. No media, binaries, private paths or credentials are committed.

System existing-file Replace wording, durable file access, arbitrary filesystem waits, other platforms and heard VoiceOver remain separate limitations. Audio listening stays parked.

S27-001 through S27-004 are accepted within the recorded scope.
