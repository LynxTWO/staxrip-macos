# Development base-picture sample probe

This separate, unbundled tool measures decoded progressive `yuv420p10le` base
planes. It emits hashes and raw code-value count/minimum/maximum/sum/sum-square
measurements for coded and codec-visible rectangles, never pixel payloads. The
existing frame reference, frozen decoder artifacts and native metadata protocol
remain unchanged. No native sample capability or edited-picture flag is enabled.

Build with already installed FFmpeg development libraries:

```sh
python3 Tools/DolbyPictureSamples/build.py --output /explicit/new/development-output
/explicit/new/development-output /explicit/generated/source.mkv --threads 1
python3 Tools/DolbyPictureSamples/test_samples.py -v
```

`PKG_CONFIG_PATH` can select an explicitly trusted installed development prefix.
No dependency is downloaded. The builder exclusively publishes a new output and
retains failed/interrupted compiler stages. Its direct compiler join and configured
deadline/log admission are not universal descendant ownership or total disk limits.
Installed dependency deployment targets must be checked separately from the probe's
requested macOS 14 target. No Developer ID, hardened loading or distribution claim.

Each plane uses its actual positive byte stride and containing FFmpeg buffer extent.
The core accepts unaligned little-endian loads, validates the whole active plane,
excludes row padding from SHA256, and refuses values above 1023. Plane geometry is
capped at 8192 per dimension and 16,777,216 pixels; storage extent is at most 64 MiB
and stride at most 128 KiB. Counts and square sums fit unsigned 64-bit arithmetic at
that sample limit. Decoder allocations have a separate 64 MiB per-allocation cap;
neither cap establishes a total memory ceiling. No extra full-picture copy is made.
FFmpeg necessarily owns decoded picture buffers, reference pictures and threads.

Codec crop edges must be even and leave a nonempty rectangle. Chroma coordinates
and dimensions are divided by two for planar 4:2:0. Negative strides, odd crop phase,
other pixel formats and interlaced pictures refuse. Container crop/display metadata
is deliberately not applied. The test oracle disables CLI automatic cropping and
applies an explicit codec rectangle with `crop:exact=1`; CLI automatic cropping can
also apply container crop. The oracle streams one raw row at a time and shares
FFmpeg's HEVC implementation, so it is not an independent HEVC decoder.

The source/packet/frame/RPU observations reuse the reference's read-only subset.
Source descriptor and selected path observations are checked before checked close;
decoder/demuxer buffers are released before a complete row. Parent EOF, zero status
and joined direct child are still required. Partial rows, complete-looking stdout or
counts do not prove independent source/frame association. A parent must also bind
tool/dependencies and source content and own cancellation/access/resource settlement
before app integration. This probe has no native ownership controller or access lease.

Color range, primaries, transfer, matrix and chroma location are decoder declarations.
Raw code statistics are not linear luminance, legal-range interpretation, tone mapping,
colorimetric rendering, enhancement-layer reconstruction or Dolby metadata conversion.
Resize, user crop, decoded sample provenance, dynamic metadata edits and production
authentication remain separate prerequisites. See the D129 planning evidence.
