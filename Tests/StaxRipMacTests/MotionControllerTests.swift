import Foundation
import Testing
@testable import StaxRipMac

@MainActor
struct MotionControllerTests {
    private actor Gate {
        var pending: CheckedContinuation<MotionComparison, Error>?
        var calls = 0
        func render(_ workspace: MotionWorkspace) async throws -> MotionComparison {
            calls += 1
            try Data("owned generated proxy placeholder".utf8).write(to: workspace.movie)
            return try await withCheckedThrowingContinuation { pending = $0 }
        }
        func release() throws {
            let stamp = PreviewStamp(pts: 0, base: try HDRFraction("1/24"))
            pending?.resume(returning: MotionComparison(requested: 0, end: 3,
                frames: [MotionFrame(stamp: stamp, width: 640, height: 360, aspect: try HDRFraction("1/1"), format: "yuv420p", color: "generated")],
                sourceIdentity: SourceFingerprint(sha256: "generated", byteCount: 3), operations: "Generated lifecycle fixture", bytes: 3))
            pending = nil
        }
    }
    private actor Cleanup {
        var refuse = true
        func remove(_ workspace: MotionWorkspace) async throws {
            if refuse { throw NativeExportError.invalid("Generated cleanup refusal") }
            try await workspace.remove()
        }
        func allow() { refuse = false }
    }
    private var tools: FFmpegTools { FFmpegTools(ffmpeg: URL(fileURLWithPath: "/usr/bin/false"), ffprobe: URL(fileURLWithPath: "/usr/bin/false")) }
    private func wait(_ controller: MotionPreviewController) async throws {
        while controller.running { try await Task.sleep(for: .milliseconds(1)) }
    }
    private func started(_ gate: Gate) async throws {
        while await gate.pending == nil { try await Task.sleep(for: .milliseconds(1)) }
    }
    @Test(.timeLimit(.minutes(1))) func cancelledLateResultCannotReplaceOrOverlapOwnedOperation() async throws {
        let gate = Gate()
        let controller = MotionPreviewController(renderer: { _, _, _, _, workspace, _ in try await gate.render(workspace) })
        controller.render(source: URL(fileURLWithPath: "/generated/one"), configuration: EncodeConfiguration(), time: 0, tools: tools)
        try await started(gate)
        let directory = try #require(controller.workspace?.directory)
        controller.cancel()
        controller.render(source: URL(fileURLWithPath: "/generated/two"), configuration: EncodeConfiguration(), time: 0, tools: tools)
        #expect(controller.running && controller.result == nil && controller.player == nil)
        #expect(FileManager.default.fileExists(atPath: directory.path))
        #expect(await gate.calls == 1)
        try await gate.release(); try await wait(controller)
        #expect(controller.workspace == nil && controller.result == nil && controller.player == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
    @Test(.timeLimit(.minutes(1))) func closeDetachesPlayerAndCleanupFailureStaysOwnedUntilRetry() async throws {
        let gate = Gate(), cleanup = Cleanup()
        let controller = MotionPreviewController(renderer: { _, _, _, _, workspace, _ in try await gate.render(workspace) }, cleanup: { try await cleanup.remove($0) })
        controller.render(source: URL(fileURLWithPath: "/generated/one"), configuration: EncodeConfiguration(), time: 0, tools: tools)
        try await started(gate); try await gate.release(); try await wait(controller)
        let player = try #require(controller.player), directory = try #require(controller.workspace?.directory)
        #expect(controller.result != nil)
        controller.close(); try await wait(controller)
        #expect(player.currentItem == nil && player.rate == 0)
        #expect(controller.cleanupFailed && controller.workspace != nil && controller.result == nil)
        #expect(FileManager.default.fileExists(atPath: directory.path))
        controller.render(source: URL(fileURLWithPath: "/generated/two"), configuration: EncodeConfiguration(), time: 0, tools: tools)
        #expect(await gate.calls == 1)
        await cleanup.allow(); controller.retryCleanup(); try await wait(controller)
        #expect(!controller.cleanupFailed && controller.workspace == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(await controller.finishClosing())
    }
}
