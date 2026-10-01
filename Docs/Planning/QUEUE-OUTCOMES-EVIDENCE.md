# Queue outcome presentation evidence

Slice 033 under D-059 / R-041 remains in qualification. No production-completion claim.

A read-only adapter derives completed, remaining and needs-attention counts from current job IDs. Orphan records cannot affect the summary. Active work and publication waiting take precedence over earlier outcomes. Empty and unreviewed queues do not claim completion or compatibility. A completed output with the persisted Cleanup warning: marker remains completed and visibly needs attention. The existing controller, journal schema and retry/publication behavior are unchanged.

Rows emphasize the destination name, source and recipe. Routine verification and full paths use native disclosure; active status, failures, cancellation/interruption, preliminary issues and cleanup warnings remain visible. Saved-output Reveal remains available when cleanup warned. Removal still only changes the queued configuration.

Focused state, real cleanup/recovery and preflight checks passed 11 tests / three suites in 16.208 seconds. The real publication-then-cleanup-failure test now also verifies the presentation sees one saved output, one remaining job and one item needing attention, both before and after recovery. Existing output/source/sibling protection, later-job stop and retry assertions remain intact.

The first ad-hoc build passed in 15.82 seconds. Initial native light-mode review showed two readable compact rows where the former completed presentation showed about one and part of another; recovery guidance remained visible. Disclosure exposed both full paths and access-review controls. Inspection found repeated action labels for jobs sharing a source and inherited disclosure hints on child controls. The refinement names each output in action labels, limits disclosure labeling to its label, and gives count summaries static-text semantics. Native qualification and full regression of this refinement remain pending.
