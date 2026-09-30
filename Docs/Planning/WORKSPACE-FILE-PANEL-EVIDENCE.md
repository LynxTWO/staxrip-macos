# Workspace file dialog evidence

Date: 2026-09-30. Slice 016, D-029 / R-019. Status: scoped local, native and hosted acceptance passed.

## Implemented contract

Workspace source, destination, session open/save and queue-reference export now use a shared native sheet presenter. A missing parent window or an existing dialog is refused without queuing another request. File commands and Add Configuration are disabled in the app menu while a workspace file request is active. The model also enforces one request independently of the UI.

The model consumes a selection callback only once and ignores callbacks from completed requests. Source/folder/session-load results must still match the request's workspace document and source-load identity. A session replacement keeps its explicit confirmation, checks current intent again when confirmed, validates the document and never starts encoding. Save session and Export JSON write the snapshot from the beginning of the request; newer edits stay in the workspace and are reported as unsaved or changed. Existing JSON formats and atomic save behavior are unchanged.

The native presenter orders out a file sheet and delivers its callback on the next main-queue turn so a following confirmation can attach after dismissal. This follows the [NSSavePanel completion guidance](https://developer.apple.com/documentation/appkit/nssavepanel/beginsheetmodal(for:completionhandler:)). Explicit request guards avoid the implicit sheet queuing described in [NSWindow's sheet documentation](https://developer.apple.com/documentation/appkit/nswindow/beginsheet(_:completionhandler:)).

## Automated checks

Six focused functions passed in 0.012 seconds with an injected presenter and actual generated JSON files. They cover cancellation for all five actions; duplicate requests; duplicate and old selection callbacks; missing presenter availability; workspace edits and source-generation changes during a chooser; session chooser and replacement cancellation; stale and repeated confirmation; failed confirmation presentation; exact captured session and queue contents; unsaved changes after a delayed save; malformed session and failed writes; request release and subsequent retry. Session restoration does not create the configured encoded output, and queue-array export cannot be loaded as a session.

The four existing external-subtitle persistence functions also passed after the refactor. The final optimized regression passed 149 tests in 29 suites, 15 opt-in skips, in 36.438 seconds. The optimized ad-hoc preview build passed in 13.34 seconds. Logs and generated fixtures are retained in ignored local `work/workspace-file-panels`. No user media or absolute local paths are committed.

## Native walkthrough

macOS 27.0.1 / Apple M5, local preview. All five file flows presented visible attached sheets. Source selection opened a generated one-second SDR MP4. Cancelling a later source selection kept that source and output stem. Cancelling destination selection retained Movies; explicitly choosing the generated fixture folder updated the destination. A generated H.264 job was added without starting it.

Session save cancellation created no file and retained the workspace. Saving produced a version 6 document with the expected one-job configuration. After changing the workspace to AV1, cancelling the open chooser retained AV1. Selecting the H.264 session opened an attached replacement confirmation: Cancel retained AV1 and the queue; confirmation restored H.264 and the original queued job without execution. Saving the restored document produced structurally identical JSON.

Queue-reference export cancellation retained the Ready job and wrote nothing. Confirmed export produced a JSON array exactly matching the saved session's jobs. No encoded output was created. The generated source SHA-256 remained unchanged.

Command-Shift-S opened the attached save sheet. While it was active, Open Source, Save Session, Open Session and Add Configuration were disabled in the native File menu. Escape cancelled the save; the commands became enabled again, and the queue remained Ready. The source of brief direct-path-dialog timing during automation was not treated as a product failure; refreshed native state confirmed the selected path before each Open action.

## Remaining gate and limits

Hosted macOS run 36787875488 passed at 42634d9: Swift 6.1.2, 149 tests in 460.171 seconds, job duration 8m43s. Draft PR 33 remains unmerged. This is a workspace file-dialog lifecycle change, not a guarantee that every synchronous filesystem operation is responsive. Session reads/writes remain bounded synchronous operations. Audio, preset, Quick Export and termination dialogs are unchanged. Durable permission bookmarks, slow/network/removable filesystems and broader OS/CPU/accessibility qualification remain separate. No listening, merge, signing, notarization or public release acceptance is included.
