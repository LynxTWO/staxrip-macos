# Source orientation evidence
Date: 2026-09-30. Scope: proposed Slice 007, D-020. Status: feasibility evidence only; application integration not yet built.

## Research and bounded feasibility checks

FFmpeg documents display_rotation as counter-clockwise degrees and notes that autorotation is enabled by default. An explicit input display_rotation overrides file metadata. See [FFmpeg video options](https://ffmpeg.org/ffmpeg.html#Video-Options). The typed implementation will disable implicit autorotation, override the input display matrix to identity, and apply the validated pixel transform before crop. This makes the selected video stream's geometry explicit for both preview and queue.

On FFmpeg 9.0.2, a generated 160 by 96 asymmetric test pattern was encoded to H.264 with explicit SDR BT.709 metadata, then copied into four MP4 fixtures with 0/90/180/270-degree display rotations. Explicit no-op, counter-clockwise transpose, horizontal-plus-vertical flip, and clockwise transpose respectively produced the same first-frame YUV420 bytes as FFmpeg autorotation. Separately, an independent array permutation of every Y, U and V pixel matched all four explicit-filter frames byte for byte. The permutation did not invoke FFmpeg's orientation machinery.

Eight scratch exports, one for each angle/container pair (MP4 and MKV), used explicit transforms followed by asymmetric crop. Each output had the expected 152 by 92 or 88 by 156 dimensions and no display matrix. These are feasibility observations, not yet production-path tests. Source fixtures and JSON receipts stay in local scratch. No private media was used.

## Planned implementation acceptance

Require exact orthogonal fixed-point matrices with no reflection, scaling, translation or perspective. Verify reported angle and legacy tag agreement. Nonzero orientation supports progressive, square-pixel 8-bit SDR only, with deinterlacing Off. Queue and still preview will share this interpretation; output verification will reject a leftover transform before publication. HDR remains under its strict no-rotation contract.

Record focused unit/integration, native and hosted receipts here after they execute. Real-camera corpus, dynamic per-frame transforms, rotated HDR, arbitrary/mirrored orientation and other platforms remain unverified or unsupported.
