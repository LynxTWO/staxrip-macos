# StaxRip Mac Slice 031: APFS full-destination qualification
Version: 0.1. Date: 2026-10-01. Status: Approved for build under D-045 / D-046 / D-047 / D-048 / D-049 / D-050 / D-051 / D-052 / R-035 / R-036 / R-037.

SLICE STATE
Milestone: Local/native capacity qualification complete. Recurrent existing hosted timing failures require bounded runtime observation under D-046.
Blocked by: None.
Evidence so far: APFS-CAPACITY-EVIDENCE.md records actual ENOSPC, protected bytes, native retry and detach, including an unrelated source-open interruption.
Last audit: 2026-10-01.

## 1. What the slice proves

The production queue handles a full disposable APFS destination without publishing a partial output, changing the source or continuing later jobs. Explicit retry after reclaiming only generated fixture space succeeds.

## 2. The walkthrough

Create a new bounded APFS image with unique fixture identity. Fill only its owned directory, confirm actual ENOSPC, then queue generated video to it. Observe the failure and absence of final files. Remove only generated filler and retry explicitly. Inspect the completed output, preserve the previous recovery journal and detach the fixture.

## 3. In scope, with build order

M1: Owned APFS fixture helper and filesystem/device/marker validation. M2: Actual production batch failure/retry with source, prior-output, staging and later-job assertions. Reuse the existing strict capacity test where its phase matches; otherwise add a separately scoped APFS test while retaining HFS+ assertions unchanged. M3: Native failure/retry, ordinary regression/hosted check and detached-fixture evidence. D-046 adds bounded read-only observation of the unchanged hosted command after two failed runs. D-047 adds a separately reported focused hosted comparison before the unchanged full gate. Focused success never substitutes for full acceptance. D-048 adds bounded existing status detail/progress/publication tracing to the generated destination test to discriminate its stalled boundary. D-049 adds a bounded test-only forwarding observation around the real source reader. D-050 adds preservation of requested source-check worker priority under R-036, with a pre-repair real-worker counterexample and full/native regression evidence. D-051 adds debug-only actual reader body/submission/worker observation to correct the forwarding-entry ambiguity. D-052 adds a per-read owned source queue with actual bounded contention negative/positive evidence. Other product repairs remain outside this boundary.

## 4. Out of scope

Network or physical removable devices, existing owner volumes, shared-container quotas, snapshots, full source/journal volumes, generalized capacity prediction, new audio behavior, process crashes, merges and distribution.

## 5. Stubs and debts

A disposable local APFS image is scoped evidence, not a guarantee for all storage devices or APFS configurations. Hosted ordinary checks do not claim disk-image qualification. The existing HFS+ evidence remains separate and intact.

## 6. Modules touched

Owned fixture script, opt-in capacity tests as needed and evidence documentation. Production publication wording and ExportSourceFingerprint worker-priority mapping within demonstrated scope; source checks and cancellation assertions remain authoritative.

## 7. Data subset

Generated short H.264 video, sentinel output and filler only. A new fixed 64 MiB APFS image, at most 64 MiB filler, separate mount device, expected filesystem and exact unique marker. Generated source and test recovery journal stay on the ordinary workspace filesystem. Native testing backs up and restores the preexisting recovery file after app exit.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S31-001 | The target is a bounded newly owned APFS image, never an arbitrary existing volume | Device/filesystem/marker/capacity receipts and fixture wrapper | apfs-ownership |
| S31-002 | Actual ENOSPC produces failed first job, absent final output and later pending jobs | Real batch plus native failure | apfs-failure |
| S31-003 | Source and prior output bytes survive; cleanup affects only current owned staging | Independent hashes and directory/journal checks | apfs-protection |
| S31-004 | Explicit retry completes after removing only generated filler | Actual readable output and native retry | apfs-retry |
| S31-005 | Fixture detaches; existing regression behavior remains | Detach receipt, local/hosted suite and unchanged HFS+ contract | apfs-regression |
| S31-006 | The source-check bridge honors foreground task priority while reading off main and preserving source/cancellation contracts | Real worker QoS negative/positive checks, unchanged source tests, full suites and native export | source-worker-priority |

| S31-007 | Source scan submission avoids the demonstrated shared-worker contention while retaining priority and ownership | Actual bounded contention negative/positive control and full regression | source-worker-contention |

## 9. Verification evidence required

Record exact filesystem/device/capacity, actual write/fsync ENOSPC, app failure phase and error, source/sentinel hashes, final-file absence, next-job status, cleanup and readable retry output. Record an admission-stage failure honestly if APFS metadata exhaustion precedes FFmpeg; do not relabel it as active-encoding failure. If required, a separately documented small preallocated reservation can be released before execution to exercise actual encoder failure without altering bounds or existing HFS+ expectations.

## 10. Guardrails

No existing disk is erased, reformatted or filled. Validate mount identity before filler writes; cap all writes. Never enlarge the fixture to make a failure disappear. Detach failure retains the fixture and reports its location; it must not trigger deletion of mounted contents. No weakened assertions, timing thresholds, scheduling changes or ordinary-test exclusions to force acceptance. The D-046 observer does not dump environment variables, arguments or arbitrary process state and preserves the test command exit status.

## 11. Definition of done

All seven criteria have scoped local/native evidence and ordinary hosted acceptance, the fixture is detached, and the release ledger states remaining storage limitations.

## 12. What this unlocks

A second filesystem qualification for the default Mac storage family and a reusable bounded fixture for separately scoped future failure tests.

Approved for build by: Owner overnight autonomous non-audio delegation, 2026-10-01; D-045 / D-046 / D-047 / D-048 / D-049 / D-050 / D-051 / D-052 / R-035 / R-036 / R-037.
