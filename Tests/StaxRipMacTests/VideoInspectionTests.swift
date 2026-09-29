import Testing
import Foundation
@testable import StaxRipMac

@MainActor
struct VideoInspectionTests {
    private func stream(_ fields: [String: Any] = [:]) throws -> MediaProbe.Stream {
        var input = fields
        input["index"] = 0
        input["codec_type"] = "video"
        return try JSONDecoder().decode(MediaProbe.Stream.self, from: JSONSerialization.data(withJSONObject: input))
    }

    @Test func absentAndUnknownTagsDoNotBecomeSDROrZeroBitVideo() throws {
        let missing = try stream()
        #expect(VideoInspection.color(missing).allSatisfy { $0.value == "Unspecified" })
        #expect(VideoInspection.picture(missing).last?.value == "Unspecified")
        #expect(VideoInspection.timing(missing).allSatisfy { $0.value == "Unspecified" })
        let partial = try stream(["color_transfer": "future-transfer", "color_range": "pc", "bits_per_raw_sample": "0"])
        #expect(VideoInspection.color(partial)[1].value == "future-transfer")
        #expect(VideoInspection.color(partial)[3].value == "Full range (pc)")
        #expect(VideoInspection.picture(partial).last?.value == "Unspecified")
        #expect(VideoInspection.reported("unknown") == "Unspecified")
    }

    @Test func declaredHDRAndGeometryKeepTheirSeparateMeaning() throws {
        let pq = try stream(["color_transfer": "smpte2084", "color_primaries": "bt2020", "color_space": "bt2020nc", "color_range": "tv", "bits_per_raw_sample": "10", "side_data_list": [["rotation": -90]], "tags": ["rotate": "180"]])
        #expect(VideoInspection.color(pq)[1].value == "PQ, declared HDR transfer (smpte2084)")
        #expect(VideoInspection.color(pq)[3].value == "Limited range (tv)")
        #expect(VideoInspection.picture(pq).last?.value == "10 bits")
        #expect(VideoInspection.timing(pq)[5].value == "-90°")
        #expect(VideoInspection.timing(pq)[6].value == "180")
        let hlg = try stream(["color_transfer": "arib-std-b67"])
        #expect(VideoInspection.color(hlg)[1].value == "HLG, declared HDR transfer (arib-std-b67)")
    }

    @Test func rationalDisplayRejectsInvalidOrUnavailableValues() {
        for raw in ["0/0", "1/0", "-24/1", "NaN/1", "1/infinity", "1/2/3", "24", "1e308/1e-308", "1e-308/1e308", "N/A", ""] {
            #expect(VideoInspection.ratio(raw, frameRate: true).hasPrefix("Unspecified"))
        }
        #expect(VideoInspection.ratio("30000/1001", frameRate: true) == "29.970 frames/s (30000/1001)")
        #expect(VideoInspection.ratio("4:3", frameRate: false) == "4:3")
        #expect(VideoInspection.ratio("0:1", frameRate: false).hasPrefix("Unspecified"))
        #expect(VideoInspection.ratio("1:0", frameRate: false).hasPrefix("Unspecified"))
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), arguments: ["bt709", "smpte2084", "arib-std-b67"])
    func generatedTaggedVideoIsInspectedWithoutChangingEncodePolicy(transfer: String) async throws {
        let tools = try #require(FFmpegTools.discover())
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("inspection-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("tagged.mkv")
        let hdr = transfer != "bt709"
        let pixel = hdr ? "yuv420p10le" : "yuv420p"
        let primaries = hdr ? "bt2020" : "bt709"
        let matrix = hdr ? "bt2020nc" : "bt709"
        let codecArguments = hdr ? ["-c:v", "libx265", "-preset", "ultrafast", "-x265-params", "pools=1:frame-threads=1:log-level=error"] : ["-c:v", "libx264", "-preset", "ultrafast"]
        let fixture = try await ToolRunner().run(executable: tools.ffmpeg, arguments: [
            "-v", "error", "-n", "-f", "lavfi", "-i", "testsrc2=size=160x90:rate=30000/1001:duration=1",
            "-vf", "setsar=4/3,setparams=color_primaries=\(primaries):color_trc=\(transfer):colorspace=\(matrix):range=limited"] + codecArguments + ["-threads", "2", "-pix_fmt", pixel,
            "-color_trc", transfer, "-color_primaries", primaries, "-colorspace", matrix, "-color_range", "tv", source.path
        ])
        try #require(fixture.status == 0, Comment(rawValue: String(decoding: fixture.stderr, as: UTF8.self)))
        let original = try Data(contentsOf: source)
        let probe = try await MediaProbe.read(source, tools: tools)
        let video = try #require(probe.video)
        #expect(video.pix_fmt == pixel)
        #expect(video.color_transfer == transfer)
        #expect(video.color_primaries == primaries)
        #expect(video.color_space == matrix)
        #expect(video.color_range == "tv")
        #expect(video.avg_frame_rate == "30000/1001")
        #expect(video.sample_aspect_ratio == "4:3")
        #expect(video.display_aspect_ratio == "64:27")
        var config = EncodeConfiguration()
        config.codec = "H.264"; config.encoder = "x264"; config.audio = "No audio"
        let output = dir.appendingPathComponent("output.mkv")
        let job = QueueJob(id: UUID(), source: source.path, isDemo: false, destination: output.path, configuration: config, created: Date())
        if hdr {
            #expect(throws: (any Error).self) { try EncodePlan.make(job: job, probe: probe, encoders: ["libx264"], staged: output) }
        } else {
            let plan = try EncodePlan.make(job: job, probe: probe, encoders: ["libx264"], staged: output)
            #expect(plan.expectedCodec == "h264")
        }
        #expect(try Data(contentsOf: source) == original)
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }
}
