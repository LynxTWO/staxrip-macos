import Foundation
import AVFoundation
import Darwin
import Testing
@testable import StaxRipMac

struct SourceLoaderTests {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("source-loader-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
    @Test func metadataSummaryHandlesNonfiniteAndUnrepresentableValues() {
        #expect(SourceLoader.summary(width: -1920, height: 1080, rate: 23.976, seconds: 154.9) == "1920 × 1080  ·  23.98 fps  ·  02:34")
        for value in [Double.nan, .infinity, -.infinity, Double(Int.max)] {
            let summary = SourceLoader.summary(width: value, height: value, rate: .nan, seconds: value)
            #expect(summary.contains("? × ?"))
            #expect(summary.contains("Unknown frame rate") && summary.contains("Unknown duration"))
        }
        #expect(SourceLoader.summary(width: 160, height: 96, rate: 24, seconds: -1).hasSuffix("00:00"))
        #expect(SourceLoader.summary(width: 160, height: 96, rate: 24, seconds: 3_600_000).hasSuffix("60000:00"))
    }

    @Test(.timeLimit(.minutes(1))) func specialEmptyAndMissingPathsNeverStartNativeReadsButRegularSymlinksWork() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let fifo = root.appendingPathComponent("held.mp4"), empty = root.appendingPathComponent("empty.mp4")
        try #require(mkfifo(fifo.path, 0o600) == 0)
        try Data().write(to: empty)
        for url in [fifo, empty, root, root.appendingPathComponent("missing.mp4"), URL(fileURLWithPath: "/dev/null")] {
            await #expect(throws: (any Error).self) {
                try await SourceLoader.read(url, tools: nil, nativeReader: { _ in
                    Issue.record("An invalid source reached the native reader")
                    return LoadedSource(nativePreview: false, info: "unexpected")
                })
            }
        }
        let regular = root.appendingPathComponent("regular.mp4"), link = root.appendingPathComponent("link.mp4")
        try Data([1]).write(to: regular)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: regular)
        let result = try await SourceLoader.read(link, tools: nil, nativeReader: { _ in LoadedSource(nativePreview: false, info: "accepted regular path") })
        #expect(result.info == "accepted regular path")
    }

    private final class HeldResource: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
        let entered: AsyncStream<Void>.Continuation
        init(_ entered: AsyncStream<Void>.Continuation) { self.entered = entered }
        func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
            entered.yield(()); return true
        }
    }
    @Test(.timeLimit(.minutes(1))) func heldNativeReadCancelsWithoutStartingFallback() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        try Data([1]).write(to: root.appendingPathComponent("generated.mp4"))
        let marker = root.appendingPathComponent("fallback-called"), wrapper = root.appendingPathComponent("probe")
        try "#!/bin/zsh\n/usr/bin/touch '\(marker.path)'\nexit 1\n".write(to: wrapper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapper.path)
        let (stream, entered) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let delegate = HeldResource(entered)
        let asset = AVURLAsset(url: URL(string: "staxrip-fixture://held/generated.mp4")!)
        asset.resourceLoader.setDelegate(delegate, queue: DispatchQueue(label: "source-loader-held"))
        let worker = Task {
            defer { entered.finish() }
            return try await SourceLoader.read(root.appendingPathComponent("generated.mp4"), tools: FFmpegTools(ffmpeg: wrapper, ffprobe: wrapper),
                                        nativeReader: { _ in try await SourceLoader.native(asset) })
        }
        do {
            var requested = false
            for await _ in stream { requested = true; break }
            try #require(requested, "The native reader must request the held resource")
            try Task.checkCancellation()
            let watchdog = Task {
                do {
                    try await Task.sleep(for: .seconds(30))
                    Issue.record("Native cancellation did not settle; forcing fixture cleanup")
                    asset.cancelLoading()
                } catch {}
            }
            defer { watchdog.cancel() }
            worker.cancel()
            await #expect(throws: CancellationError.self) { try await worker.value }
            #expect(!FileManager.default.fileExists(atPath: marker.path))
        } catch { asset.cancelLoading(); worker.cancel(); _ = try? await worker.value; throw error }
        entered.finish()
        withExtendedLifetime(delegate) {}
    }
    @Test func alreadyCancelledLoadDoesNotStartNativeOrFallback() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await SourceLoader.read(URL(fileURLWithPath: "/generated/unread.mp4"), tools: nil, nativeReader: { _ in
                Issue.record("Precancelled request started native loading")
                return LoadedSource(nativePreview: false, info: "unexpected")
            })
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        await #expect(throws: (any Error).self) { try await SourceLoader.read(URL(string: "https://example.invalid/source.mp4")!, tools: nil) }
    }
    @Test(.timeLimit(.minutes(1))) func fallbackCancellationWaitsForActualProcessExit() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        try Data([1]).write(to: root.appendingPathComponent("generated.mkv"))
        let pidFile = root.appendingPathComponent("pid"), wrapper = root.appendingPathComponent("probe")
        try "#!/bin/zsh\nprintf '%s' $$ > '\(pidFile.path)'\nexec /bin/sleep 30\n".write(to: wrapper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapper.path)
        let worker = Task {
            try await SourceLoader.read(root.appendingPathComponent("generated.mkv"), tools: FFmpegTools(ffmpeg: wrapper, ffprobe: wrapper), nativeReader: { _ in
                throw NativeExportError.invalid("Generated native refusal")
            })
        }
        do {
            while !FileManager.default.fileExists(atPath: pidFile.path) { try await Task.sleep(for: .milliseconds(5)) }
            // The marker is created before exec; wait for a complete PID rather than assume write timing.
            var pid: Int32?
            while pid == nil { pid = Int32((try? String(contentsOf: pidFile, encoding: .utf8)) ?? ""); if pid == nil { try await Task.sleep(for: .milliseconds(5)) } }
            worker.cancel()
            await #expect(throws: CancellationError.self) { try await worker.value }
            let value = try #require(pid)
            #expect(Darwin.kill(value, 0) == -1 && errno == ESRCH)
        } catch { worker.cancel(); _ = try? await worker.value; throw error }
    }
    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(1)))
    func generatedNativeAndFallbackSourcesRetainTheirBytes() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let tools = try #require(FFmpegTools.discover())
        for (name, codec, native) in [("native.mp4", "libx264", true), ("fallback.mkv", "ffv1", false)] {
            let source = root.appendingPathComponent(name)
            let made = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-n", "-f", "lavfi", "-i", "testsrc2=s=160x96:r=24:d=0.5", "-c:v", codec, source.path])
            try #require(made.status == 0)
            let bytes = try Data(contentsOf: source)
            let result = try await SourceLoader.read(source, tools: tools)
            #expect(result.nativePreview == native)
            #expect(result.info.contains("160 × 96"))
            if native { #expect(result.info.contains("24.00 fps")) }
            else { #expect(result.info.contains("native preview unavailable")) }
            #expect(try Data(contentsOf: source) == bytes)
        }
        await #expect(throws: (any Error).self) {
            try await SourceLoader.read(root.appendingPathComponent("missing.mp4"), tools: nil)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == ["fallback.mkv", "native.mp4"])
    }
}
