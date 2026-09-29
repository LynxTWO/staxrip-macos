# Static HDR10 implementation and evidence

Date: 2026-09-29. Owner approved Slice 004 / D-017 with “Yes, I approve.” Implemented on `feature/verified-hdr10`, above the unmerged HDR plan and inspector branches. This is a scoped development preview, not production HDR certification.

## Supported contract and metadata coverage

The advanced queue has an explicit **Preserve static HDR10** choice. SDR remains the legacy default. HDR requires software HEVC/x265, MKV, original dimensions, no crop, trim or deinterlacing. Incompatible choices produce an inline explanation and an execution refusal; the app does not silently alter them. Native Quick Export has a separate Apple-preset contract.

The selected first non-cover-art video must be HEVC Main 10, `yuv420p10le`, `tv`, `bt2020`, `smpte2084`, `bt2020nc`, left chroma, progressive, square pixels and zero presentation start, without rotation. Initial supported dimensions are even and 2–16384; declared average/base cadence must agree and be 1–240 fps. The timestamp time base must resolve at least two ticks per frame. Missing or ambiguous declarations refuse. This is deliberately narrower than all HDR10 files.

Tested tools: Homebrew FFmpeg/ffprobe **9.0.2**, libavcodec **63.1.102**, x265 **4.3**, Swift **6.4**, macOS **27**, Apple M5. The runtime guard accepts the 9.0.x FFmpeg/ffprobe family; other versions refuse HDR mode pending qualification. Other patch builds, operating systems and CPUs are not implied tested by that guard.

| Location/type reported by ffprobe | Policy |
| --- | --- |
| Frame `Mastering display metadata` | Required on every frame; exact rational values converted to bounded integral HEVC units, validated and compared throughout |
| Frame `Content light level metadata` | Optional, but presence and bounded MaxCLL/MaxFALL must remain identical throughout |
| Stream/container mastering and content-light metadata | Optional declarations; validate and require agreement with decoded frames; duplicates refuse |
| Frame `H.26[45] User Data Unregistered SEI message` | Ignored for this color contract; x265 encoder identification uses this type. Opaque contents are not certified or promised preserved |
| All other frame side-data types | Refused, including recognized HDR10+/SMPTE2094 dynamic metadata, Dolby Vision RPU and unknown future types |
| All other stream side-data types | Refused, including Dolby Vision configuration and display matrices |

This policy depends on what the selected decoder exposes. It cannot prove the absence of every proprietary payload, especially data hidden in unregistered SEI. The UI states that limitation alongside the mode. Do not describe this as universal dynamic-HDR detection or archival preservation. Existing audio/subtitle/attachment handling retains its existing narrower contract; this slice does not qualify every side stream.

## Data flow and bounds

1. Validate intent/settings and tool family; SHA-256 fingerprint the source.
2. Probe the selected video, then decode every source frame through ffprobe. Check fixed picture/color properties, static metadata presence/values and presentation cadence. Rehash source after preflight.
3. Build typed numeric x265 parameters, explicitly preserve absent content-light metadata with `cll=0`, and encode into an exclusively owned staging directory. No source metadata text becomes an arbitrary encoder expression.
4. Probe and fully decode the staged output. Compare properties, static metadata and frame count with the source contract; both audits check each timestamp against the same frame-indexed rational cadence, independently within one container tick. A combined source/output bound is shown, rather than accumulating per-interval tolerances.
5. Rehash source before exclusive publication. Cancellation, failed verification, changed source or destination collision does not publish. A saved session never supplies a trusted audit contract.

`HDRFrameJSON` accepts exactly a complete frames document. It stores one record (maximum 1 MiB), caps nesting at 16 and structural token count at 2048, bounds literal keys to 127 bytes and rejects duplicate keys, malformed framing and incomplete EOF. The consumer retains fixed-size typed expectations and counters, not a frame array. Parser/aggregate retained-data budget is below 16 MiB; decoder-process memory is separate. `stdoutLimit: 0` intentionally retains no transcript; successful tool exit, empty error-level stderr, parser completion and a nonempty completed audit are all required. Progress is throttled to at most four updates per second. Cancellation uses the existing interrupt/terminate/kill ladder.

Sessions now write version 5 and read versions 1–5; journals write version 4 and read versions 1–4. Missing optional color intent defaults to SDR. Unknown intent refuses. New writer versions prevent older applications from silently ignoring an HDR choice.

## Acceptance receipts

