# Slice 049: Measured dynamic HDR conversion
Version: 0.1. Date: 2026-10-03. Status: native encoded inspection, editable HEVC VBV and development base-frame association locally qualified; bounded encoder feasibility recorded; no new Dolby Vision conversion admission.

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

Owner explicitly includes crop and resize. Preserve the untouched original RPU/EL separately. An edit manifest must record coded raster and codec conformance-window removal, decoded raster, container crop/display units, rotation/orientation, original/output sample aspect, chroma siting and resampling, effective pixel crop rectangle with integer coordinates, padding, resize kernel/dimensions and original/output frame mapping/timestamps. Keep decoder, container, user crop and Dolby active-area coordinate systems explicit; do not subtract the same crop twice. RPU Level 5 coordinates must be transformed into the output raster with validated bounds and deliberate rounding consistent with subsampling; reject ambiguous active-area mapping. Actual picture edits may change content statistics (Level 1 and MaxCLL/MaxFALL), while target-display trims represent artistic intent and are not automatically interchangeable with new HDR10+ authoring. Do not blindly reuse the original RPU after crop, scale, color/gamut/tone mapping, deinterlace, cadence edits or trimming. Initially qualify unchanged geometry and cadence; keep edited dynamic HDR refused until actual transformed metadata and picture evidence exists. Retaining an archive does not make the edited media equivalent to the original master.

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

D-096 adds a separate unbundled installed-FFmpeg base-picture reference with raw RPU
digests, original packet provenance and unapplied codec conformance cropping. A
bounded on-disk checker requires packet/raw-buffer agreement and complete one-to-one
coverage, rather than infer it from PTS sorting or opaque propagation alone. Generated
codec cropping, B-frame reorder, surplus/missing RPU and CRA/nonoutput cases precede
private complete-source verification. DECODED-DOLBY-ASSOCIATION-EVIDENCE.md records
the outcome and scope; original EL pairing, general POC mapping and runtime conversion
remain separate gates.

## Edited-picture analysis prerequisites

D-097 qualifies a compatible development dependency before native decoded-frame
integration. The first private dependency inherited a macOS 27 minimum; the rebuilt
candidate and development reference explicitly target macOS 14. Generated and
relocated development checks pass. Complete compatible source association passed;
Developer ID hardened loading and native resource/ownership integration stay open.
MINIMAL-DECODER-RUNTIME-EVIDENCE.md records the bounded effect and failures. No native
conversion, edit or new dependency is admitted by these observations.

Dolby's creation guidance specifies the active image before analysis, permits it to
vary by shot and distinguishes measured L1 analysis from artistic target trims.
MaxCLL/MaxFALL normally require separate calculation. Therefore removing only verified
blanking might preserve the analyzed picture region, but removing active content or
resampling it cannot be assumed to preserve those values. That distinction is a
design inference requiring resulting-picture checks, not a generic metadata rewrite.
See [Dolby active-image guidance](https://professionalsupport.dolby.com/s/article/Dolby-Vision-Content-Creation-Best-Practices-Guide?language=en_US)
and [metadata levels](https://professionalsupport.dolby.com/s/article/Dolby-Vision-Metadata-Levels?language=en_US).

For a later edited workflow, declare the source active-area coordinate basis before
transforming it. Bind every per-picture/shot region to the verified timeline; intersect
it with the effective crop, translate, then apply the same rational scale/padding and
explicit integer-edge rounding used by the picture pipeline. Refuse empty/ambiguous
regions, unresolved orientation and changing geometry. Odd luma metadata coordinates
remain valid; chroma sample alignment and the actual pixel crop/resampling policy are
separate decisions. Container display ratios do not substitute for sample dimensions.

The edit record must retain kernel, chroma siting, border treatment, sample aspect,
bit depth and color/transfer/range. Verify active-area bounds and sample actual edited
pictures with correct transfer/color handling; resampling can change peaks and mix
blanking near boundaries. Do not multiply brightness by the area ratio or relabel
original L1 as newly measured HDR10+ statistics. Burned-in subtitles/graphics are
picture edits too; variable aspect scenes cannot be collapsed to one global crop.
Preserve original metadata and matching original BL/EL independently of all transformed
results. Decoder conformance cropping, crop-only blanking removal, active-picture crop,
down/upscale, padding, subtitle overlays and variable-aspect sequences need separate
generated/output/reference tests before a native edited-Dolby choice is enabled.


D-098 implements only an internal geometry proposal seam. Explicit coded/codec/
container/decoder bases, composite crop, rational scale/padding and sample shape are
validated. Integer proposals refuse fractional edges; clipping/resizing facts do not
qualify original analysis values. Generated actual luma-grid and ordinary app checks
are required. Per-picture association, physical color/chroma/brightness, general
rounding/resampling and metadata authoring still precede any native edited admission.
See DOLBY-EDIT-GEOMETRY-EVIDENCE.md. Source/session/queue and parked listening remain
protected; no conversion/archive or signed-distribution qualification is inferred.


D-099 selects the original-companion publication prerequisite: a private owned result
stage, exact requested member size/hash checks and one same-parent exclusive directory
rename. Generated refusal/cancel/cleanup/competition checks plus ordinary regression
and build qualify the primitive only. Existing flat exports and dynamic-HDR refusal
remain unchanged. Archive writers, original BL/EL/RPU/configuration/timeline semantics,
space estimates, result review and signed distribution remain unimplemented gates.

Approved for build by: owner standing autonomous delegation, 2026-10-04, limited to
D-099's generated internal publication prerequisite. No owner archive write or native
companion execution is authorized by this build checkpoint.


D-099's internal publication prerequisite passed focused generated filesystem cases,
331-test ordinary local regression and optimized development build/signature checks.
RESULT-SET-PUBLICATION-EVIDENCE.md scopes the observed content/ownership outcomes. No
archive writer, native choice, HDR semantic admission or production completion follows.


D-100 selects a generated development producer for exact original RPU/configuration
and encoded packet association components. Metadata-only excludes picture residuals;
complete retention preserves the entire original container, explicitly including other
tracks/metadata. The native CLI stays read-only, protocol unchanged. Content recheck
and writer receipts precede a development manifest; source path identity, native consent,
decoded associations, importer and publication integration stay open.
Approved for build by: owner standing autonomous delegation, 2026-10-04, D-100's
generated development-only original component producer. No owner archive write.


D-100's generated producer passed exact original component/association checks, 24 Rust
and 15 decoded-reference tests, ordinary 331-test app regression and optimized bundle
checks. ORIGINAL-COMPANION-PRODUCER-EVIDENCE.md states metadata-only losses and whole-
container retention costs. Native source identity/cancellation/review, semantic reread,
result publication/import integration and signed distribution remain open. No native
archive choice or dynamic-HDR conversion is admitted by this library prerequisite.
