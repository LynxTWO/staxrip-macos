# StaxRip Mac Slice 004: Verified static HDR10 export
Version: 0.1 Draft. Date: 2026-09-29. Status: Proposed.

SLICE STATE
Milestone: Feasibility demonstrated on generated 10-bit data; build boundary prepared.
Blocked by: Approval of this brief and D-017.
Evidence so far: HDR10-FEASIBILITY.md; existing EncodePlan/BatchController verification inspected.
Last audit: 2026-09-29.

## 1. What the slice proves

A user explicitly chooses static HDR10 preservation, receives a checked plan, and exports a new 10-bit HEVC MKV whose supported color signaling, static metadata, frame count and timing have been verified before publication. This is not a universal HDR or archival claim.

## 2. The walkthrough

1. Open a supported source. Choose Preserve static HDR10 in advanced Video settings; the existing SDR path remains the default.
2. See software HEVC/MKV requirements and incompatible picture settings. The app explains conflicts instead of silently changing codec, container or filters.
3. Add the configuration to the queue. Before encoding, scan all selected video frames with cancellable progress. Show a concrete refusal for ambiguous, changing or unsupported metadata.
4. Encode into owned staging. Fully decode and verify the staged video before exclusive publication. A verification failure leaves the source and existing outputs untouched.
5. Inspect the completed result's before/after color metadata and verification summary. Source preview remains labelled source playback; it is not proof of calibrated HDR reproduction.

## 3. In scope, with build order

| Milestone | Boundary |
| --- | --- |
| M1 | Typed source color/static metadata and a bounded streaming frame audit. Prove static metadata stability, recognized dynamic-metadata refusal, valid numeric/rational bounds, complete EOF/exit handling and cancellation. |
| M2 | Explicit mode, validated optional session field with legacy default, software libx265 plan, immutable expected color/timing contract. Source binding must survive source changes by rechecking identity before publication. |
| M3 | Full staged-output audit, native queue results, fixture failures, cancellation and session round trips; source/output comparison is metadata verification, not a new HDR preview renderer. |

Initial inputs: HEVC, yuv420p10le, limited-range bt2020/smpte2084/bt2020nc, left chroma location, progressive, square pixels, no rotation, one selected video. Require valid mastering-display metadata; content-light metadata may be absent and must remain absent. Require a zero presentation start and stable declared properties over the complete source. Changing metadata and nonconstant frame cadence are refused in this first contract. Timestamp tolerances use actual rational time bases, not guessed integer frame rates.

Initial outputs: software HEVC Main 10 in MKV, original dimensions, no crop, resize, deinterlace or trim. Existing quality/bitrate and software speed controls remain applicable. Existing selected audio/subtitle/attachment behavior is retained only to its existing tested contract; this slice does not certify every side stream. No HDR output option in native Quick Export or Apple hardware yet.

## 4. Out of scope, on purpose

HLG, SDR tone mapping, Dolby Vision, HDR10+, other dynamic metadata, 12-bit/4:2:2/4:4:4/RGB, alpha, hardware HDR, AV1 HDR, MP4 qualification, VFR preservation, filtered HDR preview, changed mastering metadata, inferred missing metadata, calibrated visual certification, audio mastering, release signing and merges. These remain separate contracts under D-005 and D-017.

## 5. Stubs and their debts

No fake preservation toggle. Unsupported source/settings give a recoverable reason. The ordinary SDR path is unchanged. The source preview is not silently relabelled as an HDR output comparison.

## 6. Modules touched

MediaProbe/typed HDR audit, ToolRunner streaming callbacks, EncodePlan/ColorPlan, BatchController staged verification, configuration/session validation, shared workspace/queue video controls, inspector/result presentation and focused tests. No public API or new library. No custom arbitrary FFmpeg expression from saved sessions.

## 7. Data subset

