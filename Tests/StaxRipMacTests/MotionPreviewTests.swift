import Foundation
import Testing
@testable import StaxRipMac

struct MotionPreviewTests {
    private func config() -> EncodeConfiguration {
        var c = EncodeConfiguration(); c.selectCodec("H.264"); c.resolution = "Original"
        c.cropTop = 0; c.cropBottom = 0; c.picture.cropLeft = 0; c.picture.cropRight = 0
        c.picture.start = 0; c.picture.end = 0; c.picture.deinterlace = "Off"
        return c
    }
    private func makeSource(_ root: URL, kind: String, rate: Int = 24) async throws -> URL {
        let tools = try #require(FFmpegTools.discover()), url = root.appendingPathComponent(kind == "fullrange" ? "source.mkv" : "source.mp4")
        var filters = [String]()
        if kind == "interlaced" { filters.append("tinterlace=mode=interleave_top") }
        if kind == "vfr" { filters.append("select=not(eq(mod(n\\,3)\\,1))") }
        filters.append("setparams=range=\(kind == "fullrange" ? "full" : "limited"):color_primaries=bt709:color_trc=bt709:colorspace=bt709")
        var args = ["-v", "error", "-nostdin", "-n", "-f", "lavfi", "-i", "testsrc2=size=322x182:rate=\(kind == "slow" ? "1/4" : String(rate)):duration=4"]
        if !filters.isEmpty { args += ["-vf", filters.joined(separator: ",")] }
        args += kind == "fullrange" ? ["-c:v", "ffv1"] : ["-c:v", "libx264", "-preset", "ultrafast"]
        args += ["-threads", "1", "-fps_mode", "passthrough", "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709", "-color_range", kind == "fullrange" ? "pc" : "tv", url.path]
        let result = try await ToolRunner().run(executable: tools.ffmpeg, arguments: args)
        try #require(result.status == 0)
        if kind == "rotated" {
            let rotated = root.appendingPathComponent("rotated.mp4")
            let copy = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-n", "-display_rotation:v:0", "90", "-i", url.path, "-c", "copy", rotated.path])
            try #require(copy.status == 0)
            return rotated
        }
        return url
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(1)), arguments: ["cfr", "vfr", "interlaced", "rotated", "fullrange"])
    func realMovieMatchesSourceFramesAndBounds(kind: String) async throws {
        let workspace = try MotionWorkspace.create()
        do {
            let source = try await makeSource(workspace.directory, kind: kind, rate: kind == "interlaced" ? 48 : 24), before = try Data(contentsOf: source)
            let tools = try #require(FFmpegTools.discover())
            if kind == "rotated" {
                let probe = try await MediaProbe.read(source, tools: tools)
                #expect(try SourceOrientation.read(#require(probe.video)).degrees == 90)
            }
            var c = config(); c.picture.deinterlace = kind == "rotated" ? "Off" : "All frames"; c.picture.cropLeft = 6; c.picture.cropRight = 8
            c.cropTop = 4; c.cropBottom = 6; c.resolution = "1280 × 720"
            let result = try await MotionPreview.render(source: source, configuration: c, time: 0.537, tools: tools, workspace: workspace)
            #expect(result.frames.count == (kind == "vfr" ? 48 : 72))
            #expect(result.bytes > 0 && result.bytes <= 64 * 1024 * 1024)
            #expect(try Data(contentsOf: source) == before)
            // An independent full source decode establishes completeness of the selected interval.
            let decoded = try await ToolRunner().run(executable: tools.ffprobe, arguments: ["-v", "error", "-show_frames", "-show_entries", "frame=pts:frame_side_data=", "-of", "json", source.path])
            let sourceProbe = try await MediaProbe.read(source, tools: tools)
            let base = try HDRFraction(sourceProbe.video?.time_base)
            let frames = try JSONDecoder().decode(MotionPreview.OutputFrames.self, from: decoded.stdout).frames.compactMap(\.pts)
                .map { PreviewStamp(pts: $0, base: base) }.filter { $0.seconds >= 0.537 && $0.seconds < 3.537 }
            #expect(frames.count == result.frames.count)
            #expect(zip(frames, result.frames).allSatisfy { $0.matches($1.stamp) })
            // Independent raw references exercise full temporal history and crop/fit,
            // without calling the renderer's graph builder. Lossy proxy tolerance is explicit.
            for filtered in [false, true] {
                let output = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-i", workspace.movie.path,
                    "-vf", "crop=640:360:\(filtered ? 640 : 0):0", "-frames:v", "1", "-pix_fmt", "yuv420p", "-f", "rawvideo", "pipe:1"])
                let upright = kind == "rotated" ? "transpose=cclock," : ""
                let temporal = kind == "rotated" ? "" : "bwdif=mode=send_frame:parity=auto:deint=all,"
                let operations = upright + (filtered ? temporal + "crop=iw-14:ih-10:6:4,scale=1280:720:force_original_aspect_ratio=decrease:force_divisible_by=2," : "")
                let referenceFilter = operations + "select=gte(t\\,0.537),colorspace=all=bt709:range=tv:format=yuv420p,scale=w='trunc(min(640,360*dar)/2)*2':h='trunc(min(360,640/dar)/2)*2',setsar=1,pad=640:360:(ow-iw)/2:(oh-ih)/2"
                let reference = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-noautorotate", "-i", source.path, "-vf", referenceFilter,
                    "-frames:v", "1", "-pix_fmt", "yuv420p", "-f", "rawvideo", "pipe:1"])
                try #require(output.status == 0 && reference.status == 0 && !output.truncated && !reference.truncated)
                try #require(output.stdout.count == 640 * 360 * 3 / 2 && reference.stdout.count == output.stdout.count)
                let mse = zip(output.stdout, reference.stdout).reduce(0.0) { sum, pair in
                    let difference = Double(pair.0) - Double(pair.1); return sum + difference * difference
                } / Double(output.stdout.count)
                let psnr = mse == 0 ? Double.infinity : 10 * log10(255 * 255 / mse)
                #expect(psnr >= 35, Comment(rawValue: "\(kind) \(filtered ? "filtered" : "original") proxy PSNR \(psnr) dB"))
            }
            try await workspace.remove()
        } catch { try? await workspace.remove(); throw error }
        #expect(!FileManager.default.fileExists(atPath: workspace.directory.path))
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(1)))
    func excessiveFramesAndEarlyTimeoutRefuseAndSettle() async throws {
        let workspace = try MotionWorkspace.create()
        do {
            let source = try await makeSource(workspace.directory, kind: "cfr", rate: 240), tools = try #require(FFmpegTools.discover())
            do {
                _ = try await MotionPreview.render(source: source, configuration: config(), time: 0, tools: tools, workspace: workspace)
                Issue.record("Expected 600-frame refusal")
            } catch { #expect(error.localizedDescription.contains("Motion frames exceed"), Comment(rawValue: error.localizedDescription)) }
            try await workspace.remove()
            let timed = try MotionWorkspace.create()
            do {
                let source = try await makeSource(timed.directory, kind: "cfr")
                await #expect(throws: (any Error).self) { try await MotionPreview.render(source: source, configuration: config(), time: 0, tools: tools, workspace: timed, timeout: 0.001) }
                try await timed.remove()
            } catch { try? await timed.remove(); throw error }
        } catch { try? await workspace.remove(); throw error }
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(1)))
    func actualRenderCancellationAndChangedSourceRefuse() async throws {
        let workspace = try MotionWorkspace.create(), tools = try #require(FFmpegTools.discover())
        do {
            let source = try await makeSource(workspace.directory, kind: "cfr", rate: 120)
            let (stream, signal) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
            let c = config()
            let task = Task {
                defer { signal.finish() }
                return try await MotionPreview.render(source: source, configuration: c, time: 0, tools: tools, workspace: workspace) {
                    if $0 == "Rendering motion frames…" { signal.yield(()) }
                }
            }
            defer { task.cancel(); signal.finish() }
            var began = false
            for await _ in stream { began = true; break }
            try #require(began)
            task.cancel()
            await #expect(throws: CancellationError.self) { try await task.value }
            try await workspace.remove()
        } catch { try? await workspace.remove(); throw error }
        let changed = try MotionWorkspace.create()
        do {
            let source = try await makeSource(changed.directory, kind: "cfr")
            let original = try Data(contentsOf: source)
            do {
                _ = try await MotionPreview.render(source: source, configuration: config(), time: 0, tools: tools, workspace: changed) {
                    if $0 == "Rechecking source identity…" { try? (original + Data([0])).write(to: source) }
                }
                Issue.record("Accepted changed source")
            } catch { #expect(error.localizedDescription.contains("source changed"), Comment(rawValue: error.localizedDescription)) }
            #expect(try Data(contentsOf: source) == original + Data([0]))
            try await changed.remove()
        } catch { try? await changed.remove(); throw error }
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(1)))
    func longFrameTailRefusesAndTrimEndClipsInterval() async throws {
        let workspace = try MotionWorkspace.create(), tools = try #require(FFmpegTools.discover())
        do {
            let source = try await makeSource(workspace.directory, kind: "slow")
            do {
                _ = try await MotionPreview.render(source: source, configuration: config(), time: 0, tools: tools, workspace: workspace)
                Issue.record("Accepted four-second frame tail")
            } catch { #expect(error.localizedDescription.contains("playback duration"), Comment(rawValue: error.localizedDescription)) }
            try await workspace.remove()
        } catch { try? await workspace.remove(); throw error }
        let trimmed = try MotionWorkspace.create()
        do {
            let source = try await makeSource(trimmed.directory, kind: "cfr")
            var c = config(); c.picture.start = 1; c.picture.end = 2
            let result = try await MotionPreview.render(source: source, configuration: c, time: 1.5, tools: tools, workspace: trimmed)
            #expect(result.end == 2 && result.frames.count == 12)
            #expect(result.frames.allSatisfy { $0.stamp.seconds >= 1.5 && $0.stamp.seconds < 2 })
            try await trimmed.remove()
        } catch { try? await trimmed.remove(); throw error }
    }

    private func metadata() -> String {
        MotionMetadata.names.map { name in
            "[showinfo@\(name) @ 0x1] config in time_base: 1/24, frame_rate: 24/1\n" + (0..<2).map { index in
                "[showinfo@\(name) @ 0x1] n: \(index) pts: \(index + 24) pts_time:1 fmt:yuv420p sar:1/1 s:640x360 i:P iskey:0 type:P \n" +
                "[showinfo@\(name) @ 0x1] color_range:tv color_space:bt709 color_primaries:bt709 color_trc:bt709\n"
            }.joined()
        }.joined()
    }
    @Test func incrementalMetadataAndRefusalControls() throws {
        let data = Data(metadata().utf8)
        for size in [1, 2, 17, 4096, data.count] {
            var parser = MotionMetadata()
            for start in stride(from: 0, to: data.count, by: size) { try parser.accept(data.subdata(in: start..<min(start + size, data.count))) }
            try parser.finish(); #expect(try parser.verify(time: 1, end: 2, range: "tv").count == 2)
        }
        for altered in [metadata().replacingOccurrences(of: "n: 1 pts: 25", with: "n: 1 pts: 24"),
                        metadata().replacingOccurrences(of: "n: 1 pts: 25", with: "n: 2 pts: 25"),
                        metadata().replacingOccurrences(of: "color_primaries:bt709", with: "color_primaries:unknown"),
                        metadata().replacingOccurrences(of: "color_range:tv", with: "color_range:pc"),
                        String(metadata().dropLast()), String(repeating: "x", count: 16_385),
                        metadata().replacingOccurrences(of: "originalfit", with: "wrongfit"),
                        metadata().replacingOccurrences(of: "s:640x360", with: "s:3840x3840")] {
            #expect(throws: (any Error).self) {
                var parser = MotionMetadata(); try parser.accept(Data(altered.utf8)); try parser.finish()
                _ = try parser.verify(time: 1, end: 2, range: "tv")
            }
        }
        #expect(throws: (any Error).self) { var p = MotionMetadata(limit: 1); try p.accept(data) }
        var parser = MotionMetadata(); try parser.accept(data); try parser.finish()
        let frames = try parser.verify(time: 1, end: 2, range: "tv"), base = try HDRFraction("1/24")
        try MotionPreview.verifyTimes([0, 1], base: base, expected: frames)
        for values: [Int64?] in [[1, 2], [0], [0, 1, 2], [0, nil], [0, 0]] {
            #expect(throws: (any Error).self) { try MotionPreview.verifyTimes(values, base: base, expected: frames) }
        }
    }

    @Test(.timeLimit(.minutes(1))) func byteRefusalDrainsAndPreservesExistingFiles() async throws {
        for cap in [0, 1_000, 65_536] {
            let workspace = try MotionWorkspace.create()
            do {
                let runner = ToolRunner(), sink = try MotionFileSink(url: workspace.movie, limit: cap)
                let script = "BEGIN { s=\"A\"; for(i=0;i<20;i++) s=s s; printf \"%s\",s; printf \"done\" > \"/dev/stderr\" }"
                do { _ = try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/awk"), arguments: [script], stdoutLimit: 0, onOutput: { sink.accept($0, runner: runner) }); Issue.record("Expected byte refusal") }
                catch { #expect(sink.failure != nil) }
                try sink.close()
                let protected = try Data(contentsOf: workspace.movie)
                #expect(protected.count <= cap && protected.count == sink.count)
                #expect(throws: (any Error).self) { _ = try MotionFileSink(url: workspace.movie) }
                #expect(try Data(contentsOf: workspace.movie) == protected)
                try await workspace.remove()
            } catch { try? await workspace.remove(); throw error }
        }
    }
}
