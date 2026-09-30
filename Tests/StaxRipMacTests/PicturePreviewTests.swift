import Foundation
import Testing
import Darwin
@testable import StaxRipMac

@Suite(.serialized)
@MainActor
struct PicturePreviewTests {
    private func folder() throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("picture-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: false)
        return u
    }
    private func fixture(_ url: URL, tools: FFmpegTools, interlaced: Bool = false, size: String = "160x96", duration: String = "2", range: String = "limited") async throws {
        let filters = (interlaced ? "tinterlace=mode=interleave_top," : "") + "setparams=range=\(range):color_primaries=bt709:color_trc=bt709:colorspace=bt709"
        let r = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-n", "-f", "lavfi", "-i", "testsrc2=size=\(size):rate=\(interlaced ? "48000/1001" : "24000/1001"):duration=\(duration)", "-vf", filters, "-c:v", "ffv1", url.path])
        try #require(r.status == 0)
    }
    private func config() -> EncodeConfiguration {
        var c = EncodeConfiguration(); c.codec = "H.264"; c.encoder = "x264"; c.audio = "No audio"; c.subtitleMode = "Remove all subtitles"
        return c
    }

    @Test func sharedPlanRetainsQueueArguments() async throws {
        let tools = try #require(FFmpegTools.discover()), dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("source.mkv"); try await fixture(src, tools: tools)
        let probe = try await MediaProbe.read(src, tools: tools)
        var c = config()
        #expect(PicturePlan(c).filters.isEmpty)
        c.picture.cropLeft = 2; c.picture.cropRight = 6; c.cropTop = 2; c.cropBottom = 2
        c.picture.deinterlace = "All frames"; c.resolution = "1280 × 720"
        let expected = "bwdif=mode=send_frame:parity=auto:deint=all,crop=iw-8:ih-4:2:2,scale=1280:720:force_original_aspect_ratio=decrease:force_divisible_by=2"
        #expect(PicturePlan(c).expression == expected)
        let job = QueueJob(id: UUID(), source: src.path, isDemo: false, destination: dir.appendingPathComponent("out.mkv").path, configuration: c, created: Date())
        let plan = try EncodePlan.make(job: job, probe: probe, encoders: ["libx264"], staged: dir.appendingPathComponent("stage.mkv"))
        let index = try #require(plan.arguments.firstIndex(of: "-vf"))
        #expect(plan.arguments[index + 1] == expected)
    }

    @Test func temporalFramesMatchFullRenderAtEdgesAndInterior() async throws {
        let tools = try #require(FFmpegTools.discover()), dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("interlaced.mkv"); try await fixture(src, tools: tools, interlaced: true)
        let originalHash = try await SourceFingerprint.read(src)
        var c = config(); c.picture.deinterlace = "All frames"; c.picture.cropLeft = 2; c.picture.cropRight = 6; c.cropTop = 2; c.cropBottom = 2
        // Independent full render, no select and no production PicturePlan.
        let reference = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-i", src.path, "-vf", "bwdif=mode=send_frame:parity=auto:deint=all,crop=152:92:2:2,colorspace=all=bt709:trc=iec61966-2-1:range=pc:format=yuv444p,format=rgb24", "-fps_mode", "passthrough", "-f", "rawvideo", "pipe:1"])
        try #require(reference.status == 0 && !reference.truncated)
        for (request, index) in [(0.0, 0), (0.4, 10), (1.95, 47)] {
            let r = try await PicturePreview.render(source: src, configuration: c, time: request, tools: tools)
            #expect(r.original.stamp.matches(r.filtered.stamp))
            #expect(r.filtered.width == 152 && r.filtered.height == 92)
            let size = 152 * 92 * 3
            #expect(r.filtered.rgb == reference.stdout.subdata(in: index * size..<(index + 1) * size))
            #expect(r.filtered.image != nil)
        }
        #expect(try await SourceFingerprint.read(src) == originalHash)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["interlaced.mkv"])
    }

    @Test func noOpResizeFullRangeAndTrimBounds() async throws {
        let tools = try #require(FFmpegTools.discover()), dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("full-range.mkv"); try await fixture(src, tools: tools, range: "full")
        var c = config()
        let noOp = try await PicturePreview.render(source: src, configuration: c, time: 0.1, tools: tools)
        #expect(noOp.original.rgb == noOp.filtered.rgb)
        c.resolution = "1280 × 720"
        let resized = try await PicturePreview.render(source: src, configuration: c, time: 0.1, tools: tools)
        #expect(resized.filtered.width <= 1280 && resized.filtered.height <= 720)
        #expect(resized.filtered.width > resized.original.width)
        c.picture.start = 0.4; c.picture.end = 0.41
        await #expect(throws: (any Error).self) { try await PicturePreview.render(source: src, configuration: c, time: 0.4, tools: tools) }
        await #expect(throws: (any Error).self) { try await PicturePreview.render(source: src, configuration: c, time: 0.2, tools: tools) }
    }

