# SDR frame timing evidence

Date: 2026-10-01. Slice 026 under D-040 / R-030. Product head f06d431. Local and native checks passed within the limits below; hosted run 36813735721 passed at that head.

## S26-001: observed failure and correction

A generated one-second FFV1 source contains 24 frames with alternating short and long intervals in a one-millisecond time base. The new test ran the unchanged actual EncodePlan and failed on 12 decoded timestamps, shifted by 18 or 19 milliseconds. Frame count alone would not catch this. Exploratory passthrough-only commands also retained the quantization.

The SDR plan now supplies video-specific fps_mode passthrough and enc_time_base filter. The separately audited static HDR10 path and audio options are unchanged. FFmpeg's [advanced options](https://ffmpeg.org/ffmpeg.html#Advanced-options), reviewed 2026-10-01, document the inverse-frame-rate default and filter time-base alternative. Muxers can still alter timestamps; these options are not a runtime completeness guarantee.

## S26-002 and S26-003: generated matrix

Three focused test declarations passed in 2.864 seconds with local hardware enabled. They executed 53 short output encodes: one negative-control replacement, 36 software cases across H.264/HEVC/AV1, and 16 hardware cases across H.264/HEVC. All compare decoded presentation timestamps and frame counts from actual EncodePlan output against independently decoded source frames. Tests preserve source bytes.

Software cases cover irregular VFR intervals, nominal-rate gaps and 24000/1001 CFR in MKV and MP4. Each runs whole-source and cropped/BWDIF/trimmed variants. Trim expectations select source frames inside 0.2 to 0.85 seconds and subtract the requested start, rather than assuming the first retained frame occurs at zero. Hardware covers irregular and fractional sources in both containers and variants on the development Mac. The allowance is one millisecond for MKV, or one output tick for MP4, plus a one-nanosecond floating comparison allowance. Tests require source/output ticks no larger than one millisecond.

## Native queue evidence and retained limitation

The rebuilt macOS 27.0.1 app opened the generated saved session and explicitly reviewed its FFV1 source. It truthfully reported native preview unavailable while allowing advanced queue execution. The first attempt encoded and verified but waited in Finishing. A process sample showed the utility publication thread in Darwin.link; the UI remained responsive. Quit correctly refused while the operation was active. Destination review during the pending call did not settle it. The owned preview process was terminated with SIGTERM; this is not successful operation cancellation. Its journal and staging remain in the ignored diagnostic directory.

After relaunch, Restore previous queue displayed Interrupted and warned about retained partial files. Explicit destination review before retry and read-only queue preflight succeeded. Start queue then completed publication. Independent ffprobe inspection found all 24 decoded timestamps exactly equal to the original source. The source SHA-256 remained unchanged; the successful attempt cleaned its own staging and left the interrupted staging untouched. The earlier recovery record was backed up and restored after quitting the completed test app; both test journals were retained separately.

This retry is scoped native cadence evidence. It does not resolve the recurring filesystem-access limitation or prove its root cause. Prior attempts and diagnostics must remain visible in acceptance records.

## S26-004: regression receipts

| Scope | Result |
| --- | --- |
| Original actual-plan negative control | Failed as required: 12 timestamp issues, 0.212 seconds |
| Focused matrix with local hardware enabled | 3 test declarations, 53 outputs passed in 2.864 seconds |
| Full local release | 200 tests / 40 suites passed in 38.664 seconds |
| Ad-hoc native app build | Passed in 15.93 seconds |
| Hosted 36813735721 / f06d431 | Swift 6.1.2, 200 tests passed in 616.001 seconds; software cadence matrix 20.554 seconds |

Existing exclusions remain unchanged; the new hardware test uses the existing opt-in hardware environment and is exercised separately above. No deadline, test scheduling or prior assertion was weakened. Ignored cadence logs, cadence-discovery and cadence-native receipts retain the observations. Draft PR 43 is unmerged. No media, binaries, private paths or credentials are committed.

Unusual/discontinuous timestamps, long-film A/V sync, representative real-media qualification and runtime per-frame verification remain open. Audio listening remains parked.

S26-001 through S26-004 are accepted within these limits. The native filesystem wait remains open evidence, not erased by the successful retry.
