# Decoded base-picture sample prerequisite

D129,2026-10-04. Separate DEVELOPMENT C artifact only. Product Swift sources,
default Preview, original reference and five frozen D097 objects are unchanged.
No native sample/edited-picture admission, app action or UI walkthrough follows.

`Tools/DolbyPictureSamples/measure.h` checks concrete containing buffer extent,
positive byte stride, bounded plane and rectangle geometry, unaligned little-endian
10-bit sample loads, and canonical row hashes excluding padding. Count, extrema,
sum and square sum stay integer code-value facts. The 16,777,216 sample cap makes
maximum-value square sums fit UInt64. Full active-plane bounds are checked even
when the measured rectangle is smaller. Invalid samples do not yield output stats.

`samples.c` separately reuses the read-only reference decode subset and measures
progressive10-bit420 coded and codec-visible planes. It checks actual FFmpeg plane
buffer extents and even chroma-aligned crop edges. Each row records packet/frame/
raw-RPU observations, codec geometry and color declarations alongside six bounded
plane summaries. No pixel payload or added full-picture copy. Decoder/demuxer objects
settle before final path/descriptor observations and checked source close; SIGPIPE
becomes an ordinary output refusal. EOF/zero exit/parent join remain necessary.
No native parser, signed tool capability, resource/access caller or independent
sample/source coverage flag is provided. The old native metadata protocol is unchanged.

The installed-runtime generated suite passed five groups in4.958s. A separate build
against the previously qualified minimal LGPL FFmpeg9.0.2 macOS14 prefix passed
the same five groups in17.034s. Frozen relocated objects and original prefix libraries
were observed unchanged. The new retained probe has macOS14.0 minimum and the
three explicit original-prefix FFmpeg dependencies, not Homebrew dependencies.
Ordinary ad-hoc development loading only; not positive hardened or Developer ID trust.

Ten generated actual cases exercise B-frame reorder, BlockGroup, wider VINT,
conformance and open-GOP source variants across one/four decoder threads, four or
24 pictures. All three coded and codec-visible planes match a separate row-streaming
FFmpeg CLI oracle in dimensions/count/extrema/sum/squares/SHA256. The oracle shares
the FFmpeg decoder, not an independent codec implementation. Coded176x112 versus
codec-visible162x98 conformance samples differ; declared container crop/display is
not applied. Color declarations alone do not qualify transfer/range/chroma rendering.

Address/undefined sanitizer execution covers padded odd byte strides, unaligned data,
known ROI values, plane extent/overflow/outside/null/rectangle/stride refusals, unsupported
format/interlace/odd phase and a full maximum-size plane at code1023. Test allocations
are generated; the measurement core keeps only SHA state and finite results. This
does not establish total decoder memory, film performance or storage guarantees.

Two actual repeated-cluster probe executions acknowledge live/non-zombie sample
production. Owned group termination joins the direct child without a successful result;
same-content source-path substitution refuses after reading and direct child join.
Source hashes remain unchanged. Invalid arguments/nonregular/symlink/malformed
input, broken stdout and exclusive builder replacement refusal also pass. Test-only
Python owns generated finite processes/logs/deadlines; it is not an app runtime bridge
or universal escaped-descendant/physical-I/O cancellation guarantee.

The initial suite failed two default-CLI visible-plane comparisons and an access-time
comparison. CLI automatic cropping includes container crop, so the oracle now disables
it and selects only the explicit codec rectangle with exact aligned crop. Identity checks
exclude normal read access-time updates and keep device/inode/size/mtime/ctime/mode/
link observations plus generated content hashes. Initial logs remain private. Sanitizer
and other refusal checks had passed; no production protocol, historical assertion,
deadline or global concurrency policy was changed.

PR103 automatic37238461417 failed485reported tests in1341.912s with113issues:
57 unchanged60s,40 unchanged120s,one unchanged180s bounds and15 other issues.
Full log retained and PR updated without retry. Timing/phase/prelaunch causes remain
unknown under completed D090 investigation. No new historical observer or workaround.

Local ordinary regression:485reported tests/98suites in211.948s,30 unchanged opt-in
skips and one existing writer-surrogate child-settlement assertion failure at
CompanionWriterProcessTests.swift:204. Full log retained; no rerun, weakened assertion
or cause inferred. All new sample groups pass separately. Product sources are unchanged;
reuse D128's explicit optimized execution, with new current strict ad-hoc app/read-only
helper signature checks. Writer/decoder/sample probe remain absent from the bundle.
Owner source metadata/current journal, frozen objects, privacy and planning checks pass.

Remaining gates: actual native sample tool/protocol/source association, sample delivery
and resource/lease ownership, color/range/chroma qualification, user crop/resize and
edited statistics, EL reconstruction, stable archive/import/recovery, signing/packaging
and owner retention-mode review. Raw base-plane measurements establish none of
those. Original preservation, compatible Dolby conversion, edited-picture statistics,
enhancement reconstruction and companion archival remain separate choices.