    @Test func sourceMetadataAndBadCropFailWithPreviewSpecificReason() throws {
        let fields: [String: Any] = ["index": 0, "codec_type": "video", "pix_fmt": "yuv420p", "width": 160, "height": 96, "color_primaries": "bt709", "color_transfer": "bt709", "color_space": "bt709", "color_range": "tv", "sample_aspect_ratio": "1:1", "start_pts": 0, "time_base": "1/1000"]
        func probe(_ override: [String: Any]) throws -> MediaProbe {
            let f = fields.merging(override) { _, b in b }
            return try JSONDecoder().decode(MediaProbe.self, from: JSONSerialization.data(withJSONObject: ["streams": [f], "format": ["duration": "2"]]))
        }
        for bad: [String: Any] in [["color_transfer": "unknown"], ["color_transfer": "smpte2084"], ["color_range": "unknown"], ["sample_aspect_ratio": "4:3"], ["start_pts": 1], ["width": 9000], ["tags": ["rotate": "90"]], ["time_base": "0/0"]] {
            #expect(throws: (any Error).self) { try PicturePreview.validate(config(), probe: probe(bad), time: 0) }
        }
        var bad = config(); bad.picture.cropRight = 160
        #expect(throws: (any Error).self) { try PicturePreview.validate(bad, probe: probe([:]), time: 0) }
        #expect(throws: (any Error).self) { try PicturePreview.validate(config(), probe: probe([:]), time: .nan) }
        #expect(throws: (any Error).self) { try PicturePreview.validate(config(), probe: probe([:]), time: 2) }
    }

