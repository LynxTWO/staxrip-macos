import Foundation
import Testing
@testable import StaxRipMac

@Suite(.serialized)
@MainActor
struct OrientationTests {
    private let matrices: [Int: [Int]] = [
        0: [65536,0,0,0,65536,0,0,0,1073741824],
        90: [0,-65536,0,65536,0,0,0,0,1073741824],
        180: [-65536,0,0,0,-65536,0,0,0,1073741824],
        270: [0,65536,0,-65536,0,0,0,0,1073741824]
    ]
    private func matrixText(_ values: [Int]) -> String {
        (0..<3).map { String(format: "%08d: %d %d %d", $0, values[$0*3], values[$0*3+1], values[$0*3+2]) }.joined(separator: "\n")
    }
    private func probe(angle: Int = 90, values: [Int]? = nil, overrides: [String: Any] = [:]) throws -> MediaProbe {
        let fields: [String: Any] = ["index": 1, "codec_type": "video", "codec_name": "h264", "width": 160, "height": 96,
            "pix_fmt": "yuv420p", "sample_aspect_ratio": "1:1", "field_order": "progressive", "start_pts": 0, "time_base": "1/1000",
            "color_primaries": "bt709", "color_transfer": "bt709", "color_space": "bt709", "color_range": "tv",
            "side_data_list": [["side_data_type": "Display Matrix", "rotation": angle, "displaymatrix": matrixText(values ?? matrices[angle]!)]]]
        return try JSONDecoder().decode(MediaProbe.self, from: JSONSerialization.data(withJSONObject: ["streams": [fields.merging(overrides) { _, b in b }], "format": ["duration": "1"]]))
    }
    private func configuration() -> EncodeConfiguration {
        var c = EncodeConfiguration(); c.selectCodec("H.264"); c.quality = 18; c.audio = "No audio"; c.subtitleMode = "Remove all subtitles"; return c
    }
    @Test func fullMatrixAndSourceContractRefuseAmbiguity() throws {
        for angle in [0,90,180,270] {
            #expect(try SourceOrientation.read(probe(angle: angle).video!).degrees == angle)
        }
        var mirrored = matrices[90]!; mirrored[3] = -65536
        var translated = matrices[90]!; translated[6] = 65536
        var perspective = matrices[90]!; perspective[2] = 1
        var scaled = matrices[90]!; scaled[1] = -32768
        for matrix in [mirrored, translated, perspective, scaled, matrices[180]!] {
            #expect(throws: (any Error).self) { try SourceOrientation.read(probe(values: matrix).video!) }
        }
        for bad: [String: Any] in [
            ["tags": ["rotate": "0"]], ["tags": ["rotate": "garbage"]],
            ["side_data_list": [["side_data_type": "Display Matrix", "rotation": 90]]],
            ["side_data_list": [["side_data_type": "Display Matrix", "rotation": 90, "displaymatrix": "malformed"]]],
            ["side_data_list": [], "tags": ["rotate": "90"]],
            ["side_data_list": [["side_data_type": "Other", "rotation": 90]]]
        ] { #expect(throws: (any Error).self) { try SourceOrientation.read(probe(overrides: bad).video!) } }
        let orientation = try SourceOrientation.read(probe().video!)
        for bad: [String: Any] in [["field_order": "tt"], ["sample_aspect_ratio": "4:3"], ["pix_fmt": "yuv420p10le"], ["color_transfer": "smpte2084"]] {
            #expect(throws: (any Error).self) { try orientation.validateTranscode(probe(overrides: bad).video!, configuration: configuration()) }
        }
        var c = configuration(); c.picture.deinterlace = "All frames"
        #expect(throws: (any Error).self) { try orientation.validateTranscode(probe().video!, configuration: c) }
        c = configuration(); c.picture.cropLeft = 96
        #expect(throws: (any Error).self) { try PicturePreview.validate(c, probe: probe(), time: 0) }
        let job = QueueJob(id: UUID(), source: "/generated/source.mp4", isDemo: false, destination: "/generated/out.mkv", configuration: c, created: Date())
        #expect(throws: (any Error).self) { try EncodePlan.make(job: job, probe: probe(), encoders: ["libx264"], staged: URL(fileURLWithPath: "/generated/stage.mkv")) }
        c.picture.cropLeft = 0
        var validJob = job; validJob.configuration = c
        let plan = try EncodePlan.make(job: validJob, probe: probe(), encoders: ["libx264"], staged: URL(fileURLWithPath: "/generated/stage.mkv"))
        let overrideIndex = try #require(plan.arguments.firstIndex(of: "-display_rotation:1"))
        #expect(plan.arguments[overrideIndex+1] == "0" && overrideIndex < plan.arguments.firstIndex(of: "-i")!)
        #expect(plan.expectedWidth == 96 && plan.expectedHeight == 160)
        _ = try PicturePreview.validate(c, probe: probe(overrides: ["width": 3840, "height": 2160]), time: 0)
        #expect(throws: (any Error).self) { try PicturePreview.validate(c, probe: probe(overrides: ["width": 3840, "height": 3840]), time: 0) }
    }
    private func run(_ args: [String], tools: FFmpegTools) async throws -> Data {
        let r = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-nostdin", "-n"] + args)
        try #require(r.status == 0 && !r.truncated, Comment(rawValue: String(decoding: r.stderr, as: UTF8.self)))
        return r.stdout
    }
    // Independent index mapping for each Y/U/V plane. Does not use a filter or
    // orientation helper to produce the expected pixels.
    private func permute(_ data: Data, angle: Int) -> Data {
        var output = Data(), offset = 0
        for (w,h) in [(160,96),(80,48),(80,48)] {
            let swap = angle == 90 || angle == 270, ow = swap ? h : w, oh = swap ? w : h
            for y in 0..<oh { for x in 0..<ow {
                let sx: Int, sy: Int
                switch angle {
                case 90: sx = w-1-y; sy = x
                case 180: sx = w-1-x; sy = h-1-y
                case 270: sx = y; sy = h-1-x
                default: sx = x; sy = y
                }
                output.append(data[offset+sy*w+sx])
            } }
            offset += w*h
        }
        return output
    }
    @Test func rightAnglesMatchIndependentPixelsPreviewAndPublishedOutputs() async throws {
        let tools = try #require(FFmpegTools.discover())
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("orientation-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: dir) }
        let base = dir.appendingPathComponent("base.mp4")
        _ = try await run(["-f", "lavfi", "-i", "testsrc2=size=160x96:rate=24:duration=1", "-c:v", "libx264", "-crf", "0", "-pix_fmt", "yuv420p", "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709", "-color_range", "tv", "-bsf:v", "h264_metadata=colour_primaries=1:transfer_characteristics=1:matrix_coefficients=1", base.path], tools: tools)
        let rawArgs = ["-frames:v", "1", "-pix_fmt", "yuv420p", "-f", "rawvideo", "pipe:1"]
        let raw = try await run(["-i", base.path] + rawArgs, tools: tools)
        for angle in [0,90,180,270] {
            let source = dir.appendingPathComponent("source-\(angle).mp4")
            _ = try await run(["-display_rotation:v:0", String(angle), "-i", base.path, "-map", "0", "-c", "copy", source.path], tools: tools)
            let fingerprint = try await SourceFingerprint.read(source)
            let p = try await MediaProbe.read(source, tools: tools), v = try #require(p.video)
            let orientation = try SourceOrientation.read(v)
            #expect(orientation.degrees == angle)
            let explicit = try await run(orientation.inputArguments(stream: v.index) + ["-i", source.path, "-vf", orientation.filters.isEmpty ? "null" : orientation.filters.joined(separator: ",")] + rawArgs, tools: tools)
            #expect(explicit == permute(raw, angle: angle))
            var c = configuration(); c.cropTop = 2; c.cropBottom = 2; c.picture.cropLeft = 2; c.picture.cropRight = 6
            let comparison = try await PicturePreview.render(source: source, configuration: c, time: 0, tools: tools)
            let width = (angle == 90 || angle == 270) ? 96 : 160, height = (angle == 90 || angle == 270) ? 160 : 96
            #expect(comparison.original.width == width && comparison.original.height == height)
            #expect(comparison.filtered.width == width-8 && comparison.filtered.height == height-4)
            #expect(comparison.original.stamp.matches(comparison.filtered.stamp))
            // Independent FFmpeg default autorotation reference, with explicit
            // numeric crop; no production orientation or PicturePlan involved.
            let rgb = try await run(["-i", source.path, "-vf", "crop=\(width-8):\(height-4):2:2,colorspace=all=bt709:trc=iec61966-2-1:range=pc:format=yuv444p,format=rgb24", "-frames:v", "1", "-f", "rawvideo", "pipe:1"], tools: tools)
            #expect(comparison.filtered.rgb == rgb)
            let referenceYUV = try await run(["-i", source.path, "-vf", "crop=\(width-8):\(height-4):2:2"] + rawArgs, tools: tools)
            for container in ["MP4", "MKV"] {
                c.container = container
                let output = dir.appendingPathComponent("output-\(angle).\(container.lowercased())")
                let job = QueueJob(id: UUID(), source: source.path, isDemo: false, destination: output.path, configuration: c, created: Date())
                let batch = BatchController(); await batch.discover(); batch.start([job])
                let deadline = Date().addingTimeInterval(30)
                while batch.running && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
                if batch.running { batch.cancel() }
                try #require(batch.statuses[job.id]?.phase == "Completed", Comment(rawValue: batch.statuses[job.id]?.detail ?? "Missing result"))
                let actual = try await MediaProbe.read(output, tools: tools), av = try #require(actual.video)
                #expect(av.width == width-8 && av.height == height-4)
                #expect(try SourceOrientation.read(av) == .identity)
                let pixels = try await run(["-noautorotate", "-i", output.path] + rawArgs, tools: tools)
                try #require(pixels.count == referenceYUV.count)
                let mse = zip(pixels, referenceYUV).reduce(0.0) { $0 + pow(Double($1.0)-Double($1.1), 2) } / Double(pixels.count)
                #expect(mse < 40, "Lossy encode should retain upright cropped content, not just dimensions")
            }
            #expect(try await SourceFingerprint.read(source) == fingerprint)
        }
        let mirror = dir.appendingPathComponent("mirror.mp4")
        _ = try await run(["-display_rotation:v:0", "90", "-display_hflip:v:0", "-i", base.path, "-map", "0", "-c", "copy", mirror.path], tools: tools)
        let mirrorHash = try await SourceFingerprint.read(mirror)
        await #expect(throws: (any Error).self) { try await PicturePreview.render(source: mirror, configuration: configuration(), time: 0, tools: tools) }
        let refused = dir.appendingPathComponent("refused.mkv")
        let job = QueueJob(id: UUID(), source: mirror.path, isDemo: false, destination: refused.path, configuration: configuration(), created: Date())
        let batch = BatchController(); await batch.discover(); batch.start([job])
        let deadline = Date().addingTimeInterval(15)
        while batch.running && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        if batch.running { batch.cancel() }
        #expect(batch.statuses[job.id]?.phase == "Failed")
        #expect(batch.statuses[job.id]?.detail.contains("orientation") == true)
        #expect(!FileManager.default.fileExists(atPath: refused.path))
        #expect(try await SourceFingerprint.read(mirror) == mirrorHash)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).allSatisfy { !$0.hasPrefix(".staxrip-batch-") })
    }
}
