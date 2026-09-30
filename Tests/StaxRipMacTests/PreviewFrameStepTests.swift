import Foundation
import Testing
import Darwin
@testable import StaxRipMac

@MainActor
struct PreviewFrameStepTests {
    private func stamp(_ pts: Int64, base: String = "1/1000") throws -> PreviewStamp {
        PreviewStamp(pts: pts, base: try HDRFraction(base))
    }
    @Test func streamingNeighborsUseRationalAnchorsAndTrimBoundaries() throws {
        let data = Data("frame|pts=0|\nframe|pts=208\nframe|pts=375\nframe|pts=583\nframe|pts=875\n".utf8)
        for direction in [PreviewStepDirection.previous, .next] {
            var scanner = try PreviewNeighborScanner(anchor: stamp(750, base: "1/2000"), base: HDRFraction("1/1000"), direction: direction, start: 0, end: 1)
            for byte in data { try scanner.accept(Data([byte])) }
            try scanner.finish()
            #expect(scanner.finished)
            #expect(scanner.neighbor?.pts == (direction == .previous ? 208 : 583))
        }
        var first = try PreviewNeighborScanner(anchor: stamp(375), base: HDRFraction("1/1000"), direction: .previous, start: 0.3, end: 0.6)
        try first.accept(data); try first.finish(); #expect(first.neighbor == nil)
        var last = try PreviewNeighborScanner(anchor: stamp(583), base: HDRFraction("1/1000"), direction: .next, start: 0, end: 0.6)
        try last.accept(data); try last.finish(); #expect(last.neighbor == nil)
        var eof = try PreviewNeighborScanner(anchor: stamp(875), base: HDRFraction("1/1000"), direction: .next, start: 0, end: 1)
        try eof.accept(data); try eof.finish(); #expect(eof.neighbor == nil)
    }
    @Test func invalidTimestampEvidenceRefusesWithinBounds() throws {
        for text in ["frame|pts=N/A\n", "frame|pts=-1\n", "frame|pts=+1\n", "frame|pts=1.0\n", "frame|pts=1000000000001\n", "frame|pts=0|pts=1\n", "frame|pts=0\nframe|pts=0\n", "frame|pts=42\nframe|pts=20\n", "packet|pts=0\n", String(repeating: "x", count: 257)] {
            var scanner = try PreviewNeighborScanner(anchor: stamp(100), base: HDRFraction("1/1000"), direction: .next, start: 0, end: 1)
            #expect(throws: (any Error).self) { try scanner.accept(Data(text.utf8)); try scanner.finish() }
        }
        var missing = try PreviewNeighborScanner(anchor: stamp(100), base: HDRFraction("1/1000"), direction: .next, start: 0, end: 1)
        try missing.accept(Data("frame|pts=0\n".utf8))
        #expect(throws: (any Error).self) { try missing.finish() }
        var passed = try PreviewNeighborScanner(anchor: stamp(100), base: HDRFraction("1/1000"), direction: .next, start: 0, end: 1)
        #expect(throws: (any Error).self) { try passed.accept(Data("frame|pts=0\nframe|pts=101\n".utf8)) }
        var capped = try PreviewNeighborScanner(anchor: stamp(100), base: HDRFraction("1/1000"), direction: .next, start: 0, end: 1, frameLimit: 1)
        #expect(throws: (any Error).self) { try capped.accept(Data("frame|pts=0\nframe|pts=100\n".utf8)) }
        var invalidUTF8 = try PreviewNeighborScanner(anchor: stamp(100), base: HDRFraction("1/1000"), direction: .next, start: 0, end: 1)
        #expect(throws: (any Error).self) { try invalidUTF8.accept(Data([255, 10])) }
        for (start, end) in [(Double.nan, 1.0), (0, Double.infinity), (-1, 1), (1, 0), (0.1, 1)] {
            #expect(throws: (any Error).self) { try PreviewNeighborScanner(anchor: stamp(0), base: HDRFraction("1/1000"), direction: .next, start: start, end: end) }
        }
    }
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("frame-step-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false); return root
    }
    private func config() -> EncodeConfiguration {
        var c = EncodeConfiguration(); c.selectCodec("H.264"); c.audio = "No audio"; c.subtitleMode = "Remove all subtitles"
        return c
    }
    private func fixture(_ root: URL, tools: FFmpegTools, vfr: Bool) async throws -> URL {
        let source = root.appendingPathComponent(vfr ? "vfr.mkv" : "fractional.mp4")
        let filters = (vfr ? "setpts='if(lt(N,6),N,if(lt(N,12),N+3,N+9))/(24*TB)'," : "") + "setparams=range=limited:color_primaries=bt709:color_trc=bt709:colorspace=bt709"
        let result = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-n", "-f", "lavfi", "-i", "testsrc2=size=160x96:rate=\(vfr ? "24" : "24000/1001"):duration=1", "-vf", filters, "-fps_mode", "passthrough", "-c:v", vfr ? "ffv1" : "libx264", source.path])
        try #require(result.status == 0); return source
    }
    private func comparison(_ outcome: PicturePreview.StepResult) throws -> PictureComparison {
        guard case .comparison(let result) = outcome else { throw PicturePreview.failure("Expected an adjacent comparison in this fixture") }
        return result
    }
    private func boundary(_ outcome: PicturePreview.StepResult) -> Bool {
        if case .boundary = outcome { return true }; return false
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(2)), arguments: [false, true])
    func vfrStepsMatchIndependentFullRenderAcrossGaps(deinterlace: Bool) async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let tools = try #require(FFmpegTools.discover()), source = try await fixture(root, tools: tools, vfr: true)
        let identity = try await SourceFingerprint.read(source)
        var c = config(); c.picture.cropLeft = 2; c.picture.cropRight = 6; c.cropTop = 2; c.cropBottom = 2
        if deinterlace { c.picture.deinterlace = "All frames" }
        let fullFilter = (deinterlace ? "bwdif=mode=send_frame:parity=auto:deint=all," : "") + "crop=152:92:2:2,colorspace=all=bt709:trc=iec61966-2-1:range=pc:format=yuv444p,format=rgb24"
        let reference = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-i", source.path, "-vf", fullFilter, "-fps_mode", "passthrough", "-f", "rawvideo", "pipe:1"])
        try #require(reference.status == 0 && !reference.truncated)
        let size = 152 * 92 * 3
        for (anchorPTS, direction, expectedPTS, index) in [(Int64(208), PreviewStepDirection.next, Int64(375), 6), (375, .previous, 208, 5), (583, .next, 875, 12), (875, .previous, 583, 11)] {
            let result = try comparison(try await PicturePreview.step(source: source, configuration: c, anchor: stamp(anchorPTS), expectedSource: identity, direction: direction, tools: tools))
            #expect(result.original.stamp.matches(try stamp(expectedPTS)))
            #expect(result.filtered.stamp.matches(try stamp(expectedPTS)))
            #expect(result.filtered.rgb == reference.stdout.subdata(in: index * size..<(index + 1) * size))
            #expect(result.sourceIdentity == identity)
        }
        #expect(try await SourceFingerprint.read(source) == identity)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == [source.lastPathComponent])
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(1)))
    func fractionalCadenceAndTrimEdgesUseActualFrames() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let tools = try #require(FFmpegTools.discover()), source = try await fixture(root, tools: tools, vfr: false)
        var c = config()
        let first = try await PicturePreview.render(source: source, configuration: c, time: 0, tools: tools)
        let next = try comparison(try await PicturePreview.step(source: source, configuration: c, anchor: first.original.stamp, expectedSource: first.sourceIdentity, direction: .next, tools: tools))
        #expect(next.original.stamp.matches(try stamp(1001, base: "1/24000")))
        let back = try comparison(try await PicturePreview.step(source: source, configuration: c, anchor: next.original.stamp, expectedSource: first.sourceIdentity, direction: .previous, tools: tools))
        #expect(back.original.rgb == first.original.rgb)
        #expect(boundary(try await PicturePreview.step(source: source, configuration: c, anchor: back.original.stamp, expectedSource: first.sourceIdentity, direction: .previous, tools: tools)))
        c.picture.start = 0.03; c.picture.end = 0.08
        #expect(boundary(try await PicturePreview.step(source: source, configuration: c, anchor: next.original.stamp, expectedSource: first.sourceIdentity, direction: .previous, tools: tools)))
        #expect(boundary(try await PicturePreview.step(source: source, configuration: c, anchor: next.original.stamp, expectedSource: first.sourceIdentity, direction: .next, tools: tools)))
        c = config()
        let last = try await PicturePreview.render(source: source, configuration: c, time: 0.95, tools: tools)
        #expect(boundary(try await PicturePreview.step(source: source, configuration: c, anchor: last.original.stamp, expectedSource: first.sourceIdentity, direction: .next, tools: tools)))
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(1)))
    func missingAnchorChangedSourceAndWrongRenderedTimestampRefuse() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let tools = try #require(FFmpegTools.discover()), source = try await fixture(root, tools: tools, vfr: true)
        let identity = try await SourceFingerprint.read(source), c = config()
        await #expect(throws: (any Error).self) { try await PicturePreview.step(source: source, configuration: c, anchor: stamp(209), expectedSource: identity, direction: .next, tools: tools) }
        await #expect(throws: (any Error).self) {
            try await PicturePreview.render(source: source, configuration: c, time: 0, tools: tools, expectedSource: identity, requiredStamp: stamp(375))
        }
        await #expect(throws: (any Error).self) {
            try await PicturePreview.step(source: source, configuration: c, anchor: stamp(208), expectedSource: identity, direction: .next, tools: tools) { message in
                if message == "Reading decoded frame timestamps from the beginning…" {
                    if let handle = try? FileHandle(forWritingTo: source) {
                        _ = try? handle.seekToEnd(); try? handle.write(contentsOf: Data([0])); try? handle.close()
                    }
                }
            }
        }
        await #expect(throws: (any Error).self) { try await PicturePreview.step(source: source, configuration: c, anchor: stamp(208), expectedSource: identity, direction: .next, tools: tools) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == [source.lastPathComponent])
    }
    private func finish(_ controller: PicturePreviewController) async throws {
        do { while controller.running { try await Task.sleep(for: .milliseconds(10)) } }
        catch { controller.cancel(); throw error }
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(2)))
    func controllerKeepsBoundaryImageAndRejectsStaleOrLateSteps() async throws {
        let root = try directory(); let controller = PicturePreviewController()
        defer {
            if controller.running { controller.cancel() }
            else { try? FileManager.default.removeItem(at: root) }
        }
        let tools = try #require(FFmpegTools.discover()), source = try await fixture(root, tools: tools, vfr: true)
        let c = config()
        #expect(!controller.canStepPrevious && !controller.canStepNext)
        controller.render(source: source, configuration: c, time: 0, tools: tools); try await finish(controller)
        let original = try #require(controller.result)
        #expect(controller.canStepNext && controller.canStepPrevious)
        controller.step(source: source, configuration: c, direction: .previous, tools: tools); try await finish(controller)
        #expect(controller.atFirstFrame && !controller.canStepPrevious && controller.canStepNext)
        #expect(controller.result?.original.rgb == original.original.rgb && !controller.stale)
        #expect(controller.status.contains("Current comparison retained"))
        controller.step(source: source, configuration: c, direction: .next, tools: tools); try await finish(controller)
        #expect(controller.result?.original.stamp.pts == 42)
        #expect(!controller.atFirstFrame && controller.canStepPrevious)
        var changed = c; changed.cropTop = 2
        controller.step(source: source, configuration: changed, direction: .next, tools: tools)
        #expect(controller.stale && !controller.running && !controller.canStepNext)
        #expect(controller.status.contains("Render a current comparison"))
        controller.render(source: source, configuration: c, time: 0, tools: tools); try await finish(controller)
        controller.step(source: source, configuration: c, direction: .next, tools: tools)
        controller.invalidate(); try await finish(controller)
        #expect(controller.stale && !controller.canStepNext)
        #expect(controller.result?.original.stamp.pts == 0)
        #expect(!controller.status.contains("Cancelling"))
        controller.render(source: source, configuration: c, time: 1.333, tools: tools); try await finish(controller)
        controller.step(source: source, configuration: c, direction: .next, tools: tools); try await finish(controller)
        #expect(controller.atLastFrame && !controller.canStepNext && controller.canStepPrevious)
        controller.close(); #expect(controller.result == nil && !controller.canStepPrevious)
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(2)))
    func cancelledAndTimedOutScannerSettlesBeforeReturning() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let tools = try #require(FFmpegTools.discover()), source = try await fixture(root, tools: tools, vfr: true)
        let identity = try await SourceFingerprint.read(source), c = config(), anchor = try stamp(0)
        func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let script = root.appendingPathComponent("probe"), pidFile = root.appendingPathComponent("scanner.pid")
        let body = "#!/bin/zsh\nif (( $@[(Ie)-show_frames] )); then\n print -r -- $$ > " + quote(pidFile.path) + "\n exec /bin/sleep 30\nfi\nexec " + quote(tools.ffprobe.path) + " \"$@\"\n"
        try Data(body.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let wrapped = FFmpegTools(ffmpeg: tools.ffmpeg, ffprobe: script)
        let task = Task { try await PicturePreview.step(source: source, configuration: c, anchor: anchor, expectedSource: identity, direction: .next, tools: wrapped) }
        do {
            while !FileManager.default.fileExists(atPath: pidFile.path) { try await Task.sleep(for: .milliseconds(10)) }
        } catch { task.cancel(); _ = try? await task.value; throw error }
        let pid = try #require(Int32(try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(kill(pid, 0) == -1 && errno == ESRCH)
        try FileManager.default.removeItem(at: pidFile)
        await #expect(throws: (any Error).self) {
            try await PicturePreview.step(source: source, configuration: c, anchor: anchor, expectedSource: identity, direction: .next, tools: wrapped, timeout: 0.2)
        }
        if FileManager.default.fileExists(atPath: pidFile.path) {
            let timedPID = try #require(Int32(try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
            #expect(kill(timedPID, 0) == -1 && errno == ESRCH)
        }
        #expect(try await SourceFingerprint.read(source) == identity)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".staxrip-") })
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(1)))
    func failedScannerCannotAuthorizeAReplacementImage() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let tools = try #require(FFmpegTools.discover()), source = try await fixture(root, tools: tools, vfr: true)
        let stream = try #require(try await MediaProbe.read(source, tools: tools).video)
        let script = root.appendingPathComponent("probe")
        for command in ["printf 'frame|pts=0\\n'; exit 3", "printf 'frame|pts=0\\nframe|pts=N/A\\n'", "printf 'frame|pts=0\\nframe|pts=0\\n'"] {
            try Data(("#!/bin/sh\n" + command + "\n").utf8).write(to: script)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            await #expect(throws: (any Error).self) {
                try await PreviewFrameNeighbor.read(source: source, stream: stream, anchor: stamp(0), direction: .next, start: 0, end: 1, tools: FFmpegTools(ffmpeg: tools.ffmpeg, ffprobe: script))
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["STAXRIP_FRAME_STEP_RESOURCE"] == "1"), .timeLimit(.minutes(2)))
    func bounded4KReplacementPair() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let tools = try #require(FFmpegTools.discover()), source = root.appendingPathComponent("4k.mkv")
        let encoded = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-n", "-f", "lavfi", "-i", "testsrc2=size=3840x2160:rate=24:duration=0.05", "-vf", "setparams=range=limited:color_primaries=bt709:color_trc=bt709:colorspace=bt709", "-c:v", "ffv1", source.path])
        try #require(encoded.status == 0)
        let first = try await PicturePreview.render(source: source, configuration: config(), time: 0, tools: tools)
        let next = try comparison(try await PicturePreview.step(source: source, configuration: config(), anchor: first.original.stamp, expectedSource: first.sourceIdentity, direction: .next, tools: tools))
        let bytes = first.original.rgb.count + first.filtered.rgb.count + next.original.rgb.count + next.filtered.rgb.count
        #expect(bytes == 99_532_800)
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        print("FRAME_STEP_RESOURCE two_pair_bytes=\(bytes) helper_peak_rss=\(usage.ru_maxrss)")
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == [source.lastPathComponent])
    }

}
