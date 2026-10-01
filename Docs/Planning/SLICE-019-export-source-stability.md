# StaxRip Mac Slice 019: Advanced export source stability
Version: 0.1. Date: 2026-09-30. Status: Active under D-032 / R-022.

SLICE STATE
Milestone: Focused/local/native acceptance passed; hosted gate pending.
Blocked by: Hosted macOS acceptance for 1f552e9, run 36795072130.
Evidence so far: Seven focused functions, negative control, 173 full release tests, native sparse-source progress and verified export; SOURCE-STABILITY-EVIDENCE.md.
Last audit: 2026-09-30.

## 1. What the slice proves

An advanced queue job compares source content fingerprints before inspection and after output verification. If those observed source bytes differ, the candidate cannot publish even if codec, dimensions, duration and track metadata still match.

## 2. The walkthrough

Open a generated stable SDR source and start a queue export. Observe source-content checking and final fingerprint confirmation. In generated integration tests, change the source after inspection or after encoding while preserving metadata; verify refusal, untouched prior outputs, cleaned owned staging and later Pending jobs.

## 3. In scope, with build order

M1: Export-specific regular-file SHA-256 reader with fixed-size chunking, metadata consistency, cooperative cancellation and bounded progress callbacks. M2: Apply source identity checks to every advanced queue export, keeping HDR audits and output verification. M3: Generated mutation/ownership/progress/cancellation cases, native stable export, regression/build and hosted acceptance.

## 4. Out of scope

Source snapshots/copies, guaranteed exclusion of external writers, malicious rewrite-and-restore detection between observations, arbitrary filesystem latency guarantees, native Quick Export, audio/preview reader changes, persistent schema, merge, signing or release.

## 5. Stubs and debts

Full content hashing adds two source reads for ordinary SDR. Slow or blocked filesystem syscalls may delay cancellation until they return; keep UI work off the reader queue and await the actual result. Content identity checks are boundary observations, not a proof that nobody ever changed the file.

## 6. Modules touched

A dedicated export source-identity reader, BatchController progress/checkpoint integration, focused regular-file and generated queue tests, scoped evidence and user-facing documentation. Reuse SourceFingerprint's value type without changing the audio implementation.

## 7. Data subset

Open read-only regular-file descriptor, fixed one-MiB buffer, incremental SHA-256, initial size and stat identity/change fields. Follow ordinary symlinks to regular files; reject directories, FIFO/device inputs and empty files. Do not retain the whole source or write its contents anywhere. Progress is throttled and bound to the active check generation.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S19-001 | Source reader has bounded memory, regular-file checks and consistent content receipts | Known SHA-256, larger fixture, symlink/special-file and mutation tests | source-content-reader |
| S19-002 | Same-metadata content replacement cannot publish | Real encoder/probe mutation cases and prior/later-job checks | source-content-refusal |
| S19-003 | Cancellation and stale progress preserve operation ownership | Deterministic reader interruption and late callback tests | source-content-lifecycle |
| S19-004 | Stable ordinary and HDR exports retain scoped functionality | Native SDR export, existing HDR regression and hosted checks | source-content-export |

## 9. Verification evidence required

Known digest/count, multiple chunks, empty/nonregular/missing input, regular symlink, size/timestamp/path changes during reading, cancellation before and during work, bounded progress, fresh source capture per attempt, actual same-metadata mutation before encode and before publication, later Pending job, prior output/source ownership, stable SDR/HDR regressions, native progress/result and hosted receipts.

## 10. Guardrails

Never publish after a detected source-content change. Keep exclusive no-overwrite publication and current-operation cleanup. Cancellation cannot abandon a live reader. Late hash progress cannot replace encoding, verification or publication state. Do not infer content stability from tags alone or call boundary fingerprints an immutable snapshot.

## 11. Definition of done

S19-001 through S19-004 have scoped local/native/hosted evidence, with I/O overhead and filesystem limitations recorded. Audio listening remains parked.

## 12. What this unlocks

More dependable long queue runs and later explicit input snapshots or persistent source identity policies.

Approved for build by: Owner autonomous non-audio delegation under D-032 / R-022 after Slice 018 closure.
