# StaxRip Mac Slice 012: Full destination failure qualification
Version: 0.1. Date: 2026-09-30. Status: Complete within recorded limits.

SLICE STATE
Milestone: M1 through M3 local/native checks passed; corrected ordinary hosted regression passed at a995ab3.
Blocked by: None external.
Evidence so far: DESTINATION-CAPACITY-EVIDENCE.md records real ENOSPC, no publication, cleanup, protected bytes and successful explicit retry on the bounded HFS+ image.
Last audit: 2026-09-30.

## 1. What the slice proves

A generated queue encode into a deliberately full disposable filesystem fails without publishing a partial result, stops later jobs, and preserves source and existing output bytes. This is bounded local filesystem evidence, not a capacity estimate or network-disk guarantee.

## 2. The walkthrough

Create and attach a uniquely named small disk image, populate only that image with generated files to exhaust space, and queue generated video to it. Observe failure, unchanged source/prior output, absent final file and owned staging cleanup. Free only the generated filler and retry explicitly to prove recovery. Detach the owned test mount afterward.

## 3. In scope, with build order

M1: Bounded disk-image feasibility and fixture ownership. M2: Opt-in integration test of actual full-destination failure and retry using the production BatchController. M3: Native generated failure/result check and record filesystem, capacity, error, cleanup and recovery receipts. Only fix production code if evidence demonstrates a defect within this failure boundary.

## 4. Out of scope

Audio acceptance, existing disk cleanup, capacity estimates, stale staging recovery, physical removable/network media, process crash simulation, signing, merging or releases.

## 5. Stubs and debts

Hosted runners need not attach disk images. Keep the destructive-capacity test opt-in and require a dedicated test mount with an ownership marker. The ordinary regression must remain portable. A single local filesystem does not qualify every supported destination.

## 6. Modules touched

Targeted BatchController integration test, local fixture utility if needed, and evidence documentation. Production publication and cleanup are expected to remain unchanged.

## 7. Data subset

Generated source and sentinel only. A fixed 64 MiB image in ignored work storage with a unique volume name; filling must be guarded by mount identity and marker. No writes to arbitrary existing volumes. Journal remains on the ordinary workspace filesystem.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S12-001 | Actual space exhaustion produces failure, no published output and stops later jobs | Generated real queue test | capacity-failure |
| S12-002 | Source and existing output remain unchanged; only current owned staging is removed | Hash and directory checks | capacity-ownership |
| S12-003 | Explicit retry after reclaiming generated fixture space succeeds | Real queue retry | capacity-retry |
| S12-004 | Native failure is understandable and does not claim completion | Native queue walkthrough | capacity-ui |

## 9. Verification evidence required

Exact image type and size, actual ENOSPC evidence, focused opt-in test, ordinary regression if code/tests change, native result and hosted status. Detach the image and retain only bounded receipts.

## 10. Guardrails

Never fill the main drive or a user-selected existing disk. Verify dedicated mount and ownership marker before filler writes. Bound total filler to 64 MiB. Do not delete owner files or change system storage settings. If disk-image mounting is unavailable, record the blocker rather than simulate an actual filesystem result.

## 11. Definition of done

S12-001 through S12-004 have evidence, fixture mount is detached and limits recorded. No broad disk-full or production-completion claim.

## 12. What this unlocks

Future removable/network and interrupted-writer qualification can reuse the ownership assertions with separately approved fixtures.

Approved for build by: Owner autonomous non-audio delegation; D-025 after Slice 011 native and hosted closure.
