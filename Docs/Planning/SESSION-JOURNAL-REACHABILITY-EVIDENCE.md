# Saved-session journal reachability evidence

D171 records a read-only M5 protection prerequisite for the existing M1 companion preservation consumer. The saved-session journal differed from the prior D169 observation during D170 verification. The writer remains unknown, the protection gate remains false, and the current journal has not been restored, overwritten or accepted as a new passing baseline. The owner clarification remains pending.

## Source findings

Verified source facts: BatchJournal.defaultURL computes the default saved-session location; StaxRipMacApp supplies it to its BatchController. BatchController's initializer defaults journalURL to nil. Its start and subsequent queue transitions checkpoint when a journal URL is supplied. Startup discovery, queue restoration and reset do not persist a journal in the inspected paths. The concrete queue-start entrance is QueueView through WorkspaceModel to BatchController.start.

The review enumerated 232 tracked source, test, script, tool, package and CI text candidates. Literal BatchJournal.defaultURL has one matched source line, in StaxRipMacApp.swift; last-batch.json has one, in BatchJournal.swift. Those known-positive matches qualify the search. No StaxRipMacApp constructor match was found. These are literal source findings, not universal runtime absence proofs.

The existing Archive.execute -> DiskCheck -> metadata-reader companion path has no journal or app dependency in the inspected call graph. Explicit journaling tests select generated temporary URLs. The static native host excludes the app entry point and uses its own main. The inspected generated SwiftPM runner also has a separate test entry, but its artifact identity is not bound to the prior D170 execution. Build and package scripts do not launch the app in the inspected paths.

An app process start observation precedes the journal modification observation. Neither source searches nor timestamp order identifies the writer or binds that running binary to the journal change. Owner media bodies, queue/session payloads and app UI were not inspected or changed. Current journal hash equality with the D170 observation does not resolve its difference from D169.

## Hosted failure inventory

Parent PR143, original D169 head 0a2621c5898fdd763f3f85721b7bab492d18fa4f, automatic run 37368103119 attempt 1/job 111958125131 compiled and failed: 658 reported tests in 768.740 seconds, 33 issues. Shared fixture preparation passed in 48 seconds; preview was skipped. The full log and categorical records are retained privately without rerun.

There were zero 60-second, 21 unchanged 120-second and six 180-second bounds. Six other issues comprise one sample child assertion, two crop close/child assertions, the existing HDR10 cancellation bound at 5.142782926559448 versus less than five seconds, and Fresh-analysis/Rendering notification EOF expectations.

All 37 decoder records are present: five qualification records and 32 historical calls. Sample EOF-live-child and crop complete-live-child refused at the sourceHash deadline before spawn or callbacks. Thirty other historical calls launched in this run. Passing calls do not resolve older invocation causes or prove universal process-group settlement. Both EOF records reached matched=true, ready and candidateReturned without notification, preserving the previously established harness contract gap. AV1/TenBit chapter worker entry, write return and caller resume occurred after the bounds; this does not prove a write-body stall or a shared starvation mechanism. Observer timing limits remain.

The original D170 PR144 automatic run remains in progress at this review snapshot. No final result is inferred. Earlier compiler, runner-acquisition and runtime failures remain separate; local passes do not resolve them.

## Checks and limits

No new local test, build, fixture, runtime, UI or signing execution occurred for D171. Product, tests and build inputs remain byte-identical to D170. Its actual 663-test/105-suite/218.402-second ordinary pass, 40 unchanged opt-in skips, no emitted warnings and 24.89-second optimized build are reused as prior receipts, not new measurements. Documentation checks are recorded separately.

The audit narrows the selected companion source closure for independent generated work. It does not clear the journal protection gate, establish an actor, qualify arbitrary runtime paths or complete M1-M5. The next Directory successful-terminal-close candidate remains selected only: required helper settlement and final checks must precede any future receipt/commit, and earlier uncertain Directory owners must receive no new close attempt. Native choice/controller/result, trusted non-DEBUG helper, recovery, sandbox, resource retirement, edited HDR, enhancement reconstruction and production acceptance remain open. Historical timing, scheduling, assertions and deadlines are unchanged; timer/queue repair proposals still require their pending human decisions.
