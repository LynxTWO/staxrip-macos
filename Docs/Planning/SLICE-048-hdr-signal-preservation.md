# Slice 048: Original HDR signal preservation
Version: 0.1. Date: 2026-10-03. Status: M1 focused/native/build results recorded in HDR-CONTAINER-CONFIGURATION-EVIDENCE.md; ordinary regression pending hosted reframe; no new runtime admission.

## Outcome

Copy original offers an explicit Preserve original signal intent alongside the existing qualified SDR copy intent. A completed copy preserves complete encoded picture data, Dolby Vision/HDR10+/HLG signaling when qualified, selected original audio/captions and the container timeline. The review distinguishes preserved video from any separately requested audio/subtitle conversion. Unsupported destination/metadata combinations refuse before publication, explain the missing capability and offer a qualified container instead. No fallback silently discards EL/RPU, object audio or bitmap captions.

## Observed feasibility

Local full first-video MP4 remux of the private Profile 7 source, using explicit hvc1 and Dolby signaling, preserved 120552 complete packet payloads/sizes and packet-side-data arrays in decode order. The complete HEVC configuration and coded side-data buffers matched. Counts: 120552 RPU NALs, 1371271 enhancement-layer NALs. All presentation timestamps matched; known decode timestamps matched; packet durations differed by at most 0.001 seconds. Complete source SHA256 before and after matched; owner recovery bytes were unchanged. Audio/captions were omitted from this private feasibility candidate and are not accepted by this result. It is not an app workflow or player/rendering qualification.

Retain the initial research-comparator failure: it converted AV_NOPTS_VALUE to an extreme negative time instead of recognizing an absent first source DTS. Corrected analysis explicitly reports one unreported source DTS which MP4 supplied; it does not claim that missing value was numerically preserved. Future runtime comparison must handle known/unknown timestamps deliberately and preserve presentation/decode ordering.

Default MP4 output omitted dvcC/hvcE despite retaining sampled video packets; the muxer required explicit signaling. A controlled signaled output retained both. Default MP4 and MKV changed three HEVC array-completeness flags from 1 to 0 without changing the 24 sampled packet payloads. Explicit hvc1 MP4 preserved the configuration bytes exactly. Never replace a full configuration comparison with codec/profile equality or indiscriminately mask differences.

Full Matroska feasibility retained compressed payload/packet boundaries/configuration/side data and roles on all 56 tracks across 6442015 packets; all 17 chapter structures matched. Exact timing digest comparison failed on TrueHD. Complete diagnosis covered 6033628 TrueHD packets: 1005605 known PTS/DTS values shifted by one millisecond, one absent timestamp remained absent and durations matched. An explicit source-timestamp-map experiment refused at the absent timestamp rather than inventing it. These findings remain research; no new runtime admission, forced interpolation or timing relaxation. Complete source SHA256 and owner recovery remained unchanged after both full-file candidates. MKVToolNix 102.0 is a local GPL-2.0-or-later development tool only, not bundled or a new app dependency.

Independent full-film video inventory subsequently found zero packet-side-data records across this source's 120552 video packets; EL/RPU remain in the main NAL payloads. This source-specific observation does not admit generic BlockAdditional data. Complete original/remuxed TrueHD decode produced identical channel-sample SHA256 digests at the original rate/layout with unchanged FFmpeg decoder defaults. This is measured decoded-channel equality, not Atmos object rendering, listening acceptance or exact container timing; the one-millisecond timestamp changes remain unresolved.

## Build sequence

M1: Complete the representation contract before admission. Bound native extraction of MP4 sample-entry hvcC/dvcC/dvvC/hvcE and Matroska CodecPrivate/BlockAdditionMapping data by track identity and parser resource limits. Preserve opaque enhancement configuration and reject duplicates/truncation/unknown mappings. Use independent locally installed FFmpeg API inspection as research evidence, not as an undeclared app dependency. Decide supported container representation normalization explicitly; exact equality remains the default.

M2: Extend the complete packet manifest to additional payloads and dynamic metadata where the CLI exposes raw bytes. Main-packet hashes cannot certify separate BlockAdditional data. Reject side-data representations whose full content cannot be measured. Track RPU/EL presence and association without inferring FEL/MEL from a configuration flag. Bound memory, temporary storage and record count, keep cancellation/process settlement and protected source identity.

