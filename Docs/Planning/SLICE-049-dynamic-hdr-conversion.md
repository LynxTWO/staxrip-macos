# Slice 049: Measured dynamic HDR conversion
Version: 0.1. Date: 2026-10-03. Status: complete source census and bounded HEVC/AV1 feasibility recorded; editable HEVC VBV prerequisite implemented and locally qualified; no new Dolby Vision admission.

## Outcome and authority

The owner explicitly prioritizes a proper dynamic-HDR workflow over the parked timing investigation. Existing refusal remains until a conversion path is qualified. Preserve original signal, compatible Dolby Vision re-encoding, HDR10 fallback extraction, enhancement reconstruction and newly authored HDR10+ are separate intents with explicit information consequences. Never silently discard enhancement data or claim metadata equivalence from color tags.

D-091 / R-059 authorizes local read-only complete RPU analysis of the existing private source, owned research outputs, tool feasibility/license review and generated workflow qualification under the owner's standing autonomous development delegation. Private source names/paths/content and credentials stay out of code/public evidence. No owner queue execution or full-film encode, listening, persistent security settings, merge or release. Cancellation/publication limits and source/prior-output protections remain unchanged. D-090 is complete and parked; no further timing observation is included.

Need: the current Profile 7 declaration cannot classify its enhancement processing requirements, and the generic transcode refusal leaves no qualified path. Consequence: user_data if conversion drops picture information or attaches incorrect metadata; read-only analysis itself is local_only. Existing strict refusal and complete packet/header preservation work are controls, not obstacles to bypass.

## Bounded build sequence

M1: Pin tool versions/source identities and licenses. Parse the complete original RPU sequence, checking count, validity, MEL/FEL/subprofile changes, scene/active-area/color metadata and dependencies. Cross-check packet/RPU counts with existing independent full-film evidence. Preserve failures and source/recovery protection. Sampling does not classify the whole film. Outputs stay private; no payload or filename in public evidence.

M2: Evaluate actual macOS enhancement reconstruction before choosing the highest-information re-encode. A developer README claim does not qualify a decoder. For FEL, prove base/enhancement/RPU frame association, expected precision/geometry/chroma, signed residual handling and reference parity. For MEL or compatible single-layer sources, qualify complete RPU alignment and supported x265 integration. Distinguish rendering reconstruction from display-management trims and output metadata authoring. Do not assume original metadata remains correct after arbitrary crop/resize/cadence/trim or tone mapping.

M3: Implement only a measured feasible contract with explicit saved intent and native review. Existing SDR/static HDR10 modes retain their boundaries. Preserve unqualified alternatives as detailed refusals. HEVC Dolby Vision, AV1/HDR10 and newly derived HDR10+ require separate codec/profile/container and metadata acceptance. HDR10+ authoring analyzes resulting pictures; no one-to-one Dolby metadata translation is assumed.

M4: Actual generated queue execution, complete output metadata/frame/timing comparison, refusal mutations, cancellation and exclusive publication, native reviewed walkthrough, ordinary local regression/build. Hosted timing reliability remains a separate recorded open qualification; a new HDR implementation is not a timing repair. Private licensed real-source qualification remains local with owner state restored. Calibrated reference viewing/player validation and parked audio listening remain explicit limits.

## Feasibility candidates

Owner clarification: both original preservation and conversion choices are required. Compatible HEVC uses Profile 8.1; AV1 uses Profile 10, not an HEVC profile label. An optional companion archive must retain original RPU and enhancement data, original frame/timing association, configuration and integrity checks independently of the destination format. A metadata-only file cannot preserve FEL picture residuals. Reattachment after picture/timing edits requires a separately qualified transformation; archiving is not playback or future compatibility certification. Publish the media and archive as an explicit, collision-safe result set; never silently omit a requested companion.

Owner additionally requests editable, prefilled VBV suggestions. Implement a bounded software-HEVC control first: source/output raster and declared cadence choose a candidate HEVC level, with Main tier for compatibility or High tier for more bitrate headroom. Suggested peak and buffer limits remain distinct from manual values, persist through sessions/queue/presets and are applied by the encoder. Report that tight VBV can lower quality. Future Dolby Vision admission must also check its own level limits; generic HEVC suggestions do not certify Dolby Vision conformance. Existing sessions keep unrestricted defaults.

- dovi_tool (MIT, locally installed development tool): complete RPU analysis/conversion, not a FEL picture decoder. Mode 2 removes Profile 7 FEL mapping; discard removes enhancement. These are disclosed transformations, never full-signal preservation.
- x265: documented supported single-layer profiles and RPU input; CLI/API integration must be tested with the installed build rather than assumed from option names.
- libplacebo: applies decoded frame RPU metadata and removes it from output; this does not by itself prove enhancement reconstruction. The installed FFmpeg lacks this filter.
- FelBaker/DoViBaker: evaluate pinned source, license, macOS build, precision, synchronization and reconstruction evidence before integration. No unreviewed executable or new bundled dependency.

