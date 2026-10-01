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
