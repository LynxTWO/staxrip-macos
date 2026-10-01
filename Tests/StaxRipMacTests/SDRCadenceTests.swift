import Foundation
import Testing
@testable import StaxRipMac

@MainActor
struct SDRCadenceTests {
    private let encoders: Set<String> = ["libx264", "libx265", "libsvtav1", "h264_videotoolbox", "hevc_videotoolbox"]
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sdr-cadence-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
    private func run(_ args: [String], tools: FFmpegTools) async throws -> ToolResult {
        let result = try await ToolRunner().run(executable: tools.ffmpeg, arguments: args)
        try #require(result.status == 0, Comment(rawValue: String(decoding: result.stderr, as: UTF8.self)))
        return result
    }
    private func fixture(_ root: URL, kind: String, tools: FFmpegTools) async throws -> URL {
        let source = root.appendingPathComponent(kind + (kind == "fractional" ? ".mp4" : ".mkv"))
        let timing: String
        switch kind {
        case "irregular": timing = "settb=1/1000,setpts='(N+0.45*mod(N,2))*1000/24',"
        case "gaps": timing = "setpts='if(lt(N,6),N,if(lt(N,12),N+3,N+9))/(24*TB)',"
        default: timing = ""
        }
        _ = try await run(["-v", "error", "-n", "-f", "lavfi", "-i", "testsrc2=size=160x96:rate=\(kind == "fractional" ? "24000/1001" : "24"):duration=1",
                          "-vf", timing + "setparams=range=limited:color_primaries=bt709:color_trc=bt709:colorspace=bt709",
                          "-fps_mode", "passthrough", "-enc_time_base", "filter", "-c:v", kind == "fractional" ? "libx264" : "ffv1", source.path], tools: tools)
        return source
    }
    private struct Frames: Decodable {
        struct Frame: Decodable { let best_effort_timestamp: Int64 }
        let frames: [Frame]
    }
    private func timestamps(_ source: URL, tools: FFmpegTools) async throws -> (values: [Double], tick: Double) {
        let probe = try await MediaProbe.read(source, tools: tools)
        let tick = try HDRFraction(probe.video?.time_base).value
        try #require(tick > 0 && tick <= 0.001)
        let result = try await ToolRunner().run(executable: tools.ffprobe, arguments: ["-v", "error", "-select_streams", "v:0", "-show_frames", "-show_entries", "frame=best_effort_timestamp", "-of", "json", source.path])
        try #require(result.status == 0 && !result.truncated)
        let frames = try JSONDecoder().decode(Frames.self, from: result.stdout).frames
        return (frames.map { Double($0.best_effort_timestamp) * tick }, tick)
    }
    private func job(_ root: URL, source: URL, codec: String, container: String, filteredTrim: Bool, hardware: Bool = false) -> QueueJob {
        var c = EncodeConfiguration(); c.selectCodec(codec); c.container = container; c.resolution = "Original"
        c.audio = "No audio"; c.subtitleMode = "Remove all subtitles"; c.speed = "Fast"
        if filteredTrim {
            c.picture.cropLeft = 2; c.cropBottom = 2; c.picture.deinterlace = "All frames"
            c.picture.start = 0.2; c.picture.end = 0.85
        }
        if hardware { c.rate.backend = "Apple hardware"; c.rate.mode = "Target bitrate"; c.rate.bitrate = 1200 }
        return QueueJob(id: UUID(), source: source.path, isDemo: false,
                        destination: root.appendingPathComponent("\(codec)-\(source.lastPathComponent)-\(filteredTrim).\(container.lowercased())").path,
                        configuration: c, created: Date())
    }
    private func check(_ job: QueueJob, tools: FFmpegTools) async throws {
        let source = URL(fileURLWithPath: job.source), output = URL(fileURLWithPath: job.destination)
        let before = try Data(contentsOf: source), input = try await timestamps(source, tools: tools)
        let probe = try await MediaProbe.read(source, tools: tools)
        let plan = try EncodePlan.make(job: job, probe: probe, encoders: encoders, staged: output)
        _ = try await run(plan.arguments, tools: tools)
        let actual = try await timestamps(output, tools: tools), c = job.configuration
        let expected = input.values.filter { $0 >= c.picture.start && (c.picture.end == 0 || $0 < c.picture.end) }.map { $0 - c.picture.start }
        try #require(actual.values.count == expected.count, Comment(rawValue: output.lastPathComponent))
        let allowance = (c.container == "MKV" ? 0.001 : actual.tick) + 0.000000001
        for (observed, wanted) in zip(actual.values, expected) {
            #expect(abs(observed - wanted) <= allowance, Comment(rawValue: "\(output.lastPathComponent): decoded PTS \(observed), expected \(wanted), allowance \(allowance)"))
        }
        #expect(try Data(contentsOf: source) == before)
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(1)))
    func irregularTimestampsSurviveActualEncodePlan() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let tools = try #require(FFmpegTools.discover()), source = try await fixture(root, kind: "irregular", tools: tools)
        try await check(job(root, source: source, codec: "H.264", container: "MKV", filteredTrim: false), tools: tools)
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(2)), arguments: ["H.264", "HEVC", "AV1"])
    func softwareCadenceAcrossContainersFiltersAndTrim(codec: String) async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let tools = try #require(FFmpegTools.discover())
        for kind in ["irregular", "gaps", "fractional"] {
            let source = try await fixture(root, kind: kind, tools: tools)
            for container in ["MKV", "MP4"] {
                for filteredTrim in [false, true] {
                    try await check(job(root, source: source, codec: codec, container: container, filteredTrim: filteredTrim), tools: tools)
                }
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["STAXRIP_TEST_HARDWARE"] == "1"), .timeLimit(.minutes(2)), arguments: ["H.264", "HEVC"])
    func localHardwareCadence(codec: String) async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let tools = try #require(FFmpegTools.discover())
        for kind in ["irregular", "fractional"] {
            let source = try await fixture(root, kind: kind, tools: tools)
            for container in ["MKV", "MP4"] {
                for filteredTrim in [false, true] {
                    try await check(job(root, source: source, codec: codec, container: container, filteredTrim: filteredTrim, hardware: true), tools: tools)
                }
            }
        }
    }
}