    @Test func cancellationTimeoutAndChangedSourceDoNotLeaveArtifacts() async throws {
        let tools = try #require(FFmpegTools.discover()), dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("cancel.mkv"); try await fixture(src, tools: tools, size: "640x360", duration: "8")
        let fingerprint = try await SourceFingerprint.read(src)
        let c = config()
        let task = Task { try await PicturePreview.render(source: src, configuration: c, time: 7, tools: tools) }
        try await Task.sleep(nanoseconds: 10_000_000)
        let start = Date(); task.cancel()
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(Date().timeIntervalSince(start) < 5)
        await #expect(throws: (any Error).self) { try await PicturePreview.render(source: src, configuration: c, time: 7, tools: tools, timeout: 0.001) }
        #expect(try await SourceFingerprint.read(src) == fingerprint)
        await #expect(throws: (any Error).self) {
            try await PicturePreview.render(source: src, configuration: c, time: 0, tools: tools) { message in
                if message == "Rechecking source identity…", let h = try? FileHandle(forWritingTo: src) {
                    _ = try? h.seekToEnd(); try? h.write(contentsOf: Data([0])); try? h.close()
                }
            }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["cancel.mkv"])
    }

    @Test func malformedIncompleteAndWrongFrameMetadataRefuses() throws {
        #expect(throws: (any Error).self) { try PicturePreview.parse(data: Data(), log: "", expectedRange: "tv", time: 0, end: 1) }
        let log = """
        [showinfo@identity @ 0x1] config in time_base: 1/1000, frame_rate: 24/1
        [showinfo@identity @ 0x1] n:   0 pts: 0 pts_time:0 duration: 41 fmt:yuv420p cl:left sar:1/1 s:2x2 i:P
        [showinfo@identity @ 0x1] color_range:tv color_space:bt709 color_primaries:bt709 color_trc:bt709
        [showinfo@display @ 0x2] config in time_base: 1/1000, frame_rate: 24/1
        [showinfo@display @ 0x2] n:   0 pts: 0 pts_time:0 duration: 41 fmt:rgb24 cl:left sar:1/1 s:2x2 i:P
        [showinfo@display @ 0x2] color_range:pc color_space:gbr color_primaries:bt709 color_trc:iec61966-2-1
        """
        let frame = try PicturePreview.parse(data: Data(repeating: 0, count: 12), log: log, expectedRange: "tv", time: 0, end: 1)
        #expect(frame.width == 2)
        let colorLine = "[showinfo@identity @ 0x1] color_range:tv color_space:bt709 color_primaries:bt709 color_trc:bt709"
        let sideData = log.replacingOccurrences(of: colorLine, with: "[showinfo@identity @ 0x1] side data - synthetic SEI\n" + colorLine)
        _ = try PicturePreview.parse(data: Data(repeating: 0, count: 12), log: sideData, expectedRange: "tv", time: 0, end: 1)
        let nextFrame = "[showinfo@identity @ 0x1] n: 1 pts: 1 pts_time:0.001 fmt:yuv420p sar:1/1 s:2x2 "
        for invalid in [log.replacingOccurrences(of: colorLine, with: colorLine + "\n" + colorLine),
                        log.replacingOccurrences(of: colorLine, with: nextFrame + "\n" + colorLine)] {
            #expect(throws: (any Error).self) { try PicturePreview.parse(data: Data(repeating: 0, count: 12), log: invalid, expectedRange: "tv", time: 0, end: 1) }
        }
        #expect(throws: (any Error).self) { try PicturePreview.parse(data: Data(repeating: 0, count: 11), log: log, expectedRange: "tv", time: 0, end: 1) }
        for broken in [log + "\n" + log, log.replacingOccurrences(of: "2x2", with: "999999x999999"), log.replacingOccurrences(of: "color_trc:bt709", with: "color_trc:unknown"), log.replacingOccurrences(of: "1/1000", with: "0/0")] {
            #expect(throws: (any Error).self) { try PicturePreview.parse(data: Data(repeating: 0, count: 12), log: broken, expectedRange: "tv", time: 0, end: 1) }
        }
    }

    @Test func controllerInvalidatesAndRejectsLateCompletion() async throws {
        let tools = try #require(FFmpegTools.discover()), dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("controller.mkv"); try await fixture(src, tools: tools)
        let controller = PicturePreviewController()
        controller.render(source: src, configuration: config(), time: 0, tools: tools)
        controller.invalidate()
        for _ in 0..<500 where controller.running { try await Task.sleep(nanoseconds: 10_000_000) }
        #expect(!controller.running && controller.result == nil)
        controller.render(source: src, configuration: config(), time: 0, tools: tools)
        for _ in 0..<500 where controller.running { try await Task.sleep(nanoseconds: 10_000_000) }
        try #require(controller.result != nil)
        controller.invalidate(); #expect(controller.stale)
        controller.close(); #expect(controller.result == nil && !controller.stale && !controller.status.contains("Cancelling"))
        controller.render(source: src, configuration: config(), time: 0, tools: nil)
        #expect(controller.status.contains("required"))
    }

    @Test func oversizedAndNonzeroDecoderOutputFailClosed() async throws {
        let tools = try #require(FFmpegTools.discover()), dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("source.mkv"); try await fixture(src, tools: tools)
        let stream = try #require(try await MediaProbe.read(src, tools: tools).video)
        for command in ["printf partial; exit 3", "/bin/dd if=/dev/zero bs=1048576 count=26 2>/dev/null"] {
            let script = dir.appendingPathComponent("decoder")
            try ("#!/bin/sh\n" + command + "\n").write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            let fake = FFmpegTools(ffmpeg: script, ffprobe: tools.ffprobe)
            await #expect(throws: (any Error).self) {
                try await PicturePreview.frame(source: src, stream: stream, filters: [], time: 0, end: 2, tools: fake)
            }
        }
    }

    @Test func limitedBlackAndWhiteBecomeSRGBEndpoints() async throws {
        let tools = try #require(FFmpegTools.discover()), dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("levels.mkv")
        let r = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-n", "-f", "lavfi", "-i", "nullsrc=size=6x2:rate=24:duration=0.1", "-vf", "geq=lum='if(lt(X,2),16,if(lt(X,4),126,235))':cb=128:cr=128,setparams=range=limited:color_primaries=bt709:color_trc=bt709:colorspace=bt709", "-c:v", "ffv1", src.path])
        try #require(r.status == 0)
        let result = try await PicturePreview.render(source: src, configuration: config(), time: 0, tools: tools)
        let bytes = Array(result.original.rgb)
        for channel in 0..<3 {
            #expect(bytes[channel] <= 1)
            #expect(bytes[12 + channel] >= 254)
            // BT.709 inverse transfer then sRGB encoding predicts about 140.
            #expect((137...143).contains(Int(bytes[6 + channel])))
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["STAXRIP_PREVIEW_RESOURCE"] == "1"))
    func bounded4KPair() async throws {
        let tools = try #require(FFmpegTools.discover()), dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("4k.mkv"); try await fixture(src, tools: tools, size: "3840x2160", duration: "0.05")
        let result = try await PicturePreview.render(source: src, configuration: config(), time: 0, tools: tools)
        let bytes = result.original.rgb.count + result.filtered.rgb.count
        #expect(bytes == 49_766_400)
        #expect(bytes < 128 * 1024 * 1024)
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        print("PICTURE_RESOURCE pair_bytes=\(bytes) helper_peak_rss=\(usage.ru_maxrss)")
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["4k.mkv"])
    }
}
