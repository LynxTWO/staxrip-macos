# Queue preflight evidence
Date: 2026-09-30. Scope: Slice 008, D-021. Status: Local automated and native checks passed; hosted check pending.

## Behavior and boundary

Check queue performs a read-only review of at most 1000 uniquely identified jobs. Source regular-file/readability checks, destination entry/parent checks, conservative canonical case-folded destination collisions, configuration and output-name validation precede bounded ffprobe inspection. SDR jobs reuse EncodePlan without executing its arguments. Existing destinations, including dangling links, remain untouched.

Software results say Preliminary check passed and explain that execution independently rechecks. Hardware results require further runtime checks. HDR results validate preliminary settings and stream metadata but explicitly defer full frame/timing audit, tool qualification and track/container checks to execution. Completed entries are skipped and labelled Already completed. No disk-space, hard-link support or future filesystem guarantee is made.

Per-item observations and check time are ephemeral. Queue intent changes invalidate them globally at the app model boundary, even when QueueView is not visible. Tool/encoder changes also invalidate results immediately; snapshots must still match before results display. Cancellation discards results, and generation checks reject late updates. Start queue is disabled while review runs and still performs its existing authoritative checks. Review never updates processing statuses or the recovery journal. The app quit guard includes active review.

Each ffprobe task has a 15-second cancellation deadline; existing process termination and pipe draining settle before it returns. This is not a guarantee about blocked operating-system filesystem calls on unavailable network mounts. Review is qualified for local generated files only.

## Automated receipts

Four focused tests passed in 0.621 seconds. The mixed queue includes a valid item, invalid quality, missing source, existing output, dangling destination link, missing parent, container/extension mismatch and case-colliding outputs. All issues were reported together. Before/after directory listings, source fingerprint, prior output bytes and link destination were unchanged. A sentinel encoder script was never invoked. Duplicate identifiers and more than 1000 jobs were refused.

Synthetic metadata fixtures establish explicit deferred HDR/hardware states and completed-item skipping; these do not claim hardware or HDR execution. A slow probe executable establishes timeout and cancellation, plus invalidation of in-flight intent. No destination or journal is created; existing processing status remains unchanged. Completed reviews reject changed job settings and changed encoder sets.

The release regression reported 107 tests in 19 suites passed in 10.000 seconds, with 14 opt-in skips. Existing audio regressions are unchanged; no new audio listening or mastering acceptance. The final focused rerun passed four tests in 0.623 seconds after tool-change invalidation was strengthened. The optimized ad-hoc app built successfully in 13.27 seconds.

## Native receipt

On macOS 27 / Apple M5, a generated one-second portrait source was queued twice. The second entry deliberately requested an end time beyond the source duration. Check queue reported one preliminary pass and one Needs correction with the trim error. The native editor accepted a keyboard-entered end value of zero. Saving cleared both old review results and check time; rechecking reported two preliminary passes. Per-item results, overall counts and snapshot limitations were present in the accessibility tree and the layout remained usable by scrolling. This is native interaction and AX evidence, not owner VoiceOver listening acceptance.

Before/after SHA-256 checks confirmed source and existing recovery journal bytes were identical. Both intended output paths remained absent; Start queue was never invoked. Local receipts are native-before.json and native-after.json in the queue-preflight scratch directory; personal paths are not committed.

## Remaining validation

Hosted validation remains pending. Owner VoiceOver listening, other OS/CPU platforms, network drives and capacity/resource planning remain outside this local evidence.
