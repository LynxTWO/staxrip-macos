# SignalForge reuse assessment
Version: 0.1 Draft. Date: 2026-09-28.

Owner requested investigation of SignalForge to avoid duplicating existing work. Read-only source assessment at revision 93d82e2796ac4c148033fc45dc067af1746b3b29. No source, fixture or dependency was copied into this public repository. Source reference: https://github.com/LynxTWO/SignalForge (access may require authorization).

## What exists

Inspected `crates/signalforge-analysis/src/lib.rs`, workspace and analysis Cargo manifests, Cargo.lock, the loudness manual, AGENTS.md and license declarations. Source facts, not new test results:

| Candidate | Evidence in lib.rs | Use here |
| --- | --- | --- |
| K-weighting and gated integrated energy | Bs1770IntegratedAccumulator, bs1770_integrated_lufs_from_block_mean_squares | Reuse numerical design and boundary tests |
| Continuous measurement | ProgrammeSequenceLoudnessMeter | Streaming adapter candidate; preserves state between chunks |
| True-peak estimation | Bs1770TruePeakEnvelopeStream and direct peak routines | Candidate for streaming peak analysis and later limiter verification |
| Full measurement | EbuR128LoudnessMeter using ebur128-stream | Existing integrated/LRA and trace path to compare |
| Conformance cases | official_ebu_test_set_core_cases_match_expected_values | Reuse expected-case inventory after verifying original standard and fixture rights |
| Boundary regressions | Sequence versus concatenated buffer, parallel versus sequential peak, cancellation and nonfinite input tests | Carry equivalent tests into the chosen integration |

Workspace declares MIT OR Apache-2.0; MIT notice names Daniel Boyd. Cargo.lock pins ebur128-stream 0.2.0. These are useful starting facts, not a completed dependency-license audit. Preserve notices for any copied or adapted code and review the chosen dependency closure before publication.

## Limits that change the plan

- Standard-rate sequence measurement uses ebur128-stream; its custom accumulator is a fallback for unsupported rates. Calling the whole path an original meter would be inaccurate.
- Sequence finalization returns no LRA or momentary/short-term trajectory. The full-buffer path has more features but is not yet evidence of bounded full-film memory use.
- Several paths use -120 LUFS for unavailable integrated loudness, or fall back to sample peak. Adaptation must preserve unavailable states and identify the peak method, instead of presenting a sentinel or fallback as a measured result.
- Channel layout is inferred from channel count in these paths. Film layouts must come from explicit stream metadata and validated mapping before surround support.
- The official EBU test exits successfully after printing a skip when fixtures are absent. Our conformance gate must require the fixture manifest and fail or report an explicit unmet gate when absent.
- Approximate analysis helpers and music vocal-presence heuristics do not establish movie dialogue detection accuracy.
- A comparison between two wrappers using the same underlying library is not independent numerical validation. Record backend identities and retain an external implementation plus official known-answer fixtures.

## Proposed bounded decision, D-010

M1 compares two narrow candidates: a licensed Swift adaptation of the meter components, or a small Rust library with a C ABI and Swift wrapper. Keep the SwiftUI application. Do not embed the SignalForge UI, library database, music reference matching or whole CLI.

First inspect the minimal transitive dependency closure and numerical conventions. After slice approval, run generated mono/stereo and available official fixtures against the candidate, compare to FFmpeg's ebur128 path, profile streaming memory/cancellation, and verify build/packaging on macOS. Limit this investigation to one working day before returning a decision with evidence. If neither candidate meets the brief, revise the slice; do not silently replace reuse with a whole new DSP engine.

Preference: reuse verified algorithms and test cases first. Choose the bridge only if its build, ABI ownership, cancellation and distribution cost is lower than maintaining a port. Any port needs fresh numerical validation. No superiority or conformance claim transfers from the source repository's documentation.

## Evidence boundary

Verified: source structures and tests listed above exist at the pinned revision. Inferred: they can reduce implementation work. Unknown: current tests pass on this Mac, complete conformance, full-film throughput, dependency closure license compatibility and comparative listening quality. No SignalForge build or DSP test was run in this planning turn.
