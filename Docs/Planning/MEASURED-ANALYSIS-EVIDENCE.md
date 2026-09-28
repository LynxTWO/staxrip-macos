# Slice 001 measurement evidence
Version: 0.1 Draft. Date: 2026-09-28.

Status: Done with evidence. Owner approved implementation and subsequently confirmed the functional and spoken walkthroughs, including the H.264 pronunciation correction, on 2026-09-28. This is measurement/reporting, not automatic dialogue-aware gain processing.

## Implemented boundary

SignalForge-derived Swift K-weighting and integrated gating, four-phase 12-tap true-peak estimate, EBU LRA, 20 ms trajectories, individual mono channel diagnostics, separately reset user-selected speech intervals, source SHA-256 before/after analysis, decoder provenance and local versioned report save/reopen. No new dependency runtime. SignalForge MIT notice retained in source repository and development bundles.

Metadata-free legacy PCM WAV needs an explicit mono/stereo declaration. Surround and unknown layouts are not inferred. Supported rates: 44.1, 48, 88.2, 96 and 192 kHz. Current upper limit: four hours, 16 non-overlapping speech regions and 32 MiB saved reports. Source paths are omitted from reports. Saved measurements remain informational; source verification does not authenticate the correctness of externally edited values and no saved report drives rendering.

## Numerical evidence

Official EBU v5 archive SHA-256: `9cc500b4df83f7c21855c74dce795ef5209a752bf884253ae57d0ce512efb062`. Per-file manifest: ../EBU-V5-MANIFEST.json. Obtained from the [official EBU page](https://tech.ebu.ch/publications/ebu_loudness_test_set) through the browser after command-line requests returned HTTP 403. Media is kept outside Git for internal research only under the linked terms. Test sequences © EBU; no audio is redistributed.

The supported gate exercises 64 distinct mono/stereo sequences: seven integrated cases, six LRA cases (two shared with integrated), nine peak cases, 21 short-term maximum cases, 21 momentary maximum cases, and two trajectory-step cases. Integrated and trajectory tolerances are 0.1 LU; LRA 1 LU; true peak -0.4/+0.2 dB around nominal. Surround case 6 and reference-listening calibration are outside this gate. Passing these minimum checks is not metering certification or proof of correctness for all material.

Independent generated-tone checks compare to FFmpeg ebur128, with the same 1.5-second LRA tail, at 0.15 LU integrated, 1 LU LRA and 0.2 dB peak tolerances. SignalForge's wrapper is not counted as a second independent implementation. Generated tests also cover five sample rates, chunk partition invariance, mono/stereo weighting, silence, short inputs and invalid samples.

Command: `STAXRIP_EBU_TEST_SET=/local/fixture/directory scripts/check-meter-conformance.command`. The script exits 2 if the directory is missing; missing/checksum-mismatched required files fail the test. The ordinary suite skips this separate gate when fixtures are not configured and does not establish conformance by doing so. See AnalysisConformanceTests for expected-case inventory.

## Full-length memory and timing

Release build on Apple M5, macOS 27.0: generated two-hour, 48 kHz stereo FLAC; 345,600,000 frames; 360,000 programme trace points. Analysis, source hashes, report save and reopen completed in 52.96 seconds. Peak test-process resident memory was 111,837,184 bytes (106.7 MiB), below the provisional 512 MiB ceiling. This excludes fixture generation and does not establish performance on older Macs, other codecs or actual film content.

Initial runs exceeded the memory limit. Compact lossless timeline serialization reduces report overhead, but the decisive streaming fix resets the PCM remainder's backing storage rather than retaining consumed Data prefixes. Decoder reads also drain autoreleased buffers per chunk and retain no raw stdout PCM. The same two-hour gate passed after these changes; the target was not relaxed.

Command: `STAXRIP_LONG_ANALYSIS=1 swift test -c release --filter twoHourStreamingProfile`. The test generates its own source and removes its own files. It includes report equality after reopen and asserts the memory ceiling. Ten-minute diagnostic results are not substituted for this gate.

## UI and failure evidence

Native inspection is available again. A generated 12-second stereo fixture produced -22.13 LUFS, 0.62 LU LRA, -19.99 dBTP and -20.00 dBFS in Audio Lab. An out-of-range manual interval produced an error, then editing its end from 30 to 8 seconds allowed measurement. Programme metrics, timeline series and fields are present in the accessibility tree. The chart samples at most 1,000 points and separates valid stretches so lines do not bridge unavailable windows.

Automated gates cover report round trip, collision/source overwrite refusal, unavailable values, future schema, malformed timeline flags/nonfinite samples, wrong fingerprint/layout, changed source identity, missing decoder, invalid track/interval, unreadable media, missing destination folder, and cancellation with source unchanged. Cancellation must return within five seconds in the selected test. Full disk exhaustion and a complete VoiceOver listening walkthrough remain broader validation gaps; accessibility-tree exposure alone is not a complete accessibility audit.

## Receipts and current gate status

Local logs are retained outside Git: measured-ebu.log, measured-long-profile.log, measured-all-release.log and measured-all-debug.log. They include no user media. Debug and release full regression runs passed (47 tests in eight suites, with opt-in gates explicitly skipped when not configured). The release run included the 64 official supported EBU sequences; the two-hour gate ran separately. A final focused release run passed after report-read cancellation guards. The missing-fixture script was exercised and returned exit 2 with an explicit unmet status.

Native save, reopen and source verification passed: reopening preserved all displayed metrics, marked the source unverified, then Verify source changed the status to Fingerprint matched. Native cancellation returned without publishing a report and a retry completed. Daniel subsequently confirmed the functional walkthrough passed and approved the layered VoiceOver refinement. Its listening verification remains open; see ../VOICEOVER-GUIDANCE.md. The implementation PR and hosted check will be linked in the PR receipt. No merge, production signature, notarization upload or release is part of this slice.

## Owner closure and hosted receipts

Daniel reported that everything worked, then that the spoken experience sounded good after a codec-pronunciation correction. Scope is the exercised native workflow; this does not claim every VoiceOver voice, option or platform was tested. [Measurement PR 13](https://github.com/LynxTWO/staxrip-macos/pull/13) and [guidance PR 14](https://github.com/LynxTWO/staxrip-macos/pull/14) remain unmerged. [Latest hosted check for 96f1d38](https://github.com/LynxTWO/staxrip-macos/actions/runs/36458466940) passed in 3m27s. The local post-correction regression suite passed in 68.77 seconds. Earlier pending-walkthrough notes above are historical and superseded by this receipt.
