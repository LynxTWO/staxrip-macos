# Native container configuration evidence
Version: 0.2. Date: 2026-10-03. Scope: Slice 048 M1 / D-089 / R-058. Status: focused native/parser/build checks passed; ordinary regression pending the recorded hosted reframe. No new HDR copy admission.

## Representation and bounds

The native Swift reader captures complete MP4 visual sample-entry fields (including hvcC/dvcC/dvvC/hvcE) with track ID, and Matroska video CodecPrivate plus mapping type, optional frame ID, name and complete opaque extra bytes with track number/UID. Unknown opaque fields remain represented rather than silently dropped; later format-specific admission must classify them. No FEL/MEL inference, Dolby decoding, packet additional-data acceptance or tool dependency is added. The utility is an internal prerequisite, not wired to an advertised product workflow yet.

Input must be a nonempty local regular file opened read-only without following a final symlink. Descriptor identity/size/modification time are checked around reads; this does not provide a content snapshot or replace the executor's complete source fingerprints. Cancellation is checked between bounded reads, but a pending filesystem read can still wait. The parser retains at most 16 MiB per captured payload, reads at most 64 MiB total, processes at most 16384 metadata elements and 256 tracks, and traverses at most one million Matroska segment-level elements without retaining a cluster array or reading media bodies. Header bytes for those traversals count against the total read budget.

Ambiguous/repeated identities, codec or mapping fields/types/frame IDs, truncated or overflowing lengths, unsupported nested unknown lengths, multiple segments/Tracks, encrypted/encoded Matroska tracks, fragmented MP4 and multiple MP4 sample descriptions refuse. The reader supports finite clusters and a finite or unknown-size Segment; streaming unknown-size clusters require a separate parser contract. Unsupported future EBML reader declarations refuse. This is structural configuration capture, not a complete container validator.

## Retained initial limit failure and scalable repair

Initial generated tests passed six checks, but the first private full-file native exercise hit the 16384 combined element limit. Direct bounded top-level enumeration measured 36657 segment elements in the source, including 36648 finite clusters; the remux had 36423 elements/36414 clusters. No metadata/payload threshold was relaxed to hide an invalid record. The repair separates finite cluster-header traversal from the unchanged 16384 metadata budget, limits segment traversal explicitly to one million and retains the 64 MiB read bound. It streams those headers without a cluster array, still detects late duplicate Tracks, and reads no cluster payload. The failed native receipt is retained privately.

## Focused tests and full-file native exercise

Eight tests passed in 0.439 seconds: complete opaque Dolby/enhancement records across both containers, unknown-field retention without admission, duplicate/ambiguous/encrypted ownership refusals, every generated Matroska truncation and nested unknown-length refusal, payload/metadata/track bounds, 40000-cluster traversal/late duplicate and one-million traversal refusal, an actual sparse 1 GiB MP4 body with late configuration, and regular-file/source-byte/symlink/directory/URL checks. The sparse test proves media-body skipping through the real filesystem reader; fixtures are owned temporary files and removed.

The same Swift implementation, compiled independently against Apple's native frameworks, read the original private source and both full-length research candidates. Matroska track number/UID/codec/configuration/mapping records matched exactly. Across Matroska and explicitly signaled hvc1 MP4, complete 752-byte HEVC configuration, 24-byte Dolby configuration and 748-byte enhancement configuration matched. The codec bytes independently matched the earlier local FFmpeg/MKVToolNix audit. Complete source hash and owner recovery protection receipts remain private; source identity is never embedded in code/public evidence. No research C binary or MKVToolNix dependency is added to the app.

Optimized build.command succeeded with the layered icon and strict ad-hoc development signature. Private logs: work/format-assessment/header-focused-final.log and header-optimized-build.log; native receipt remains in the private format study. This is not notarization or a release.

## Remaining qualification

Ordinary regression is pending because hosted recurrence 37115174217 reached D-077/D-087's recorded reframe stop. No blind rerun or observer expansion was added to qualify this reader. M1 is therefore incomplete, despite its focused/native/build results. Full packet additions, persistence/intent migration, audio/caption/timeline contracts, actual protected queue export, player/HDR/reference viewing and broader platforms remain M2–M5 obligations. The earlier complete Matroska TrueHD exact-timing failure is retained in the Slice 048 brief. Copying configuration bytes is not Dolby rendering or full-film export acceptance.

Primary specifications: [Matroska elements](https://www.matroska.org/technical/elements.html), [registered additional mappings](https://www.matroska.org/technical/block_additional_mappings.html), and [FFmpeg MP4 writer](https://github.com/FFmpeg/FFmpeg/blob/n9.0/libavformat/movenc.c).


## Independent full-film packet and decoded-channel check

Read-only full-video inventory with FFmpeg 9.0.2 found no packet-side-data records on any of the 120552 packets from this particular source. Enhancement and RPU data are carried inside the encoded NAL payloads already counted by the independent full-packet study. This verifies only this source's representation; it does not qualify generic raw Matroska BlockAdditional data or replace M2's required refusal for unmeasurable extra payloads.

Complete independent TrueHD decoding of original and full Matroska candidate produced identical SHA256 digests over signed 32-bit little-endian PCM channel samples at the decoded original rate/layout. Each complete decode took approximately 52 seconds. The FFmpeg codec defaults were unchanged; no normalization, filter, speech processing, listening or Atmos object rendering was performed. Private receipt: work/format-assessment/dovi-copy-feasibility/truehd-pcm-comparison.json. Recovery bytes and original descriptor identity/size/modification time remained unchanged. This decoded equality supplements the earlier complete compressed-payload equality; it does not erase the retained one-millisecond container timestamp changes or establish player A/V synchronization.

D-090's one approved hosted investigation passed the original 291-test workload at 0ab9d28, but did not reproduce or locate the earlier cancellation/matrix delay. Instrumentation is retired on its own local checkpoint; no second attempt. This reader's eight extra tests were deliberately excluded, so that result does not satisfy M1 ordinary regression. The unresolved qualification decision remains in HOSTED-QUALIFICATION-REFRAME.md. No new runtime admission, merge or release.
