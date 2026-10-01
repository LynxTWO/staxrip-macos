# Restored source review evidence

Date: 2026-10-01. Slice 025 under D-039 / R-029. Product head 42c8c07 has local regression and native evidence; hosted run 36812490982 passed at that head.

## Scope

Session restoration applies validated saved intent and records the source reference without inspecting or reading that media. Explicit matching-path review starts the existing owned source reader. Path equality is not byte identity or durable access. Standard Open source retains its separate replacement semantics. No session schema, queue encoding or audio algorithm changed.

## S25-001 and S25-002: lifecycle evidence

Seven source lifecycle tests passed in 0.009 seconds. A held older read is cancelled and allowed to settle without launching a reader for the restored path. Explicit review then starts one read. Injected picker cases cover cancellation, wrong path, changed configuration, changed load identity, duplicate callbacks, reentrant requests, failed reads and successful retry. Full saved configuration, external captions, output naming and queue survive each appropriate path. Reader concurrency remains one. Existing source replacement and cancellation assertions remain in place.

## S25-003: native walkthrough

The generated session restored in the ad-hoc macOS 27.0.1 app with the saved source name, crop, H.264 CRF 18 configuration, omitted audio, external caption reference, MKV destination and custom output name. It displayed an explicit review state rather than decoder failure; tracks, inspection and filtered preview were disabled. The review picker was attached to the workspace and explained matching-path selection. Cancelling returned to the same recipe.

Quick Export also offered Review saved source and disabled Export MP4. Choosing a different generated video produced a refusal explaining the standard Open source replacement route and retained the saved session. Choosing the exact saved path loaded a 640 by 360, 24 fps, 60-second preview and enabled native export. Returning to Workspace retained the recipe. Saving a second session produced a document equal to the complete original JSON value, including all configuration fields, source, destination and queue.

Source, original session and caption SHA-256 values remained unchanged. The proposed encoded output was absent. No encode or audio listening was performed for this walkthrough. Native picker cancellation is not evidence for cancellation of an already running framework read; controlled reader tests cover ownership and retry. The earlier CoreMedia wait remains a recorded limitation for arbitrary native I/O.

## S25-004: regression receipts

| Scope | Result |
| --- | --- |
| Session format suite | 3 tests passed in 0.004 seconds |
| Focused source lifecycle | 7 tests passed in 0.009 seconds |
| Full local release | 197 tests / 39 suites passed in 38.532 seconds |
| Ad-hoc app build | Passed in 15.96 seconds; native journey above |
| Hosted 36812490982 / 42c8c07 | Swift 6.1.2, 197 tests passed in 479.518 seconds |

The full suite retained 16 existing opt-in skipped entries. No deadline or test scheduling changed. Ignored receipts are restored-source logs and restored-source-native generated fixtures and verification.json in the work directory. No media, credentials, binaries or absolute local paths are committed. Draft PR 42 remains unmerged. Audio listening, durable file access, other platform qualification and release approval remain open.

S25-001 through S25-004 are accepted within these evidence limits.
