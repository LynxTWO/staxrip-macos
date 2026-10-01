import Foundation
import AVFoundation
import Testing
@testable import StaxRipMac

@MainActor
struct NativeOutputDurationTests {
    @Test func nativeTimingRequiresKnownPositiveSourceAndFixedStrictDifference() throws {
        for value in [0.0, -1, .nan, .infinity, -.infinity] {
            #expect(throws: (any Error).self) { try NativeExportDuration(sourceSeconds: value) }
        }
        for expected in [1.0, 180, 7200, 86_400] {
            let contract = try NativeExportDuration(sourceSeconds: expected)
            try contract.verify(actual: expected)
            try contract.verify(actual: expected - 0.249)
            try contract.verify(actual: expected + 0.249)
            for difference in [-0.25, 0.25, -1, 1] {
                #expect(throws: (any Error).self) { try contract.verify(actual: expected + difference) }
            }
            for invalid in [0.0, -1, .nan, .infinity, -.infinity] {
                #expect(throws: (any Error).self) { try contract.verify(actual: invalid) }
            }
        }
    }
    #if DEBUG
    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(2)), arguments: [1, 5])
    func changedStagedDurationCannotPublishAndExplicitRetryWorks(seconds: Int) async throws {
        let tools = try #require(FFmpegTools.discover())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-duration-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let activity = ExportActivityRecorder()
        let service = NativeExportService(beginActivity: activity.begin)
        let controller = ExportController(service: service)
        controller.preset = .h264Small
        defer {
            if controller.running { controller.cancel() }
            else { try? FileManager.default.removeItem(at: root) }
        }
        let source = root.appendingPathComponent("source.mp4"), replacement = root.appendingPathComponent("replacement.mp4")
        for (url, duration) in [(source, 3), (replacement, seconds)] {
            let made = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-nostdin", "-n", "-f", "lavfi", "-i", "testsrc2=size=160x96:rate=24:duration=\(duration)", "-an", "-c:v", "libx264", "-preset", "ultrafast", "-threads", "2", "-pix_fmt", "yuv420p", url.path])
            try #require(made.status == 0)
        }
        let sourceBytes = try Data(contentsOf: source), replacementBytes = try Data(contentsOf: replacement)
        let prior = root.appendingPathComponent("prior.mp4"), protectedBytes = Data("preserve prior output".utf8)
        try protectedBytes.write(to: prior)
        let unrelated = root.appendingPathComponent(".staxrip-export-unrelated")
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: false)
        let sentinel = unrelated.appendingPathComponent("keep")
        try protectedBytes.write(to: sentinel)
        let output = root.appendingPathComponent("output.mp4")
        var observed = false
        try await NativeExportTestBoundary.$beforeVerification.withValue({ staged in
            #expect(!observed && service.active && activity.active == 1)
            observed = true
            #expect(staged.deletingLastPathComponent().lastPathComponent.hasPrefix(".staxrip-export-"))
            #expect(staged != source && staged != output)
            try replacementBytes.write(to: staged, options: .atomic)
            let altered = AVURLAsset(url: staged)
            #expect(try await altered.loadTracks(withMediaType: .video).count == 1)
            #expect(abs(try await altered.load(.duration).seconds - Double(seconds)) < 0.001)
        }) {
            controller.start(source: source, destination: output)
            while controller.running { try await Task.sleep(for: .milliseconds(10)) }
        }
        #expect(observed)
        #expect(controller.result == nil && controller.status == "Export failed")
        #expect(controller.failure?.contains("Output duration differs") == true)
        #expect(!FileManager.default.fileExists(atPath: output.path))
        if FileManager.default.fileExists(atPath: output.path) {
            let accepted = try await AVURLAsset(url: output).load(.duration)
            print("NATIVE_DURATION_UNEXPECTED_PUBLICATION expected=3 actual=\(accepted.seconds)")
        }
        activity.expectSettled()
        #expect(!service.active)
        #expect(try Data(contentsOf: source) == sourceBytes && Data(contentsOf: prior) == protectedBytes)
        #expect(try Data(contentsOf: sentinel) == protectedBytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix(".staxrip-export-") } == [unrelated.lastPathComponent])

        let retry = root.appendingPathComponent("retry.mp4")
        controller.start(source: source, destination: retry)
        while controller.running { try await Task.sleep(for: .milliseconds(10)) }
        #expect(controller.result == retry && controller.failure == nil && controller.status == "Export complete")
        #expect(abs(try await AVURLAsset(url: retry).load(.duration).seconds - 3) < 0.25)
        activity.expectSettled(count: 2)
        #expect(try Data(contentsOf: source) == sourceBytes && Data(contentsOf: prior) == protectedBytes)
        #expect(try Data(contentsOf: sentinel) == protectedBytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix(".staxrip-export-") } == [unrelated.lastPathComponent])
    }
    #endif
}
