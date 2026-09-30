# Container preservation evidence

Date: 2026-09-30. Slice 011 / D-024 / R-014. In progress; native acceptance pending.

## Implemented boundary

EncodePlan records the chapter/attachment subset intended by the existing mapping. BatchController compares the staged output before exclusive publication. ffprobe requests SHA-256 extra-data hashes without dumping payload bytes; its existing 4 MiB output cap still rejects truncation. No extraction, attachment-derived paths, font loading, new settings or stored schema.

Retained flat chapter titles and tick-derived start/end times are checked, ignoring container-local IDs. Missing and empty titles both mean untitled; all other text compares exactly. Positive rational time bases, ordered nonoverlapping nonnegative ranges, 10000 chapters maximum, one-billion-second extent, 4096-byte title/name and 1024-byte MIME limits apply. MP4 requires a zero start and contiguous chapters; use MKV for gaps. Output chapter time bases must be no coarser than 1 ms; comparison tolerates one actual output tick plus 0.1 microsecond arithmetic slack. This is not frame-accurate player navigation or arbitrary metadata/edition preservation.

Retained attachment streams compare ordered filename, MIME type, byte size and SHA-256. Sizes must be nonnegative and at most Int32.max, hashes exactly 64 hexadecimal digits, with at most 1000 retained streams. Conflicting case variants of relevant tags are refused. Cover artwork is outside the retained attachment-stream policy. Trim removes chapters; only MKV with Keep embedded tracks retains attachment streams. Categories intentionally omitted must be absent from the staged output.

## Generated feasibility

FFmpeg/ffprobe 9.0.2 on macOS 27 / Apple M5: MKV retained generated chapter gaps and an attachment whose probe hash matched an independent payload digest. MP4 moved a nonzero first chapter to zero and filled gaps; that source shape is therefore refused. A contiguous fractional chapter boundary survived MP4 within one output tick despite changed IDs/time base. Missing and empty title representation varied by container. These CLI observations informed the contract; they are not general conformance evidence.

## Local tests

The first focused run passed four test functions (including two corruption cases) in 0.446 seconds. Production BatchController generated actual H.264 MKV and MP4 outputs and exercised trim and attachment-removal policies. An independent CryptoKit SHA-256 over the original attachment bytes matched both source and retained output probe hashes.

Two controlled encoder wrappers first encoded normally, then remuxed only their own staged result to remove chapters or attachments while reporting success. Both jobs failed container verification, published nothing, removed owned staging and left the source and an unrelated existing output unchanged. Pure cases cover changed titles/times/payloads/names/types/sizes, invalid/missing hashes and rational timing, excessive counts/text, overlapping ranges, unsupported MP4 gaps, output precision and omitted-category violations. An additional boundary test covers malformed omitted source metadata, oversized and zero-byte payload declarations, and conflicting title tags.

Final release regression: 118 tests in 22 suites passed in 10.056 seconds, with 14 existing opt-in skips. Optimized executable build passed in 12.50 seconds. Scaffold audit passed with zero findings.

## Pending gates

Native generated queue encode, Completed detail, and output inspector walkthrough are pending. The computer-control tool reported the Mac locked and automatic unlock unavailable. The previously running Slice 010 preview is left intact; the current executable has only command-line build/test validation. No native acceptance or updated app-bundle claim is made.

Hosted product check is pending. Audio listening remains parked. Broader platform, long-film, metadata-corpus and release qualification remain separate work. No merge or release authorization is inferred.
