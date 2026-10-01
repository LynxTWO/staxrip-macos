# Caption cancellation entry: owner decision packet
Date: 2026-10-01. Status: Owner approved under D-074; implemented and qualified at 2f8cea7, hosted run 36893266046.

## Need and authority

Need: cancelling an active caption verification must stop and join its child process, prevent publication and later jobs, preserve originals, and clean up only owned staging.

Authority: Slice 038 S38-004 and D-068; owner autonomous non-audio completion delegation. D-071 through D-073 additionally retained a ten-second batch-start-to-second-verifier entry guard during diagnosis. No product requirement promises that complete preparation and encoding always finish in ten seconds under arbitrary competing load.

Worst case: publishing unverified media, continuing later jobs after cancellation, or deleting staging while a child is still using it. Consequence class: user_data, because the actual BatchController publishes user outputs and owns their temporary files. The separate fixed startup timing assertion characterizes a disposable generated test under full-suite contention; it does not itself prove these data guarantees.

## Existing control and gap

The existing two-minute Swift Testing limit, actual subprocess entry marker, real BatchController cancellation, child-PID exit check, output absence, next-Pending check, original-byte comparisons and staging check directly cover the intended lifecycle. The added ten-second aggregate startup guard expires before cancellation reaches the intended second verifier on the three-core hosted runner. Local runs and same-runner focused checks reach and exercise that verifier. These passes do not supersede ordinary hosted failure.

## Attempts and measured evidence

Four hosted verifier-entry failures occurred from 14:14 to 15:08 UTC (about 54 minutes elapsed including diagnosis). A preceding hosted compilation failure was separately repaired; it was not a fifth verifier-entry failure.

| Run | Head | Ordinary outcome |
| --- | --- | --- |
| 36874754310 | c386a77 | 263 tests, one entry failure, 510.084 seconds |
| 36876558655 | ae4f68b | 263 tests, same failure, 426.435 seconds; focused case 0.313 seconds passed |
| 36878448882 | 6c471b7 | 265 tests, same failure, 549.259 seconds |
| 36880463923 | 37726d5 | 265 tests, same failure, 517.715 seconds; focused case 0.387 seconds passed |

At 37726d5, fixture creation took 11.040 seconds, outside the guard. Batch start was 11.041; its task resumed at 13.034; source fingerprint returned at 14.275; probe at 15.610; caption capture at 16.422; snapshots at 16.810; titles at 16.846; encode at 18.651; output probe at 20.508. The first caption verifier started at 20.740. The guard cancelled at 21.244 and settlement finished at 21.771. Snapshot workers entered promptly and finished before their awaits resumed. This trace shows distributed preparation/execution latency; it does not establish another single stuck worker or prove that unrelated UI-actor tests caused the remaining delay.

The D-072 writer repair has separate bounded before/after dispatch evidence and remains. Plain 6c471b7 local regression passed 265 tests in 212.180 seconds; optimized/native independent output checks passed. Instrumented local 37726d5 passed 265 tests in 204.942 seconds. Temporary D-073 observers and workflow diagnosis are now restored exactly to 6c471b7. No new passing hosted result is claimed.

## Approved and qualified decision

Recommend making this a cancellation-lifecycle test with explicit phase budgets, rather than a ten-second total-throughput test:

1. Preserve the two-minute whole-case limit, complete generated source/caption fixtures, ordinary parallel scheduling and all existing PID/output/next-job/original/staging assertions.
2. Bound preparation to 90 seconds and require actual first-verifier child entry. Early batch failure, absent entry or preparation expiry fails; it does not skip or pass the test.
3. Preserve a ten-second entry limit from that first-verifier marker to the actual second-verifier PID marker.
4. Cancel only after second-verifier entry; add an explicit ten-second cancellation-settlement requirement. Always join the owned batch/tool before cleanup, including timeout and assertion-failure paths.
5. Keep the existing fixed one-second snapshot-worker contention regression and unchanged broad export/corruption cases. Add a deliberately stalled pre-verifier negative to show that preparation timeout fails without publication, and a second-verifier cancellation negative/positive ownership check. Run the ordinary complete local/hosted command before acceptance.

This deliberately replaces the old aggregate ten-second startup assertion; it is a proposed acceptance-contract change, not a passing result or an assertion that the original guard was met. It does not increase the whole-test deadline, reduce fixture content, serialize/exclude suites or alter production scheduling. A different choice is to retain the aggregate ten-second bound and explicitly fund further controlled performance diagnosis; there is not yet evidence for another production repair.

## Owner approval

The owner approved the recommended phase-specific approach in chat on 2026-10-01: "yep, i approve that approach". D-074 records exact execution and negative-test bounds. The previous failed runs remain evidence; approval does not turn them into passes.

No merge, release, audio listening or next product slice is authorized by this packet. The full-film qualification proposal remains inactive. The checkpoint intentionally avoids another unchanged hosted attempt; failed receipts remain authoritative.

Closure: ordinary local 266 tests passed in 206.456 seconds; hosted 36893266046 passed 266 tests in 513.644 seconds. MULTIPLE-CAPTIONS-EVIDENCE.md preserves the complete scoped result and prior failures.
