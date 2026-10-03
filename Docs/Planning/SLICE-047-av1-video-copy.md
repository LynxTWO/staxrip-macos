# Slice 047: Preserve AV1 video across MP4 and MKV
Date: 2026-10-03. Status: implemented; local actual-queue matrix, ordinary regression and optimized build passed. Native reviewed export is blocked by the locked console; hosted qualification is pending.

## Outcome and walkthrough

Open a generated AV1 Main 8/10-bit BT.709 limited-range SDR source, choose Copy original, No audio and original picture settings. Add a generated caption and custom chapters, review the destination and run the real queue. The completed output preserves complete encoded video/configuration and pictures within the existing fixed timing precision. The native guidance identifies the supported AV1 boundary. This is remuxing; no video encoder is used.

## Scope and build order

M1: Bounded generated eight-case feasibility matrix, two bit depths times two source and target containers. Compare every packet payload/size, complete raw pictures, color/configuration and timestamps; verify meaningful low-order ten-bit samples. Retain the initial missing-color declaration experiment; explicit SVT-AV1 parameters establish the actual qualified fixtures.

M2: Extend VideoCopyContract only to AV1 Main yuv420p/yuv420p10le with complete BT.709 primaries/transfer/matrix and limited range. Retain upright/progressive/square-pixel/zero-start, duration, time base, metadata/configuration, packet, resource, source stability and publication checks. Reuse the existing copy intent, controller, verification and caption/chapter paths. No general high-bit-depth or unknown metadata bypass.

M3: Real BatchController matrix with independent decoded picture/frame/timing/caption/chapter checks; negative profile/pixel/color/HDR/settings/metadata controls; native copy guidance and actual operation; ordinary local/hosted regression and optimized bundle.

## Gates

| Gate | Required evidence |
| --- | --- |
| av1-copy-feasibility | All eight generated remux cases; every packet/picture, fixed precision and real low bits |
| av1-copy-plan | No encoder, no transforms; incomplete/unsupported format and altered output refusal |
| av1-copy-output | Eight real queue outputs; 72 decoded frames each, exact picture digest, captions/chapters, protected sources/prior output and settled owned staging |
| av1-copy-native | Native support guidance and actual reviewed copy operation with protected recovery state |
| av1-copy-regression | Ordinary local/hosted checks and optimized build |

## Limits and guardrails

SDR AV1 Main with complete declarations only. HDR, Dolby Vision Profile 10, HDR10+, HLG, other profiles/depths/subsampling, geometry/timing expansion, AV1 re-encoding, audio DSP/listening and player interoperability remain separate. No saved-format change, new dependency, deadline/scheduling change, merge or release. Unknown/dynamic side data still refuses. Historical hosted mastering cancellation recurrence remains an independent reopen trigger; no blind retries or relaxed guard.

Owner authority: explicit preservation/conversion request and autonomous implementation delegation, 2026-10-03. Slice 046's corrected native labels are observed and its final hosted repair run passed; that inspection evidence remains independent of this bounded copy work. R-057 authorizes generated actual-queue verification through existing seams, not a new assurance service.