| Check | Evidence |
| --- | --- |
| S4-001 source/refusal | `HDR10Tests`: source properties, required metadata, exact rational bounds, bool/overflow integers, duplicate side data, late changes, missing metadata, recognized dynamic and unknown types; incompatible settings and missing audited plan refuse |
| S4-002 output | Actual full source/output audits with and without content light; wrong/missing/extra content-light metadata, altered count and drift/nonzero/duplicate timestamps refuse; queue fault injection changes output transfer and blocks publication |
| S4-003 samples | Generated 48-frame 160×90 PQ ramp at 24000/1001. All low two-bit values 0,1,2,3 observed. Every decoded frame hash matches in test-only x265 lossless mode, with and without CLL. Production CRF queue verifies metadata, not pixel equality |
| S4-004 resources | Byte-at-a-time and other chunk sizes; malformed, duplicate-key, oversized and truncated JSON; actual complete-output/nonzero-exit and incomplete-output/zero-exit tools refuse. Actual preflight cancellation returned in 0.0123 s in focused release run. Ten-minute receipt below |
| S4-005 persistence | Legacy intent defaults, HDR configuration/session/queue journal round trips, unknown mode refusal; native saved session and queue editor walkthrough |
| S4-006 publication | Actual queue completes; existing destination refuses; actual source mutation during encoding refuses; wrong output transfer refuses; cancellation refuses; source/prior-output safety and owned staging cleanup checked |
| S4-007 UI | Native source import, explicit mode, required MKV selection, queue execution and visible verified result. Final preview/keyboard/accessibility follow-up recorded below. Owner spoken VoiceOver and calibrated picture acceptance remain separate |

Regression: `swift test` reported **82 tests in 15 suites passed**, 215.116 s (13 opt-in tests skipped). `swift test -c release` reported **82 tests in 15 suites passed**, 9.879 s. Subsequently added failure-exit/truncated-tool coverage passed with final focused **8 HDR tests**, 2.575 s (the resource test opt-in skipped). A final one-shot parser-error cancellation guard was followed by 8 focused HDR tests passing in 2.620 s; cancellation returned in 0.0125 s. Test media and machine-local logs remain outside Git.

The final isolated optimized ten-minute scan processed **14,386 frames** in **1.254 s**, with a largest frame metadata record of **1,454 bytes**. Test-helper high-water resident memory was **50,053,120 bytes**, increasing **720,896 bytes** across the scan; its baseline includes Swift/Foundation/test runtime. An earlier 100 ms external process sample of the same ten-minute fixture recorded ffprobe peak RSS **15,450,112 bytes** separately from the parser/test helper (50,823,168 bytes). These are small 160×90 generated-fixture measurements, not 4K/feature-film throughput or decoder-memory guarantees. The structural limits are independent of movie length.

Fixture generation is executable in `HDR10Tests.fixture`: real 10-bit `geq` ramp, explicit frame color parameters, lossless x265 mastering metadata, optional content light. The earlier 320×180 fixture and hashes are in HDR10-FEASIBILITY.md. No personal media is committed or uploaded.

## Remaining qualification

Calibrated HDR display review, representative licensed real-film/long A/V sync corpus, other tool/OS/hardware builds, and full owner spoken accessibility review remain open. HLG, Dolby Vision/HDR10+, tone mapping, hardware HDR, MP4, VFR and transformed HDR pictures are outside this implementation. Audio listening/mastering stays parked. The preview is ad-hoc signed; no merge, notarization submission or release is included.

## Final native walkthrough

The optimized ad-hoc preview completed a generated 48-frame software HEVC/MKV queue job. The final result visibly listed source/output color properties, exact mastering coordinates and luminance, MaxCLL/MaxFALL, frame count and the 0.002 s combined timestamp bound without clipping. The editor showed the explicit MP4 conflict and removed it only after the tester chose MKV; other settings were not changed. Recovery restored the HDR intent without starting work, and independent queue editing produced a fresh second output. Both outputs and the source remained on disk.

A session saved through the native dialog reopened with HEVC, MKV and `Preserve static HDR10` intact and the queue ready rather than automatically executing. Accessibility inspection exposed the color picker as “Preserve static H D R ten,” its explanation, conflict text, and result. Source import used the keyboard Go To dialog/Return, Command-J added the job, and Tab navigation in the editor was exercised. A menu AX activation needed a screenshot-grounded click; the picker and replacement prompt then completed. This is scoped native/AX evidence, not a complete owner spoken review. Native AVFoundation preview of the MKV remained unavailable and was labelled accordingly; encoding eligibility did not depend on preview playback.

Final native fixture source SHA-256 remained `ff46b6601c7864deee992f51564bc772b88ea24292626b4142ae94762137637a`. Final native output SHA-256: `972b86fc48accf6eacbeec423235b0962e584bcd4991b81890bc354df3c720a8`, 13,665 bytes. Source size 363,530 bytes; both completed outputs remained and no owned batch staging directory remained. Saved native session version 5 retained `Preserve static HDR10`.
