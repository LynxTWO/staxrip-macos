# Caption playback choices evidence
Date: 2026-10-01. Scope: Slice 042 / D-080 / R-052.

## Baseline and authority

Product baseline 22b4dea. Plan a4a585b precedes all experiments and implementation. Owner delegated autonomous non-audio completion; no merge or release. Existing original-caption, cancellation, scheduling and protected-publication contracts remain mandatory.

## M1 container feasibility

Verified observed_behavior, user_data scope: FFmpeg 9.0.2 generated two-second 160x96 24 fps H.264, two silent FLAC audio streams with no input default and one default/forced/hearing-impaired SubRip track. Two distinct external SRTs were added. Ordinary baseline remux and explicit default/forced or optional cases were compared with and without the embedded track. All six output files passed in 0.544 seconds under the ten-minute bound. Local script/log: work/caption-flags/feasibility.py and feasibility.log, outside Git.

Both audio/video default and forced bits match the ordinary remux. First audio default is restored explicitly when multiple mapped audio streams lack one. Selecting the last caption as default clears the embedded default but preserves its forced and hearing-impaired flags. First added Forced produces only the forced bit. Explicit Optional clears both bits without assigning a replacement. Every output subtitle fully decodes to its baseline SRT bytes. Source SHA-256 remains 2a6401ad172b51d84f3d3867009859c1f1cabde89122951bb5729df74e6effc0.

References: https://ffmpeg.org/ffmpeg.html (disposition incremental updates and automatic default rules), https://ffmpeg.org/ffmpeg-formats.html#matroska (passthrough default handling). The experiment establishes configured container flags only, not player behavior. MP4, arbitrary source metadata and heard accessibility remain unqualified.

## Implementation and remaining gates

M2 and M3 pending. S42-001 passed; S42-002 through S42-006 pending. No acceptance claim yet.
