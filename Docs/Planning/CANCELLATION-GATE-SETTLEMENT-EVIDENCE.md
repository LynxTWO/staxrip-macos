# Cancellation gate settlement

D176 fixes the D174 test harness notification failure path. A missing event still fails the original requirement, after cancelling and awaiting the exact owned task. The existing cancellation holder then retains that completed task and its result for review. This includes a returned candidate whose deinitializer would otherwise remove scratch. Failure does not grant fixture cleanup authority.

The gate now has one lock-protected waiting/completed/expired resolution. Live observation, notification and cancellation are authorized only while waiting. Expiry prevents later timer delivery; completion remains authoritative even if the semaphore reports timeout at the boundary. The original 20ms delay, 10s gate escape, under-five-second assertion, cancellation type, source identity, no-publication and scratch assertions remain.

Deterministic tests cover both winner orders, duplicate delivery, failed live observation, and cancellation of a controlled exact task that cannot finish until explicitly released. Weak witnesses verify the same error and holder survive task/holder drops. These tests do not simulate OS close failures, qualify universal descendant settlement, or establish hosted timing results. Existing generated active-work and reported-close tests exercise the unchanged real helper and renderer paths.

Only tests changed. Production cleanup, journal selection, ChapterPlan scheduling, deadlines and all conversion admission gates remain unchanged. All five non-audio milestones remain open.

Focused validation: the initial recovery suite passed four reported tests in 26.417 seconds; its new local weak-variable warning was corrected with typed weak-property witnesses. The strengthened final recovery/settlement selection passed six reported tests across two suites in 30.440 seconds without warnings. Independent review checked the final test source only. The returned-candidate retention case is supported by source lifetime analysis; the deterministic executed retention case carries an error object. Explicit winner orders are not a concurrent stress or real ten-second expiry test.

Full ordinary validation: 678 reported tests across 107 suites passed in 225.650 seconds; 40 opt-in skips, no emitted warnings, no retry. Production files were unchanged, so no new production build or app demonstration was run. Current authorized queue/recovery journal hash matched before and after; the older contradictory comparison remains preserved.
