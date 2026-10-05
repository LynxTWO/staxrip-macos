import Foundation
import CryptoKit
import Testing
@testable import StaxRipMac

struct DolbyCopyTimingTests {
    private let hash = "SHA256:" + String(repeating: "ab", count: 32)
    private func line(_ pts: Int64, _ dts: Int64, duration: Int64 = 41, bytes: Int64 = 9) -> String {
        "pts=\(pts)|dts=\(dts)|duration=\(duration)|size=\(bytes)|data_hash=\(hash)\n"
    }
    private func receipt(_ text: String, chunk: Int = 7, limit: Int = 2_000_000) throws -> DolbyCopyTiming.Receipt {
        let stream = try DolbyCopyTiming.Stream(timeBase: HDRFraction("1/1000"), limit: limit)
        let data = Data(text.utf8)
        for start in stride(from: 0, to: data.count, by: chunk) { stream.accept(data.subdata(in: start..<min(start + chunk, data.count))) }
        #expect(stream.peakLineBytes <= 512)
        return try stream.finish()
    }
    @Test func exactSignedTimingPreservesDuplicatesOrderAndDTS() throws {
        let records = line(42, -42) + line(0, -1) + line(42, 0)
        let a = try receipt(records)
        #expect(a == (try receipt(records, chunk: 1)))
        #expect(a.packets == 3)
        try a.requireSameTiming(as: receipt(records.replacingOccurrences(of: "size=9", with: "size=8")))
        #expect(a.packetSequence != (try receipt(records.replacingOccurrences(of: "size=9", with: "size=8"))).packetSequence)
        for changed in [line(0, -1) + line(42, -42) + line(42, 0), records.replacingOccurrences(of: "dts=-1", with: "dts=0"), records.replacingOccurrences(of: "duration=41", with: "duration=42"), line(42, -42)] {
            #expect(throws: NativeExportError.self) { try a.requireSameTiming(as: receipt(changed)) }
        }
        let extremes = try receipt(line(Int64.min, Int64.max) + line(Int64.max, Int64.min))
        #expect(extremes.packets == 2)
        // Independently assemble the native packet binding, excluding DTS: native
        // Matroska observations must never manufacture an absent decode timestamp.
        var sequence = SHA256()
        sequence.update(data: Data("DOLBY-COPY-PACKETS-1\0".utf8))
        for (index, pts) in [Int64(42), 0, 42].enumerated() {
            for value in [Int64(index), pts, 9] {
                let bits = UInt64(bitPattern: value)
                sequence.update(data: Data((0..<8).map { UInt8(truncatingIfNeeded: bits >> ($0 * 8)) }))
            }
            sequence.update(data: Data(repeating: 0xab, count: 32))
        }
        #expect(a.packetSequence == Data(sequence.finalize()))
    }
    @Test func malformedMissingTruncatedAndBoundedStreamsRefuse() throws {
        let good = line(0, 0)
        for bad in ["", String(good.dropLast()), "\n", good + "\n", good.replacingOccurrences(of: "dts=0", with: "dts=N/A"), good.replacingOccurrences(of: "dts=0|", with: ""), good.replacingOccurrences(of: "dts=0", with: "dts=0|dts=1"), good.replacingOccurrences(of: "duration=41", with: "duration=0"), good.replacingOccurrences(of: "size=9", with: "size=16777217"), good.replacingOccurrences(of: "pts=0", with: "pts=9223372036854775808"), good + "unknown=1\n", String(repeating: "x", count: 513)] {
            #expect(throws: NativeExportError.self) { _ = try receipt(bad) }
        }
        #expect(throws: NativeExportError.self) { _ = try receipt(good + good, limit: 1) }
    }
    @Test func joinedHelperFailuresAndParserCauseCannotHideReaderUncertainty() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("dolby-timing-surrogate-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        print("GENERATED_DOLBY_TIMING_REVIEW \(root.path)")
        let tool = root.appendingPathComponent("probe")
        // Controlled generated executable, not qualification of FFprobe admission.
        try Data("#!/bin/sh\nprintf 'malformed\\n'\nexit 7\n".utf8).write(to: tool, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tool.path)
        let tools = FFmpegTools(ffmpeg: tool, ffprobe: tool)
        let timeBase = try HDRFraction("1/1000")
        await #expect(throws: NativeExportError.self) {
            _ = try await DolbyCopyTiming.read(root.appendingPathComponent("unused"), stream: 0, timeBase: timeBase, tools: tools)
        }
        do {
            _ = try await ToolRunner.$readerCloseReport.withValue({ _, succeeded in
                #expect(succeeded); return true
            }) { try await DolbyCopyTiming.read(root.appendingPathComponent("unused"), stream: 0, timeBase: timeBase, tools: tools) }
            Issue.record("Expected uncertainty before parser refusal")
        } catch let error as ToolRunner.ReaderCloseFailure {
            #expect(error.roles == ["stderr", "stdout"])
            #expect(error.consumerCause is NativeExportError)
            #expect(error.owner.retainsUncertainty)
        }
    }

    @Test func actualGeneratedHEVCCopyHasExactJoinedTimingAndReportedCloseRefuses() async throws {
        let tools = try #require(FFmpegTools.discover())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("dolby-copy-timing-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        // Reported/unknown ownership keeps this generated root; no recovery authority.
        print("GENERATED_DOLBY_TIMING_REVIEW \(root.path)")
        let source = root.appendingPathComponent("source.mkv"), output = root.appendingPathComponent("copy.mkv")
        let elementary = root.appendingPathComponent("base.hevc")
        let made = try await ToolRunner(checkedReaders: true).run(executable: tools.ffmpeg, arguments: [
            "-v", "error", "-nostdin", "-n", "-f", "lavfi", "-i", "nullsrc=s=3840x2160:r=24000/1001,format=yuv420p10le,geq=lum=64+800*X/W:cb=512:cr=512",
            "-frames:v", "8", "-an", "-c:v", "libx265", "-preset", "ultrafast", "-pix_fmt", "yuv420p10le",
            "-x265-params", "pools=2:frame-threads=1:bframes=0:log-level=error:repeat-headers=1:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:range=limited", "-color_primaries", "bt2020",
            "-color_trc", "smpte2084", "-colorspace", "bt2020nc", "-f", "hevc", elementary.path])
        #expect(made.status == 0)
        let muxed = try await ToolRunner(checkedReaders: true).run(executable: tools.ffmpeg, arguments: [
            "-v", "error", "-nostdin", "-n", "-framerate", "24000/1001", "-i", elementary.path,
            "-map", "0:v:0", "-c:v", "copy", "-an", "-strict", "-2", source.path])
        #expect(muxed.status == 0)
        let copied = try await ToolRunner(checkedReaders: true).run(executable: tools.ffmpeg, arguments: ["-v", "error", "-nostdin", "-n", "-i", source.path, "-map", "0:v:0", "-c:v", "copy", output.path])
        #expect(copied.status == 0)
        let original = try await SourceFingerprint.read(source)
        let sourceProbe = try await MediaProbe.read(source, tools: tools, checkedReaders: true)
        let outputProbe = try await MediaProbe.read(output, tools: tools, checkedReaders: true)
        let sourceStream = try #require(sourceProbe.video), outputStream = try #require(outputProbe.video)
        #expect(sourceStream.width == 3840 && sourceStream.height == 2160)
        #expect(sourceStream.profile == "Main 10" && sourceStream.pix_fmt == "yuv420p10le")
        #expect(sourceStream.avg_frame_rate == "24000/1001" && sourceStream.color_transfer == "smpte2084")
        #expect(sourceStream.color_primaries == "bt2020" && sourceStream.color_space == "bt2020nc")
        let timeBase = try HDRFraction(sourceStream.time_base)
        let outputTimeBase = try HDRFraction(outputStream.time_base)
        let a = try await DolbyCopyTiming.read(source, stream: sourceStream.index, timeBase: timeBase, tools: tools)
        let b = try await DolbyCopyTiming.read(output, stream: outputStream.index, timeBase: outputTimeBase, tools: tools)
        try a.requireSameTiming(as: b)
        #expect(a.packets == 8 && a.packetSequence == b.packetSequence)
        do {
            _ = try await ToolRunner.$readerCloseReport.withValue({ role, succeeded in
                #expect(succeeded); return role == "stdout"
            }) { try await DolbyCopyTiming.read(source, stream: 0, timeBase: timeBase, tools: tools) }
            Issue.record("Expected reader uncertainty")
        } catch let error as ToolRunner.ReaderCloseFailure {
            #expect(error.roles == ["stdout"] && error.owner.retainsUncertainty)
        }
        #expect(try await SourceFingerprint.read(source) == original)
    }
}