An optional validated color mode defaults to existing SDR behavior for older sessions and recovery journals. Unknown modes refuse to load. Keep expected HDR properties process-local and derive them from the actual source, never trusted saved reports. Audit records contain exact rationals for display chromaticities/luminance, optional integer MaxCLL/MaxFALL, pixel/color/chroma fields, frame count, rational timestamps and source fingerprint. Parameters are constructed from bounded typed numbers, never interpolated raw metadata strings.

Streaming storage must be bounded independently of frame count: at most one bounded metadata record plus aggregate expectations/fingerprints. A frame metadata record larger than 1 MiB fails closed; retained parser and aggregate storage must stay below 16 MiB, with decoder process memory measured separately. For this fixed-cadence scope, check every source/output presentation time against the same frame-indexed rational cadence and zero start, within one tick of its respective container time base. Report the resulting source/output bound and do not accumulate per-interval tolerances. Full audit completion and successful process exit are required; partial/truncated data cannot pass. Present the cost of preflight and output verification to the user.

## 8. Acceptance criteria

| ID | Criterion | Verification | Gate |
| --- | --- | --- | --- |
| S4-001 | Only the declared supported source/settings combination is accepted; missing/invalid/conflicting metadata and recognized dynamic HDR are refused | Generated sources and hostile probe records, including changes after the first frame | hdr-preflight |
| S4-002 | Actual output matches required pixel/color/chroma fields, static metadata presence and values, frame count and timeline | Full decoded source/output audits; wrong/missing/extra metadata and altered frame/timing failures | hdr-output |
| S4-003 | The no-transform pipeline preserves real 10-bit samples in its test-only lossless mode | Synthetic ramp exercising all low-two-bit values and exact decoded-frame hashes; production lossy mode is not judged by pixel identity | hdr-pixels |
| S4-004 | Audit is bounded, cancellation returns within five seconds, incomplete/malformed output cannot pass | Chunked parser tests, actual cancellation and a ten-minute generated scan with memory receipt; no full-film throughput promise | hdr-resource |
| S4-005 | Old sessions retain SDR intent; HDR mode survives save/open/queue editing; unknown modes fail | Session/recovery round trips and existing regression | hdr-session |
| S4-006 | Changed source, failed verification, output collision and cancellation do not publish; no earlier output or source changes | Fault injection and real queued export/cancel/retry | hdr-publication |
| S4-007 | Native and accessible controls explain supported scope, progress, failure and verified outcome | Native keyboard/accessibility-tree walkthrough; spoken owner review and calibrated HDR picture evaluation remain explicitly separate | hdr-ui |

Recognized dynamic metadata detection is not a claim that the decoder can identify every proprietary payload. Before M1 closes, enumerate accepted/ignored/rejected side-data types and supported decoder/tool versions; unsupported coverage must be stated in the user-facing contract. If this cannot be made truthful, stop before enabling the mode and revise the brief.

## 9. Verification evidence required

Generated fixture recipes and hashes; actual encoder/probe versions; M1 metadata coverage policy; passing focused and regression results; native UI evidence; recorded cancellation and bounded-memory scan; explicit remaining hardware/display/real-film coverage. No new general benchmark harness, cloud service or personal media upload. Calibrated display and real-film evidence remain production gates rather than inferred from synthetic equality.

## 10. Agent guardrails

Do not remove the existing SDR restriction without this explicit mode and verifier. Do not silently drop dynamic metadata under a preserve label. Do not invent absent MaxCLL/MaxFALL or mastering values. Lossy encoding does not preserve pixels exactly. All publication remains exclusive and source files remain read-only. No dependency download, merge or release is needed.

## 11. Definition of done

All S4 checks have linked evidence; enabled behavior matches the supported metadata coverage policy; the owner can inspect the native result; remaining visual/platform qualification is visible. A broad HDR-support claim is not part of completion.

## 12. What this unlocks

Separately validated static HLG, hardware HDR and MP4; then explicit HDR-to-SDR tone mapping and output preview. Dynamic HDR requires its own representation and verification policy.

Approved for build by: Pending. This is a proposed contract, not implementation authorization.
