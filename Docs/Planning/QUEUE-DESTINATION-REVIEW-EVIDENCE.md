# Queue destination review evidence

Date: 2026-10-01. Slice 029 under D-043 / R-033. Product head 485ea85 has local and native evidence. Hosted run 36818937608 passed at that head.

## S29-001: ordered folder review

Native Start queue now passes through WorkspaceModel and the existing attached file presenter. It captures the session snapshot and pending job identities, standardizes destination folder paths and deduplicates them in queue order. Completed jobs do not request another folder review; an empty or completed-only queue does not start or present a sheet.

Every sheet receives a fresh workspace request identity. The first folder uses Continue and the last uses Start queue. The message states that execution follows the last review and cancellation starts nothing. Selection is an exact configured-path match, not a relink or stored permission.

## S29-002: refusal and recovery protection

Controlled presenter tests cover repeated starts and competing file commands, a duplicate first callback while the second sheet is open, an old second callback after a retry, first/second sheet presentation refusal, wrong/remote locations, changed job destination/order/settings/source-load identity, changed pending identities, missing tools and unavailable/running execution at either folder. Cancellation, mismatch and refusal release ownership for retry. Existing journal bytes and empty output directories remain unchanged.

An initial expectation constructed expected directory URLs with file semantics; it was corrected to explicitly mark the folders as directories. Product checks were unchanged. No assertion, deadline or prior opt-in policy was relaxed.

## S29-003: native three-job walkthrough

The macOS 27.0.1 ad-hoc app loaded a generated session with three two-second H.264 jobs in two distinct folders. A manually prepared fixture initially used a numeric creation date and was rejected; it was corrected to the existing ISO 8601 schema. The corrected source was explicitly reviewed and loaded before execution testing.

Start queue presented folder 1 of 2 as an attached sheet. Its configured path, start boundary and cancel text were visible. Selecting Output A advanced directly to folder 2 of 2 despite two jobs sharing Output A. The final button said Start queue. Cancelling returned all three jobs to Ready, with unchanged source/session hashes, no outputs or staging and byte-for-byte identical prior recovery data.

Retrying reviewed Output A and Output B once each. The final selection completed all three jobs. Independent ffprobe inspection confirmed H.264, 640 by 360 and two seconds for all three files. Source/session hashes stayed unchanged; output folders held exactly the three expected files, with no staging. Start queue became disabled for the completed queue. The generated completed journal was retained locally, then the exact prior journal was restored only after the app exited.

This successful run does not establish the cause or elimination of earlier filesystem publication waits. The existing interrupted-staging evidence remains preserved.

## S29-004: real execution and regression

A focused generated test runs the actual BatchController after matching both folders, skips a completed job in a third location, ignores duplicate callbacks, and verifies all new outputs and the completed journal. Existing completed-output and source bytes remain unchanged.

| Scope | Result |
| --- | --- |
| Focused lifecycle and real three-job batch | 5 tests passed in 0.334 seconds |
| Full local release | 210 tests / 43 suites passed in 38.680 seconds |
| Ad-hoc app build | Passed in 15.54 seconds |
| Hosted 36818937608 / 485ea85 | Swift 6.1.2, 210 tests passed in 506.050 seconds; destination suite 58.341 seconds |

Ignored queue-destination logs and queue-start-native verification records retain local receipts. Draft PR 46 is unmerged. No media, binaries, private paths or credentials are committed.

Durable permissions, arbitrary filesystem latency/capacity, other platforms and heard VoiceOver remain separate. Batch admission, source fingerprints and exclusive publication are unchanged. Audio listening stays parked. S29-001 through S29-004 are accepted within this scope.
