# Ten-bit SDR video-copy evidence
Date: 2026-10-01. Status: Scoped acceptance at 23583c3; all six Slice 040 gates passed.

## Need and scope

Slice 040 / D-078 / R-050 adds one declared ten-bit SDR HEVC format through the existing user_data export path. The existing packet/configuration/metadata comparison is the control to reuse; the pre-change VideoCopyContract and EncodePlan both refused the higher-bit-depth input. No standalone copy engine, schema, DSP or new broad color guarantee is planned.

## M1 generated feasibility

Read-only installed FFmpeg 9.0.2 encoder help lists yuv420p10le. [FFmpeg streamcopy](https://ffmpeg.org/ffmpeg.html#Streamcopy) transfers encoded packets directly but still depends on source/target container requirements. [x265 VUI options](https://x265.readthedocs.io/en/master/cli.html#vui-video-usability-information-options) supply explicit color declarations. These references inform the experiment and do not prove application support.

The first generated ten-bit gradient used only FFmpeg output color flags and did not yield primaries or transfer fields in the actual probed source. M1 correctly refused that incomplete fixture before any application changes. The corrected fixture explicitly sets x265 colorprim=bt709, transfer=bt709, colormatrix=bt709 and range=limited, following the existing HDR fixture's explicit-VUI pattern without enabling HDR. This is a fixture correction, not relaxed admission.

A generated 160 by 96, 24 fps, three-second HEVC Main 10 yuv420p10le gradient has the required progressive/square-pixel/zero-start and bt709/tv fields. Its first decoded frame contains 17,374 samples with nonzero low-order two bits out of 23,040 samples. The references explicitly decode to yuv420p10le. All four MP4/Matroska source-to-MP4/MKV combinations completed using the existing copy argument shape and metadata flags. Each retained 72 frames, 72 packets, identical packet sizes/hashes, matching codec configuration and declared pixel/profile/color fields, and the same complete decoded-picture digest. Maximum per-frame timestamp differences were zero, except MP4 to MKV at 0.000333 seconds. All packet PTS/duration differences stayed within 0.001001 seconds without accumulated tolerance. Source bytes remained unchanged.

Complete decoded-picture SHA-256: 684a6ec29841f7c7449f5ae14d0fa0eabc15a830c588685655205dddfcc1c744. The second experiment completed in under a second, within the five-minute bound. All generated files and raw receipts stay in the owned local discovery folder. This is format feasibility, not actual-controller/native acceptance or broad player/visual certification. M2 may proceed within the approved contract; S40 gates remain pending.


## Actual implementation and acceptance

Qualification head: 23583c39b17d0da461e03b30cef85c2efcd6ad65, draft PR 57. VideoCopyContract admits only the strict Main 10 / yuv420p10le / three bt709 fields / tv combination in addition to the unchanged eight-bit scope. EncodePlan skips its encoding-only pixel restriction only after that contract succeeds. Existing packet/metadata verification, controller ownership and publication are unchanged. Native visible guidance and separately spelled spoken text explain the supported format.

| Gate | Evidence and result |
| --- | --- |
| S40-001 ten-bit-copy-plan | Typed positive source makes a copy plan with no advertised video encoder and no conversion arguments. Missing each color field refuses. |
| S40-002 ten-bit-copy-pictures | Four actual-controller MP4/Matroska source-to-MP4/MKV cases retain all 72 ten-bit decoded frames, complete picture hashes and nonaccumulating 0.001001-second PTS tolerance. Low-order sample check excludes a merely upconverted eight-bit fixture. |
| S40-003 ten-bit-copy-tracks | Each actual output independently retains the complete two-cue UTF-8 SRT, language/title and two custom chapter titles/ranges; no audio, source/caption/prior-output bytes unchanged and owned staging absent. |
| S40-004 ten-bit-copy-refusal | H.264, wrong HEVC profile, 4:2:2, twelve-bit, BT.2020, PQ, HLG, full-range and Dolby Vision side-data counterexamples refuse. Altered output metadata refuses. Ordinary ten-bit SDR transcoding still refuses. Existing eight-bit matrix remains green. |
| S40-005 ten-bit-copy-native | Optimized app opened the saved generated recipe, explicitly reviewed source/caption/destination access, showed Main 10 and BT.709/tv in the inspector, and completed a silent MKV copy with 72 verified packets, two chapter titles/ranges and two caption cues. Independent full decoded-frame/picture/caption/chapter checks passed. App closed normally; guarded owned job snapshot saved and prior recovery journal restored byte for byte. |
| S40-006 ten-bit-copy-regression | Focused six tests in three suites passed in 1.679 seconds. Ordinary local swift test reported 269 tests in 63 suites passed in 213.942 seconds. Ordinary hosted run 36904515988 reported 269 tests passed in 500.880 seconds (build 79.77 seconds). Each ordinary run skipped 25 explicit opt-in checks. Optimized ad-hoc preview build passed in 17.58 seconds. Selected planning audit: zero findings across 43 documents; not an all-history audit. |

Native independent output: 8,604 bytes, 72 frames at 160 by 96, yuv420p10le, no audio, one caption track/two cues and two chapters. Maximum frame PTS difference is 0.000333 seconds. Full ten-bit picture SHA-256 equals the M1 digest above. The first output frame contains 17,374 samples with nonzero low-order bits. All four protected source/session/caption/prior-output files remain byte-identical; no owned staging remains. Stored inactive quality 17, Thorough speed and Apple hardware/8732 bitrate intent remain present in the completed recipe.

Visible native text, metadata inspection and AX labels were checked; this is not a fresh heard VoiceOver, calibrated color or broad player certification. The loaded source's player area was black while paused; successful numerical copy verification is not a playback-quality claim. Existing unexplained hosted mastering cancellation delays remain recorded in FULL-FILM-VIDEO-EVIDENCE.md. This unchanged cancellation gate passed in this ordinary run, without a claimed repair, altered deadline or observer.

Local receipts stay outside Git: ten-bit-copy-focused.log, ten-bit-copy-full-local.log, ten-bit-copy-hosted.log, ten-bit-copy-build.log, and the owned ten-bit-copy-native before/output/completed-journal/restoration records. The ordinary hosted receipt is [run 36904515988](https://github.com/LynxTWO/staxrip-macos/actions/runs/36904515988). The initial incomplete generated color fixture and all M1 evidence remain retained. No HDR, DSP, owner listening, merge, notarized release or program-completion acceptance follows.
