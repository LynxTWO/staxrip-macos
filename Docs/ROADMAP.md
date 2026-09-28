# Product direction

Build a native Mac video and audio workstation whose power is measurable and whose controls remain understandable. StaxRip is a starting reference. The working name can change; copying its layout or capping the feature set at parity is not a requirement.

## Milestone reached

Native source preview, independent advanced configurations, editable queue, validated saved sessions, light/dark UI and a real, cancellable H.264/HEVC + AAC MP4 export path. The optional FFmpeg backend now executes sequential AV1/x264/x265 jobs with crop/scale, AAC/Opus/copy, subtitle copying, cancellation and output verification. A probed track inspector is available. This is an early developer preview, not a competitor-leading encoder suite.

## Next reviewable milestones

| Priority | Capability | Acceptance evidence |
| --- | --- | --- |
| 1 | Capability-driven encoding plans | Probe actual backend/tool support; every visible setting maps to a verified operation or explicit unsupported reason. |
| 2 | Advanced batch engine | Real AV1, H.264 and HEVC jobs; CRF/bitrate modes; deterministic command arguments; cancellation; bounded logs; output validation; crash recovery; tests for conflicting destinations. |
| 3 | Track-level media inspector | Video format, color/HDR metadata, rotation, sample aspect ratio, frame timing; audio languages/layouts; subtitles/chapters; missing/unknown metadata visible. |
| 4 | Serious audio tools | Stream selection, passthrough, AAC/Opus/FLAC where supported, sample-rate/channel mapping, loudness analysis and normalization; verify duration, channel layout and measured levels. |
| 5 | Filter and preview pipeline | Accurate trim/crop/scale/deinterlace/tone mapping, source/output comparison and frame stepping; prove preview/export agreement and A/V sync. |
| 6 | Quality and speed laboratory | Repeatable short sample encodes, visual comparison, supported objective metrics, time/size/energy records; pin inputs, tool versions and hardware context. |
| 7 | Mac production fit | Accessibility audit, keyboard workflow, sleep/thermal/resource behavior, undo, recovery, signed/notarized delivery and long-run test matrix. |

External tool integration needs explicit provenance and distribution/license review before bundled releases. The native backend must not pretend to implement codec-specific CRF or preservation contracts it does not support.

## What earns a superiority claim

Publish a reproducible comparison using the same sources, output constraints and hardware. Report supported workflows and failure behavior alongside throughput, quality, file size, memory and energy. Include difficult material: variable frame rate, rotation, HDR, interlacing, multiple audio/subtitle tracks and damaged inputs. Separate measured results from planned capability. No “most powerful” claim before this evidence exists.

## Development cadence and stopping points

Ship small PRs with tests and a runnable local preview. Keep an unmerged PR stack when later work depends on earlier review. Continue autonomously across milestones while implementation and validation are possible. Stop for genuine external dependencies such as unavailable signing credentials, required account actions, or missing representative media/hardware needed to validate a preservation contract. Do not disguise CI/account restrictions as test failures in application code.
