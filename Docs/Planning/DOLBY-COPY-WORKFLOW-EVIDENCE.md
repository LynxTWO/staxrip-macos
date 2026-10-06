# Generated Dolby-to-HDR10 copy workflow

D179 serves M2's inspect → configure/queue → copy → verify → exclusive publication → usable result consumer. The isolated development app completed that journey on the generated eight-picture 3840×2160 Main 10 source: nominal 24000/1001, P7/L6/CCID6, MEL-style metadata, BT.2020/PQ and CM 2.9. This is encoded HDR10 base-layer copy to MKV, not re-encoding or tone mapping. All five milestones remain open.

## Observable behavior

The user completes source inspection, chooses HDR10 base-layer copy and acknowledges Dolby Vision loss for that source identity. Only original picture settings, MKV, No audio and Remove embedded tracks are admitted. Queue review reports deferred qualification, rather than inventing a completed audit. Execution freshly verifies the source, creates its own staging output, verifies that complete output and publishes exclusively.

The app displayed Completed with eight frames, the actual output SHA256, explicit Dolby/enhancement loss, unchanged static HDR/chroma and no re-encoding. The published file and retained staging file had the same device/inode and SHA256, and the displayed digest matched both. The Reveal button was invoked on this recorded destination. Finder selection confirmation was unavailable: its exact owned read-only query was stopped after no response. Window capture was unavailable; accessibility observations, generated journal, file identities and hashes provide the evidence. No screenshot or native MKV playback claim is made. The owned app was explicitly quit and observed absent.

The normal recovery journal was unchanged before and after. The demonstration used a fresh validated generated journal root. The earlier historical journal mismatch and unknown actor remain recorded; no restoration or history rewrite occurred.

## Admission and verification

The dedicated route preserves the general HDR guard and existing SDR copy contract. Fresh full Dolby inspection requires one RPU per original packet, P7 MEL and CM 2.9 throughout. The native comparator binds every packet to explicit FFprobe PTS/DTS/duration, requires exact hvcC and retained encoded bytes, and refuses output RPU/EL/non-base-layer NALs and Dolby mapping. It preserves in-band parameters. The initial route is single-video-track, no chapters/attachments, SimpleBlock, no reordering, top-left 4:2:0 10-bit, square-pixel 4K with original timing. Other inputs refuse.

Every decoded frame must retain PQ/BT.2020/range/chroma, progressive geometry, mastering display and consistent optional content-light values. Frame presentation order binds to the native packet receipt under the same rational clock. Constant-size per-frame pixel digests compare every decoded base-layer picture. This uses the same installed decoder, not an independent decoder or calibrated display oracle. Actual millisecond timestamps are preserved; nominal 24000/1001 is not an exact per-frame 1001/24000 container clock.

The final checked file worker returns its actual descriptor identity with the content proof. Staging must match that identity before publication. The published path must match it afterward, and a fresh checked full hash/native read must match before Completed. A published but unverified file remains Failed with its destination and publication fact retained.

## Ownership and limits

Checked readers preserve shared uncertainty before parser/cancellation replacement. Checked prelaunch refusals retain the same runner/pipes, and reuse refuses. The existing Batch controller retains its concrete source/parent scopes, descriptors and stage on every failed qualification; there is no automatic retry or release interface. Failed close is not release proof. Both directory close roles are attempted once after known successful verification, consuming before close and capturing status/errno before reports.

This route never recursively deletes staging. Successful verification files remain beside the output, disclosed in Completed. Directory substitution or close uncertainty retains the same controller/resources while preserving any verified published result. Actual generated prepublication replacement, postpublication replacement, after-successful-close report and postpublication directory substitution exercised these distinct outcomes. Replacement and original directories survived; no consumed-descriptor absence probe was used.

Broader process-group/descendant, null/write endpoint, sandbox revocation, recovery, hostile same-user substitution and release trust are not established. Generated EL is a codec fixture, not certified enhancement reconstruction. P8.1 and genuine tone-mapped SDR remain visibly unavailable. ChapterPlan scheduling is unchanged.

## Checks and retained failures

- Focused final logic: 9 tests / 2 suites passed; final diagnostic-wording check: 5 tests / 1 suite passed.
- Ordinary final logic: 691 tests / 110 suites passed in 269.613 seconds, 40 unchanged opt-in skips, no emitted warnings, no ordinary retry. The sole later product change removes incorrect component-level “Nothing published” wording from postpublication-capable checks; final focused checks and optimized build cover it.
- Final optimized build: compiler-reported 30.94 seconds, no warnings; current strict ad-hoc app/read-only-helper signatures and macOS minima 14.0/11.0 passed. Writer/decoder/sample/crop helpers remain absent. Planning audit has no findings; 14-file privacy zero/positive sentinel and protected source metadata/frozen artifacts/current journal comparison passed. These are development checks, not release trust.
- Actual generated native/timing/full-frame/pixel host and real Batch publication passed. Final normal and directory-substitution executions passed after removal of recursive cleanup.
- Source review found and corrected clock/static-metadata binding, repeated parser cancellation, publication identity/result classification and unsafe staging cleanup. It is source-only, not independent execution or a full milestone exit.

Retained failures include an initial new pixel test crash caused by indexing sliced Data from zero, an initial strict stream field-order refusal despite progressive decoded frames, private host configuration/compile corrections and an initial demo process observed absent before interaction. Sliced indexing was fixed and the same test passed. The first demo has no app-behavior claim; a fresh detached owned launch completed the journey. All uncertain/generated roots remain retained.

The predecessor's exact automatic CI run compiled but failed 686 tests with 9 issues. Its historical child, timing, notification and renderer-gate failures remain independent; local passes and this conversion journey do not resolve them. No manual rerun, deadline/assertion change, new skip or global scheduling workaround was used.
