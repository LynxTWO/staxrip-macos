# Declared display aspect feasibility

2026-09-30. Feasibility conducted while Slice 016 hosted checks ran. The resulting implementation boundary is SLICE-017-display-aspect.md.

FFmpeg's scale filter preserves input display aspect by adjusting output sample aspect ratio. With proportional fit and even rounding, a square source can therefore produce slightly non-square output pixels. A verifier should compare resulting display proportions, not assume output SAR is always 1:1 or identical to the source. Source: https://ffmpeg.org/ffmpeg-filters.html#scale . Current PicturePlan uses force_original_aspect_ratio=decrease and force_divisible_by=2 without reset_sar.

Local FFmpeg 9.0.2 generated a 722x480 source with SAR 32:27. Twelve software exports (H.264, HEVC, AV1; MKV and MP4; full frame or 16 horizontal/10 vertical pixels cropped before 1280x720 fit) preserved exact rational DAR. Cropped output raster was 1082x720 with SAR 90368:76281 and DAR 11296:6345. Full frame outputs had SAR 2888:2439. Independent frame reports for each of the six cropped outputs agreed with its stream SAR throughout the six-frame fixture.

A separate generated re-encode kept the 1082x720 raster but set SAR 1:1. Its DAR changed to 541:360. Existing raster-only verification cannot distinguish these two outcomes. Original sources and successful fixtures were not overwritten.

A generated H.264/MKV with setsar=0 omitted SAR and DAR entirely from ffprobe stream metadata. Treating absence as 1:1 would invent information. Proposed bounded contract: verify declared positive rational pixel shape when available; clearly report unavailable display verification for genuinely unknown source SAR while preserving existing export behavior. Refuse malformed non-unknown ratios and mismatch/missing output SAR when a source contract exists. Do not claim per-frame constancy, pixel-content equivalence, typography, viewer behavior or missing-metadata inference.

Exact arithmetic is feasible without floating tolerances: SAR terms bounded to positive Int32, raster terms within the existing positive Int32 bound, each numerator/denominator product fits Int64. Reduce each fraction by GCD and compare reduced values without cross-multiplication. The expected display ratio is upright cropped width times source SAR numerator divided by upright cropped height times source SAR denominator. Existing rotation restrictions already require square pixels for nonzero transforms. Static HDR already has its stronger square-pixel frame contract.

Generated evidence: spike.py, spike.json, frame-ratios.json, wrong-shape.json, unknown-sar.json in this ignored folder. This is feasibility on one machine/tool version, not a compatibility matrix.
