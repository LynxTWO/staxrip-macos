# Declared display proportion evidence

Date: 2026-09-30. Slice 017, D-030 / R-020. Status: local and native acceptance passed; hosted pending.

## Contract

Advanced queue plans derive a reduced display fraction from the upright cropped raster and declared source pixel ratio. Bounded positive Int32 values multiply safely within Int64; GCD reduction avoids cross-multiplying already large products. Output stream geometry must match before publication. Missing or malformed output pixel shape cannot satisfy a known source contract. Missing source SAR, N/A and 0:1 remain explicitly unverified, with no square-pixel inference. Other malformed source/output ratios are refused.

No filters, saved schema or settings changed. Existing raster, codec, duration, routing, HDR, chapter, attachment and external-caption verification remains. The Picture pane explains raster versus display proportions; queue preflight and completion expose the contract. The check covers reported stream metadata, not decoded picture equivalence, codec-header agreement, per-frame constancy or every player's presentation.

## Automated checks

Eight new test functions in two suites cover rational reduction, invalid/missing metadata, positive Int32 boundaries, products near Int64 limits, pathological text, upright crop, unchanged filter arguments, unknown source behavior and real publication. Twelve generated exports cover H.264, HEVC and AV1 in MKV/MP4 with full and cropped anamorphic pictures. Independent output probes require specific raster dimensions and SAR values, not merely reuse the implementation's comparison.

Two real encoder wrappers append setsar=1 or setsar=0 after the intended crop/resize. Both retain the correct 1082x720 raster but fail display verification; neither output publishes, the following job stays Pending, source/prior bytes and unrelated staging stay intact, and owned staging is removed. A real unknown-SAR source exports successfully with an explicit unverified result.

The initial 156-test regression exposed the existing near-square MKV precision loss documented in DISPLAY-ASPECT-RESEARCH.md. The same crop remains a successful raster/display test in MP4. A separate real MKV test requires either exact preservation if the tool improves or a truthful refusal when metadata differs. It never marks an approximation exact. The final optimized regression passed 157 tests in 31 suites in 36.308 seconds; 15 opt-in tests skipped. The preview build passed in 13.60 seconds with its local ad-hoc signature.

## Native walkthrough

macOS 27.0.1 / Apple M5, FFmpeg 9.0.2. A generated version 6 session restored two Ready jobs without execution. The anamorphic fixture's inspector reported 722x480, SAR 32:27 and DAR 722:405. The Picture pane showed crop top 4, bottom 6, left 6, right 10, 1280x720 fit and the new verification explanation in the accessibility tree.

Source and destination locations were selected explicitly using native pickers. The initial restored-source inspection waited for access; one preflight reported its existing source-inspection deadline. Review source access and retry resolved it without rewriting the queued path. This is the known restored-path permission boundary, not a durable-bookmark fix.

Read-only preflight showed the known job's expected 11296:6345 display ratio and the second job's unavailable source pixel shape. Outputs were absent before execution. Both jobs then completed: the known source reported verified raster 1082x720 and verified display proportions 11296:6345; the unknown source reported verified raster 1206x720 and display proportions unverified. Independent ffprobe confirmed the first output SAR 90368:76281 and DAR 11296:6345; the second output had no reported SAR/DAR. Both source hashes stayed unchanged and no owned staging remained.

Generated fixtures and logs remain in ignored local work/display-aspect. No user media or absolute local paths are committed.

## Limits and remaining gate

Hosted macOS regression remains required. Strict equality can refuse small encoder/container approximations; the failure message explains possible rounding and suggests trying another container or Original size. Hardware, other tool versions, frame-varying metadata, codec/container disagreement, long films and broad player compatibility remain separate qualification. Audio listening stays parked. No merge, signing, notarization or public release is included.
