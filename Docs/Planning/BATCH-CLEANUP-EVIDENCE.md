# Batch cleanup evidence
Date: 2026-09-30. Scope: Slice 009, D-022. Status: Automated, native and hosted checks passed.

## Behavior

Advanced queue jobs await removal of their own staging directory after the encoder process has exited and its pipes have drained. The shared ExportStaging helper retries wrapped transient EBUSY/ENOTEMPTY errors at most six times with 1.55 seconds total backoff, including when cancellation has already been requested. Permanent errors return immediately. This bounds retries, not a blocked operating-system filesystem call.

A removal failure carries the original operation error and any published destination separately. Successfully published media remains Completed with a cleanup warning and Reveal output available. A cancelled or failed operation retains that phase and reports no output publication. The warning includes the remaining directory and underlying removal error. The batch stops before later jobs. Existing recovery detail persists the same outcome; a separate journal failure remains a recovery warning. No recovery schema, dependency, audio processing or historical-staging deletion is added.

The native export helper/error were renamed for shared use. The preset export's existing error reference was updated mechanically; its behavior is unchanged. Cancellation wording now says that the operation was cancelled rather than exposing an opaque Swift cancellation error.

## Automated receipts

Ten focused tests in two suites passed in 0.568 seconds, including three new batch scenarios across two parameterized tests. A real generated H.264 encode with injected EACCES cleanup retained both the readable published output and owned staging; state remained Completed, the second job stayed Pending, and restored recovery preserved the warning. Retrying only that completed job did not run or change its output.

Controlled encoder scripts wrote an owned partial file, then either exited 42 with a known error marker or were cancelled while running. At the cleanup seam, their process identifiers no longer existed. Injected removal failure preserved Failed or Cancelled, the original failure/cancellation text, retained staging and the warning path. Neither final output existed, the next job stayed Pending, and recovery round trips retained status and detail. Source bytes and an unrelated staging-like sibling directory were unchanged in every case.

Existing shared-helper tests cover wrapped transient retries after cancellation, maximum retries, immediate permanent failure, already-absent directories and missing-child errors that must not hide a surviving directory. Existing real batch cancellation/success tests exercise default cleanup without injection.

After the cancellation wording refinement, the full release regression passed 109 tests in 20 suites in 10.125 seconds, with 14 existing opt-in skips. Existing audio regression tests do not constitute new audio acceptance. The optimized ad-hoc app built in 11.78 seconds. Hosted macOS validation passed in 8 minutes 35 seconds at product commit 8eef657: [run 36711323507](https://github.com/LynxTWO/staxrip-macos/actions/runs/36711323507/job/109873555003).

## Native receipt

Two generated one-second portrait jobs were opened as a session and explicitly started through the native queue on macOS 27 / Apple M5. Both displayed Completed with Reveal output. Independent ffprobe inspection confirmed H.264, 96 by 160 pixels and one-second duration for each file. The generated source SHA-256 stayed identical; no owned batch staging directory remained. The existing journal recorded both Completed outcomes without cleanup warnings. The prior local journal was preserved in private scratch before the walkthrough.

The UI inspection tool returned noWindowsAvailable once during processing. The app process remained alive, no new crash report appeared, and reconnecting showed both completed jobs without relaunching. A sampled main thread was in its ordinary event loop. This transient inspection failure is not a native fault-injection test or a crash diagnosis. Final AX and screenshot inspection confirmed the completed statuses, output actions and updated footer; owner VoiceOver listening remains separate.

## Limits

Permanent removal errors are injected through a test-only constructor dependency; no native fault-injection UI or permission changes are used. Network/removable filesystems, blocked kernel calls, forced-crash leftovers and older operating systems remain unqualified. No stale directory is automatically found or removed, and a recovery path is never treated as a deletion capability. The local app remains an ad-hoc development build.
