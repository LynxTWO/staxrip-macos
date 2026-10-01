# Ten-bit SDR video-copy evidence
Date: 2026-10-01. Status: M1 feasibility passed; no product acceptance yet.

## Need and scope

Slice 040 / D-078 / R-050 adds one declared ten-bit SDR HEVC format through the existing user_data export path. The existing packet/configuration/metadata comparison is the control to reuse; both VideoCopyContract and EncodePlan currently refuse the higher-bit-depth input. No standalone copy engine, schema, DSP or new broad color guarantee is planned.

## M1 generated feasibility

Read-only installed FFmpeg 9.0.2 encoder help lists yuv420p10le. [FFmpeg streamcopy](https://ffmpeg.org/ffmpeg.html#Streamcopy) transfers encoded packets directly but still depends on source/target container requirements. [x265 VUI options](https://x265.readthedocs.io/en/master/cli.html#vui-video-usability-information-options) supply explicit color declarations. These references inform the experiment and do not prove application support.

The first generated ten-bit gradient used only FFmpeg output color flags and did not yield primaries or transfer fields in the actual probed source. M1 correctly refused that incomplete fixture before any application changes. The corrected fixture explicitly sets x265 colorprim=bt709, transfer=bt709, colormatrix=bt709 and range=limited, following the existing HDR fixture's explicit-VUI pattern without enabling HDR. This is a fixture correction, not relaxed admission.

A generated 160 by 96, 24 fps, three-second HEVC Main 10 yuv420p10le gradient has the required progressive/square-pixel/zero-start and bt709/tv fields. Its first decoded frame contains 17,374 samples with nonzero low-order two bits out of 23,040 samples. The references explicitly decode to yuv420p10le. All four MP4/Matroska source-to-MP4/MKV combinations completed using the existing copy argument shape and metadata flags. Each retained 72 frames, 72 packets, identical packet sizes/hashes, matching codec configuration and declared pixel/profile/color fields, and the same complete decoded-picture digest. Maximum per-frame timestamp differences were zero, except MP4 to MKV at 0.000333 seconds. All packet PTS/duration differences stayed within 0.001001 seconds without accumulated tolerance. Source bytes remained unchanged.

Complete decoded-picture SHA-256: 684a6ec29841f7c7449f5ae14d0fa0eabc15a830c588685655205dddfcc1c744. The second experiment completed in under a second, within the five-minute bound. All generated files and raw receipts stay in the owned local discovery folder. This is format feasibility, not actual-controller/native acceptance or broad player/visual certification. M2 may proceed within the approved contract; S40 gates remain pending.
