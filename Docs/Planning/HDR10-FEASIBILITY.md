# Static HDR10 feasibility checkpoint

Date: 2026-09-29. Local tools: FFmpeg 9.0.2, x265 4.3. This is a bounded local experiment, not a new app encoding feature or visual HDR acceptance.

## Results

| Check | Result |
| --- | --- |
| 48-frame, 320x180, 24000/1001 PQ source to lossless HEVC MP4 | All decoded frame hashes match; stream and every decoded frame retain pixel format, primaries, transfer, matrix, range, chroma location, dimensions and sample aspect ratio |
| Static metadata | Every decoded frame retains mastering-display and content-light metadata |
| MP4 timing | Maximum source/output presentation-time difference 0.5 ms; container time-base precision matters |
| True 10-bit ramp to lossless HEVC MKV | 48 frames retained, decoded hashes identical, every declared field and static metadata block identical, timestamps identical |
| Ramp precision | First decoded frame contains all four low-two-bit values, so the test exercises more than an 8-bit signal padded with zeros |
| Absent content-light values | Deleting CONTENT_LIGHT_LEVEL side data in a local experimental fixture and setting x265 cll=0 retained mastering-display metadata without inserting a content-light block |
| Automatic propagation comparison | The local wrapper also retained the tested static metadata without explicit static x265 parameters. This observation is not a cross-version guarantee; output verification remains necessary |

No lossy visual-quality, real-film, dynamic HDR, HLG, hardware encoder, audio remux or calibrated-display claim follows from these results.

## Reproduction contract

Generate a two-second 320x180 source at 24000/1001. Set yuv420p10le and use geq expressions `mod(X+Y*3+N*7,877)+64` for luma, `mod(X*5+N,897)+64` for blue chroma and `mod(Y*7+N,897)+64` for red chroma. Explicitly set frame metadata with setparams: range=limited, color_primaries=bt2020, color_trc=smpte2084, colorspace=bt2020nc. This is an artificial code-value fixture, not an HDR reference picture.

Encode both source and round trip with libx265, ultrafast, yuv420p10le, pools=1, frame-threads=1, lossless=1, repeat-headers=1, colorprim=bt2020, transfer=smpte2084, colormatrix=bt2020nc, range=limited, hdr10=1, master-display=G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,50), max-cll=1000,400. The round trip maps only video, disables audio/subtitles and uses fps_mode=passthrough. Compare actual ffprobe decoded frames and raw yuv420p10le framemd5 hashes, not just command arguments. Hash the generated files for provenance.

Ramp source SHA-256: ff46b6601c7864deee992f51564bc772b88ea24292626b4142ae94762137637a.
Ramp output SHA-256: 3f36447a9d571cfb5154c3870c2def9977501403d2d53a6943a5f7fb3f32e74a.

Local media and full receipts remain outside Git. There is no new runtime dependency or public corpus upload.

## Implications for the next build

BatchController presently verifies codec, dimensions, track counts and duration, but not color fields or HDR side data. EncodePlan deliberately rejects PQ/HLG and non-8-bit pixel formats. Removing that guard alone would not create a preservation workflow.

The first proposed export contract is software HEVC, MKV, static HDR10, with explicit opt-in. It requires a complete source frame-metadata audit and complete staged-output verification. A first-frame sample is inadequate to rule out changing/static or recognized dynamic metadata later in the file. Unknown or unsupported metadata must produce a refusal or a separately scoped policy, not silent flattening.

Source tags can be incorrect. The contract preserves the declared supported signal and metadata; it does not certify how the original was mastered. Lossless fixture equality validates pipeline handling; actual lossy output requires its own decoded output and metadata checks and cannot promise identical pixels.

Sources: [x265 metadata options](https://x265.readthedocs.io/en/master/cli.html#cmdoption-master-display) define static mastering-display and content-light signaling, separately from dynamic metadata. [FFmpeg documentation](https://ffmpeg.org/ffmpeg.html) describes frame synchronization and encoding options. Installed-tool results above determine local feasibility, not assumed behavior from documentation alone.
