# APFS capacity recovery evidence

Date: 2026-10-01. Slice 031 under D-045 / R-035. Implementation and acceptance in progress.

## Discovery and failure boundary

A newly created 64 MiB APFS image reports 67067904 bytes and a distinct mount device. The opt-in helper generates a UUID marker and the test verifies it, APFS type, capacity at most 64 MiB, separate device and initial free space before writing capped generated filler. Source and journal remain on the host filesystem. No existing owner volume is used.

The initial generated test reached actual ENOSPC after 64290816 filler bytes. The production batch completed encoding/verification but failed exclusive publication with No space left on device. This differs from the existing HFS+ encoder failure. The copied encoder-phase assertion failed; all other checks passed, including failed-first/pending-next, absent final outputs, unchanged source/sentinel, no staging, and successful explicit retry after removing only filler. The APFS test now asserts its observed publication boundary; the HFS+ test is unchanged.

The initial error advised a destination supporting hard links for ENOSPC, even though the mounted filesystem supports them. A focused wording repair is within the planned demonstrated publication-defect boundary. The APFS regression requires a free-space remedy and rejects the misleading hard-link advice. No no-overwrite, publication, cleanup or retry policy changes are planned.

Receipts are retained locally in apfs-initial-test.log and subsequent APFS logs. The initial wrapper detached the new image successfully after the failure. No broad APFS/container/quota, network/removable or full-journal guarantee is claimed.

The wording negative control failed both expected remedy checks in 0.326 seconds on actual APFS publication ENOSPC. Publication now distinguishes ENOSPC and asks the user to free destination space or choose another folder, then retry. Existing error handling for collisions and other filesystem failures remains intact.

A subsequent equal-size APFS run failed earlier, at FFmpeg trailer/close with ENOSPC, and therefore failed the provisional publication-only expectation. APFS exhaustion phase is variable. The dedicated APFS contract now admits only the two directly observed ENOSPC boundaries: FFmpeg failure or publication failure. Every outcome still requires Failed/no destination, later Pending, protected bytes, no final files/staging and successful explicit retry; publication failures additionally require the corrected remedy. This is not an arbitrary-error allowance. Existing HFS+ checks and both time limits remain unchanged.

The final opt-in APFS run passed in 0.319 seconds, reaching actual ENOSPC at 64356352 filler bytes and observing FFmpeg trailer/close failure. All protection, cleanup and readable explicit-retry checks passed. Detach succeeded. Native and ordinary regression gates remain pending.

Local full release regression passed 223 tests / 47 suites in 38.472 seconds; the ad-hoc app rebuilt in 16.66 seconds. Hosted run 36825820502 at 6dd21db is pending.

The first native attempt did not reach APFS: its generated source check waited inside Darwin open on the host filesystem. A process sample locates the blocked call in ExportSourceFingerprint.scan. Explicit source review did not release the in-flight call; cancellation remained waiting and normal Quit refused while the operation was active. Source/session/sentinel hashes remained unchanged, both destinations and staging were absent, and the interrupted journal/sample were retained locally. Only the owned generated-test app process was terminated with SIGTERM for a fresh attempt. This is not recorded as ordinary cancellation or an APFS capacity outcome; the underlying native filesystem wait remains unresolved.

## Native failure and recovery

After the recorded restart, explicit Restore previous queue showed Interrupted/Pending and did not execute. Reviewing the generated source before a new start, then reviewing its configured APFS destination, allowed the fresh attempt to reach FFmpeg ENOSPC at trailer/close. Native accessibility text and the screenshot showed Failed for the first job and Pending for the second. Source/session/sentinel hashes matched, final files and owned staging were absent, and the failed capacity journal was retained.

Removing only the verified generated filler and explicitly starting through destination review completed both jobs. Independent ffprobe decoded 48 H.264 frames in each 320 by 192 output, with no audio stream. Matroska duration reported 1.999 seconds for the two-second fixture. An initial scratch check incorrectly demanded textual 2.000 seconds; decoded-frame count and the existing 250 ms production bound supplied the appropriate verification without changing product tolerance. Source/session/sentinel bytes remained unchanged and no staging remained.

The app exited normally after completion. The completed generated journal was retained, the prior recovery file restored byte-for-byte, and the native APFS image detached successfully. Generated outputs remain inside the bounded image for review. This successful fresh attempt does not prove the earlier host-source open wait fixed. Heard VoiceOver, other OS/hardware, existing volumes, quotas and arbitrary filesystem latency remain unqualified.

## Direct publication remedy check

Because real APFS encoding can fail before publication, the same owned full-image fixture additionally attempts at most 1024 generated hard links to its sentinel, stopping at actual publication ENOSPC and removing only successful generated links before the batch. The final run created 43 links before the next publication refused with the corrected free-space remedy; the failed destination was absent. The subsequent real batch also failed publication with the corrected message, retained all safety assertions, then completed explicit retry. The whole opt-in test passed in 0.528 seconds and detached successfully. This directly exercises the repaired product branch, rather than relying on source inspection or an error-string mock.

Final local regression at e5b24ba passed 223 tests / 47 suites in 38.389 seconds. The unchanged opt-in HFS+ contract separately passed in 0.283 seconds with its required actual FFmpeg trailer/close ENOSPC and successful retry; detach succeeded. Hosted final run 36826611045 is pending.

## Hosted timing investigation remains open

Initial hosted run 36825820502 at 6dd21db failed after 548.238 seconds with five existing integration-test timeouts: unknown display aspect, cancelled publication with a competing output, late source progress, matching destination folders (each one minute), and the software anamorphic matrix (two minutes). The destination trace reached the second inspection at 31.397 seconds and was cancelled there at 58.190 seconds of body time; the suite reported 60.466 seconds. This is broader timing debt than the earlier single destination failure, not an APFS opt-in failure. Hosted APFS remains skipped as declared. Final already-dispatched e5b24ba run 36826611045 is pending. No deadline, assertion, scheduling or exclusion was changed. Further performance diagnosis is required if the timing failures recur.

The local full diagnostic debug run also passed all 223 tests / 47 suites in 201.455 seconds with unchanged deadlines. Destination-review body assertions completed in 4.606 seconds. A one-second-scale process sample taken during that run showed the main thread predominantly waiting for events while a cooperative worker computed existing meter fixtures and process-pipe workers were active. It does not establish hosted starvation, a main-actor defect or the cause of the five host timeouts. No DSP, scheduling or timeout changes followed from this observation.

Final hosted run 36826611045 at e5b24ba failed after 507.226 seconds with two issues: destination review exceeded one minute while the last job was Verifying (last phase at 29.505 seconds, cancellation at 58.040 body seconds), and the existing fresh-analysis cancellation test reported 5.852 seconds against its unchanged five-second bound. Audio remains parked; no threshold or scheduling change is made. D-046 records the next bounded observation and keeps Slice 031 acceptance open.