M3: Add explicit preserved-signal copy intent, validated persistence/migration and native review. Existing SDR jobs retain their restrictions. The new intent applies only to Copy original and never re-encodes. Preserve unknown scan declarations as unknown under the qualified copying boundary rather than inventing progressive labels; retain chroma placement. Missing required color/codec/Dolby configuration still refuses. Generate static HDR10/HLG/metadata fixtures plus mutation/refusal controls; qualify real Profile 7 locally without its filename in public code/evidence.

M4: Verify every selected original audio and embedded-caption payload/configuration, index-to-output identity, language/default/forced/hearing-impaired role, layout and timestamps. TrueHD/Atmos and PGS route to a qualified MKV destination when MP4 cannot retain them. Per-track copy plus a compatibility encode is a separate authored intent; add a saved-format migration before implementing it. Subtitle OCR is information-reducing, not a lossless fallback.

M5: Full protected original-signal export through the actual queue, successful output audit before exclusive publication, verified cancellation/refusal/recovery, independent whole-film packet comparison and bounded decoded checks. The source/owner journal must remain intact. Header or packet preservation does not certify Dolby rendering, HDR display accuracy, FEL processing, AV1 Profile 10 conversion or metadata-derived HDR10+ equivalence. Keep decoder/player/reference-display gates explicit.

## Acceptance and stop rules

No advertising HDR copy until representation, actual controller, native reviewed export, full-film preservation and ordinary regression gates pass for each admitted format/container pair. No runtime API helper linking or tool installation is implied by the private research compiler. New dependency/build changes need their own feasibility and licensing decision. If raw configuration/additional data cannot be audited correctly, retain the refusal and finish the missing audit path. Do not change packet precision, mastering cancellation limits or publication policy to force a pass. A locked console blocks native actions and is not an Accessibility-permission failure.

## Primary evidence

- [FFmpeg MP4 writer](https://github.com/FFmpeg/FFmpeg/blob/n9.0/libavformat/movenc.c): writes Dolby and enhancement configuration only under its explicit compliance branch.
- [FFmpeg Matroska writer](https://github.com/FFmpeg/FFmpeg/blob/n9.0/libavformat/matroskaenc.c): retains Dolby/enhancement mappings separately from ordinary codec configuration.
- [FFmpeg probe implementation](https://github.com/FFmpeg/FFmpeg/blob/n9.0/fftools/ffprobe.c): prints selected typed fields, not every opaque coded side-data buffer; BlockAdditional bytes require explicit data output.
- [Matroska additional mappings](https://www.matroska.org/technical/block_additional_mappings.html): hvcE and Dolby decoder configuration are container extensions with distinct identities.
- [FFmpeg bitstream filters](https://ffmpeg.org/ffmpeg-bitstream-filters.html#dovi_005fsplit): Profile 7 EL/RPU can be carried in NAL types 63/62; splitting/removing them is an explicit transform.
- [FFmpeg HEVC decoder documentation](https://github.com/FFmpeg/FFmpeg/blob/n9.0/doc/decoders.texi): base-layer decoding and multiview support do not establish full Dolby enhancement reconstruction.

## Current bounded implementation: M1 container configuration reader

D-089 / R-058 authorizes a native Swift read-only configuration reader and adversarial/generated verification before any HDR copy admission. Capture complete video sample-entry configuration boxes in MP4 and CodecPrivate/BlockAdditionMapping fields in Matroska, retaining track identities and opaque bytes. Parse structure under strict read/element/track/payload bounds; reject truncated/duplicate/ambiguous metadata and unsupported layouts. Inspect private full-file candidates with the same Swift reader, without source names in the repository. The reader neither interprets EL as FEL/MEL nor executes/export/publishes media.

| Gate | M1 required evidence |
| --- | --- |
| header-structure | Generated known records, ambiguous identity/duplicates/truncation/unknown lengths/resource refusal and changed opaque-byte detection |
| header-native | Same native Swift reader on private source/candidates; codec bytes compared with independent local FFmpeg/MKVToolNix research |
| header-protection | Read-only source/candidate handling; complete source/recovery protection and no private media identity in repo |
| header-regression | Focused tests, optimized build and ordinary local/hosted checks |

M1 is an internal prerequisite, with no product workflow wired to it yet. Completion accepts only the bounded reader, not HDR copying or its remaining M2-M5 gates. Unknown container fields captured as bytes are not automatically approved for export. A whole-file byte copy, decoder output or codec label cannot substitute for container/packet/timeline verification in a remux.