## Picture-edit contract

Owner explicitly includes crop and resize. Preserve the untouched original RPU/EL separately. An edit manifest must record coded raster and codec conformance-window removal, decoded raster, container crop/display units, rotation/orientation, original/output sample aspect, chroma siting and resampling, the exact effective pixel crop rectangle, padding, resize kernel/dimensions and original/output frame mapping/timestamps. Keep decoder, container, user crop and Dolby active-area coordinate systems explicit; do not subtract the same crop twice. RPU Level 5 coordinates must be transformed into the output raster with validated bounds and deliberate rounding consistent with subsampling; reject ambiguous active-area mapping. Actual picture edits may change content statistics (Level 1 and MaxCLL/MaxFALL), while target-display trims represent artistic intent and are not automatically interchangeable with new HDR10+ authoring. Do not blindly reuse the original RPU after crop, scale, color/gamut/tone mapping, deinterlace, cadence edits or trimming. Initially qualify unchanged geometry and cadence; keep edited dynamic HDR refused until actual transformed metadata and picture evidence exists. Retaining an archive does not make the edited media equivalent to the original master.

## Gates

| Gate | Required evidence |
| --- | --- |
| dovi-source | Complete validated source RPU census, independent counts and protected source/journal |
| conversion-feasibility | Pinned capability/license facts plus actual generated and bounded private reconstruction/encoding results; losses explicit |
| conversion-contract | Typed intent, supported profile/metadata/geometry bounds and no silent fallback |
| conversion-output | Complete actual output metadata/frame/timing checks and mutations/refusal/settled cancellation |
| conversion-native | Native reviewed choice and result; correct losses/readiness labels |
| conversion-regression | Appropriate focused, ordinary local/build and explicit hosted-status record |

Primary references: [dovi_tool](https://github.com/quietvoid/dovi_tool), [x265 options](https://x265.readthedocs.io/en/master/cli.html), [FFmpeg libplacebo](https://ffmpeg.org/ffmpeg-filters.html#libplacebo), [FelBaker](https://github.com/bbeny123/felbaker), [DoViBaker](https://github.com/erazortt/DoViBaker).

## Companion package detail

Provide a lightweight original-metadata archive and a complete original-video archive with explicit storage estimates and information differences. When enhancement residuals are present, RPU plus EL alone is not a complete master: the residual belongs to its matching original base picture, and a newly compressed base cannot be assumed interchangeable. Complete preservation therefore retains the matching original encoded BL as well, plus EL/RPU/configuration and packet/frame timeline. For unsupported destination carriage, an archive saves recoverable source material; it does not turn that destination into a Dolby Vision bitstream. Never mark an HDR-only video as Dolby Vision just because a companion exists.

A result directory containing media, companion and manifest can be published with one exclusive directory operation; two independent file renames cannot be advertised as an atomic set. Design the destination review around this package when archival is requested, retain existing flat-file behavior otherwise, preflight space for original-video plus staged media, and verify all requested components before publication. Collision, cancellation or verification failure must leave no partial success claim or overwrite. Original and transformed metadata belong in separately identified components with independent integrity checks.

Source/encoder research: DYNAMIC-HDR-FEASIBILITY-EVIDENCE.md. Implemented VBV prerequisite: HEVC-BUFFER-LIMITS-EVIDENCE.md. Source metadata counts and bounded semantic preservation do not close complete runtime conversion, original preservation, companion publication, picture edits or calibrated rendering gates.

D-093 adds a locally qualified development-only bounded RPU archive reader. BOUNDED-DOLBY-READER-EVIDENCE.md records generated failures and the full original archive comparison. This closes an archive-read prerequisite only; native integration, container extraction completeness, frame mapping and edited-picture qualification remain open.


D-094 adds a development-only bounded Matroska HEVC packet reader with signed timestamps, duplicate-preserving RPU association and strict read failure boundaries. BOUNDED-MATROSKA-DOLBY-EVIDENCE.md records generated FFprobe comparisons and complete private source agreement. This is an extraction/association prerequisite, not native admission, decoded-frame/POC qualification, crop/resize validity or rendering. Presentation-order archives and decoding-order packets must remain distinct in edit manifests.


D-095 admits a fixed bundled read-only native Matroska HEVC inspector with protocol 3,
complete encoded-packet/hash/timestamp proof, selected configuration agreement and a
final source fingerprint. The active-area UI explicitly separates container crop,
display units and Level 5 luma offsets. Generated protocol/lifecycle/actual helper
checks, ordinary regression, licensed nested-helper build and a focused native
walkthrough are the required boundary; evidence is recorded separately. This does
not close conversion, decoded-picture/POC, brightness, archive publication,
crop/resize, rendering or hosted timing-reliability gates.
