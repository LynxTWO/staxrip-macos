# Retention tests preserve weak ownership on the hosted compiler

D163 corrects an actual M5 compile failure in the M1 writer-pin acceptance tests. PR137
run 37343500814, attempt one, job 111876189068, exact D162 head
b58551e670b646c6b1f83524f6bb26ee8873b3bf stopped before Swift tests ran. The hosted
Swift 6.1.2 compiler rejected THREE new `weak let` locals: one writer-pin witness and
two archive pin/stage witnesses. Repeated diagnostics are not additional source sites.
Local Swift 6.4 accepted these declarations; that local check was insufficient for the
hosted compiler. Full failed-step and full-job logs are retained privately without rerun.
Shared native generated fixture preparation passed in that run. No test/suite/skip/pass
counts or absence of older test failures are inferred from compilation stopping.

The correction uses two explicitly typed private test witness classes, with THREE
mutable `weak var` properties. The witness cannot retain the concrete pins, stage,
returned error or completed Task. Nothing resets those properties to manufacture
owner disappearance: ARC alone updates them. Every original identity/lifetime/FD-field
assertion remains; Task/error drop precedes witness construction, and the same expiry
and independent registry/Access release sequence follows. No new tests or helper trials,
product code, callbacks, timing observer, timer, deadline, fixture, case order, skip,
worker, scheduling or cleanup policy changed. The existing five generated tests retain
34 writer direct joins and their original bounded acceptance, not a new qualification.
Independent source review confirmed this scope and corrected one premature comment
claim before ordinary execution. Actual compatibility requires corrected-head hosted
compilation; neither source review nor local pass establishes that result.

All 98 selected product/build files are byte-identical to D162. The actual D162 optimized
22.47-second build is reused; no new production compilation. Current strict ad-hoc app
and read-only helper signatures/minima are checked separately. No release writer,
decoder/sample/crop packaging, Developer-ID loading, clean-machine or native UI admission.
The static exact 94-product-source host retains its prior preservation/review scope.
D162 production pin settlement, concrete retention and source/pipe/process priority
are unchanged. Constructor/partial admission/pre-spawn/fallback/deinit/metadata-disk,
alias/identity-equivalent/concurrent direct admission, sandbox/recovery and native
choice/result/trusted-helper gates remain open. Fake scopes/controlled-after-close or
after-eligible-body reports do not prove spontaneous OS or failed-group faults. DEBUG
isolation is not production recovery or cleanup authority.

The existing draft PR137 is updated, retaining its failed original head/run. The next
automatic run is for changed code; no failed run is manually retried. Older exact-head
hosted timeout, child-launch, pipe-holder and mastering failures remain independently
retained. No blanket common-cause/starvation inference, scheduling/deadline/assertion/skip
workaround or live-work gate/timer-arm/ToolRunner-close implementation follows. Those
specific proposals still require actual human question/answer evidence. All M1–M5 remain
open. No owner media body/full-source repeat/audio listening/runtime build-copy/C/sanitizer/
pixel oracle/APFS/power/signing-loading retry/LV bypass/UI/release/merge qualification.

Actual focus/ordinary/current signature/protection/planning receipts follow below.


Actual local focus5tests/2suites3.163s PASSED/no warnings. Existing
five cases/34writer direct joins; no new tests/helper trials. Ordinary631tests/105suites
220.498s PASSED with0issues/40UNCHANGED explicit opt-in skips/0emitted warnings,
full log retained/no retry. Actual D162optimized22.47s reused/all98product-build files byte-identical;
CURRENT strict ad-hoc app/read-only helper/minima14.0/11.0 pass, writer/decoder/sample/crop
absent. Five-file privacy zero/positive sentinel/protected owner metadata-journal-original-
frozen-D130/D142/D143 unchanged/planning empty. Source-only finite review/no independent
execution/full milestone exit. Hosted compilation outcome remains a separate actual gate.
