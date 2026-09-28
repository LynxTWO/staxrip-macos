# WavPack staging evaluation

Owner-requested local experiment, 2026-09-28. No storage implementation or dependency installation resulted from this benchmark.

## Format boundary

The [official WavPack feature list](https://www.wavpack.com/) supports lossless 8/16/24/32-bit integer PCM and 32-bit floating point, and publishes the library under a BSD license. It does not advertise arbitrary Float64 audio support. Local FFmpeg 9.0.2's built-in wavpack encoder accepts `u8p`, `s16p`, `s32p`, and `fltp`, not Double. Do not confuse a lossless Float32 codec with a lossless Float64-to-Float32 conversion. Use lossless mode, never a hybrid file without its correction data.

## Local result

Apple M5; one 60-second, 48 kHz stereo excerpt (100–160 seconds) from the explicitly prepared Sintel source in LISTENING-MANIFEST.md. Original and a double-precision gain-adjusted copy (`volume=1.23456789:precision=double`) were compared. Default FFmpeg WavPack compression, three runs, warm local files. The mastering resource test was also active, so these are indicative timings, not isolated performance guarantees or measured whole-pipeline overhead.

| Case | Float64 WAV bytes | Float32 WAV bytes | WavPack bytes | Median encode | Median decode |
| --- | ---: | ---: | ---: | ---: | ---: |
| Original | 46,080,092 | 23,040,092 | 8,904,246 | 0.187 s | 0.046 s |
| Gain-adjusted | 46,080,092 | 23,040,092 | 16,099,046 | 0.219 s | 0.051 s |

Both cases restored the Float32 PCM byte-for-byte in all three runs. SHA-256: original `ed15b059af4d178a2689b539cbc1da985bc48e2ef6225ce558333f5dc1e0aeab`; adjusted `2fe2a6144b8c76aafda9c9b849b5133cd46315115e1fedc87daf941b0f87db7d`.

The original also restored Float64 PCM exactly because this particular 24-bit source was exactly representable as Float32. The adjusted Float64 PCM did not: maximum absolute rounding difference was `7.446347483064386e-09`. WavPack introduced no further Float32 loss. This small measured error does not authorize silently reducing the app's intermediate precision or claiming all sources round-trip exactly.

Relative to Float64 WAV, file reductions were approximately 81% and 65%; part of that is the precision representation change. Relative to Float32 WAV, WavPack itself reduced size by approximately 61% and 30%. Other signals, especially noise and different channel counts/rates, may compress differently.

## Recommendation and acceptance before a switch

Prefer a verified compressed original cache when its decoded sample representation can be preserved exactly (Float32 or appropriate integer PCM), with a Float64 fallback. Keep arithmetic in Double. Avoid duplicate full-file PCM representations and investigate piping rendered chunks straight into encoding; those changes can reduce disk use without any precision conversion. For arbitrary Double caches, a general-purpose lossless block compressor is another candidate, with separate seek/index/integrity validation.

Before integration, test whole-file decoded sample hashes, negative zero/finite edge values/over-full-scale audio, frame and channel order, seeking near block/end boundaries, cancellation and corrupt-cache refusal. Benchmark actual two-hour peak disk, app/child RSS, wall time and repeated-candidate cost. Native playback can keep using small PCM excerpts decoded from the cache. Do not assume AVPlayer directly supports `.wv`. Keep source hash checks and exclusive publication unchanged.
