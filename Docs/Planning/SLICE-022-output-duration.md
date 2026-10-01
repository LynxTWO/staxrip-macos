# StaxRip Mac Slice 022: Bounded output duration verification
Version: 0.1. Date: 2026-09-30. Status: Approved for build under D-035 / R-025.

SLICE STATE
Milestone: Plan committed before investigation and implementation.
Blocked by: None; Slice 021 closed at 3c56caa with hosted run 36801364346.
Evidence so far: BatchController permits max(0.25 seconds, one percent of planned duration); this becomes 72 seconds for a two-hour source. Actual truncated-output reproduction is pending.
Last audit: 2026-09-30.

## 1. What the slice proves

An advanced export with a known planned duration cannot publish a materially shorter or longer container merely because the programme is long. Preserve the existing 250-millisecond absolute allowance, remove percentage growth, and state when source duration is unavailable. This verifies declared container duration, not full decoded content or audiovisual synchronization.

## 2. The walkthrough

Queue a generated multi-minute source, export normally, and read a bounded duration-verification result. A controlled encoder that removes or appends one second must fail verification without publication or advancing later jobs. Retry with the normal encoder succeeds. A generated two-hour low-frame-rate source and a precise trim check the bounded policy at different scales.

## 3. In scope, with build order

M1: Reproduce the percentage-tolerance gap using generated media and real shortened/extended encoded outputs before changing product code. M2: Extract a finite duration comparison with a strict difference below 250 milliseconds for known positive planned durations, explicit unknown-source reporting and actionable mismatch diagnostics. M3: Preserve existing codec/raster/track/HDR/source/staging checks; add unit boundaries, real output refusal/retry, long-duration and trim tests. M4: Regression/build, native ordinary long-duration export and hosted acceptance.

## 4. Out of scope

Decoded frame completeness, packet-level timestamps, per-track duration/alignment, audiovisual synchronization, selected-track planning changes, VFR cadence changes, new trims, audio mastering, native Quick Export, saved schemas, merge and distribution. Broader timing acceptance requires its own evidence.

## 5. Stubs and debts

The expected duration remains the current planned container/trim duration. Metadata can be wrong, and an unchanged declared duration cannot prove intact decoded content. Missing nonpositive source duration remains an explicit unverified result, preserving current supported behavior. Nonfinite duration values refuse. Sources whose ordinary muxing differs by 250 milliseconds or more will fail rather than silently widening the allowance; such cases reopen this policy with evidence.

## 6. Modules touched

New small duration-verification policy, BatchController result verification, generated timing tests and scoped evidence. No encoding argument or data-format changes.

## 7. Data subset

Expected and observed duration in seconds and an ephemeral verification summary. No new persisted fields, source writes or old staging cleanup. The current stage stays unpublished until all verification passes.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S22-001 | Known duration allowance does not grow with programme length; invalid values refuse and unavailable source duration is explicit | Boundary and invalid/unknown tests | duration-policy |
| S22-002 | Real one-second truncation or extension of a multi-minute encode cannot publish or run later jobs; fresh retry succeeds | Generated encoder-wrapper regression and original-policy negative control | duration-refusal |
| S22-003 | Ordinary longer export and precise trim retain their intended measured container duration | Two-hour low-frame-rate fixture, trim and native multi-minute export | duration-compatibility |
| S22-004 | Existing export safety and other verification remain intact | Full local and hosted regression, source/prior-output bytes and stage checks | duration-regression |

## 9. Verification evidence required

A failing pre-change regression establishes the source finding on actual encoded media. After correction, unit tests cover exact quarter-second boundary, nonfinite/missing durations and both mismatch directions. Real refusal/retry leaves source, prior output and unrelated staging untouched. A long positive fixture and precise trim pass. Native queue result displays the bounded duration statement; full local/hosted receipts and planning audit close the slice.

## 10. Guardrails

Do not represent metadata matching as audiovisual synchronization or frame completeness. Do not silently use proportional tolerance or change encoder cadence to make a test pass. Unknown expected duration is explicit. Retain all independent verification, source fingerprint and exclusive publication checks.

## 11. Definition of done

S22-001 through S22-004 have scoped local/native/hosted evidence. Any newly discovered compatibility conflict is recorded and resolved within scope before acceptance.

## 12. What this unlocks

A bounded duration contract and clear foundation for later decoded-timestamp and per-track alignment work.

Approved for build by: Owner autonomous non-audio delegation under D-035 / R-025, 2026-09-30, after Slice 021 closure.
