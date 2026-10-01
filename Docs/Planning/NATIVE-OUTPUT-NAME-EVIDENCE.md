# Native output name correction evidence

Date: 2026-10-01. Slice 028 under D-042 / R-032. Product head 70c17da has local and native evidence. Hosted run 36817176434 passed at that head.

## S28-001: candidate validation

The save sheet retains its weak AppKit delegate through completion. Only confirmed filename submissions are checked, at the documented callback before automatic extension append and replacement confirmation. A local extensionless candidate receives .mp4 for checking; explicit mixed-case MP4 suffixes remain valid. The delegate returns the original name on success, never an automatic alternative.

Generated tests cover explicit, extensionless, mixed-case and Unicode names; invalid URL/type/extension/NUL inputs; existing files, directories and dangling symlinks; and an indeterminate path through a regular-file parent. Entry checks refuse existing or indeterminate results. No file is created by validation. An initial fixture incorrectly described a directory as an extensionless file URL; it was corrected to set the directory flag. The product guard was not weakened.

## S28-002: native correction and cancellation

On macOS 27.0.1, a generated two-second H.264 source opened in Quick Export. Submitting an existing MP4 name kept the attached save sheet open with: An item already uses this name. Choose a new MP4 name; nothing was replaced. No Replace confirmation appeared. Extensionless and upper-case suffix variants produced the same refusal on this case-insensitive filesystem.

The correction message fit visibly in the compact native sheet, with the name field and buttons available. Cancel returned to the ready state without changing the source or preset. Reopening restored the original save-sheet message. The implementation posts an accessibility announcement; heard VoiceOver remains unverified.

## S28-003: corrected export and independent race protection

After a repeated collision, an extensionless fresh name exported as corrected-native.mp4. Independent ffprobe inspection reported H.264 and 2.000000 seconds. Source and existing output SHA-256 values stayed unchanged; no extra staging or output files remained. No queue recovery record was changed.

A generated race test first validated an absent name, then created a competing destination before exclusive publication. Publication refused, preserving both the competing bytes and staged bytes. Name validation is a usability aid and does not replace service protection. A concurrent writer after validation may still cause a later system confirmation or export refusal.

## S28-004: regression receipts

| Scope | Result |
| --- | --- |
| Focused names and publication race | 2 tests passed in 0.002 seconds |
| Full local release | 205 tests / 42 suites passed in 38.196 seconds |
| Ad-hoc app build | Passed in 15.60 seconds |
| Hosted 36817176434 / 70c17da | Swift 6.1.2, 205 tests passed in 467.993 seconds; name suite 0.234 seconds |

Ignored native-name logs and native-name-native verification.json retain observations and hashes. Draft PR 45 is unmerged. Existing opt-in exclusions and prior assertions/deadlines are unchanged. No media, binaries, private paths or credentials are committed.

A synchronous name check does not guarantee arbitrary filesystem latency, durable access, future availability or capacity. Other platforms/filesystems and heard VoiceOver remain open. Audio listening stays parked. S28-001 through S28-004 are accepted within this scope.
