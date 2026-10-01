#if DEBUG
import Foundation
import Darwin
import Testing
@testable import StaxRipMac

struct ExternalSubtitleWorkerContentionTests {
    private final class Context: @unchecked Sendable {
        let lock = NSLock()
        var qos: UInt32 = 0, main = true
        func record() { lock.withLock { qos = qos_class_self().rawValue; main = Thread.isMainThread } }
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["STAXRIP_SUBTITLE_WORKER_STRESS"] == "1"), .timeLimit(.minutes(1)))
    func actualCaptionWorkerStartsDuringBoundedCPUContention() async throws {
        let count = ProcessInfo.processInfo.activeProcessorCount
        try #require((2...32).contains(count))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("subtitle-contention-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("captions.srt")
        let bytes = Data("1\n00:00:00,000 --> 00:00:01,000\nGenerated caption\n\n".utf8)
        try bytes.write(to: file)
        let load = WorkerContentionLoad(count: count), context = Context()
        do {
            try #require(Task.currentPriority == .medium)
            let document = try await ExternalSubtitle.$observeBoundary.withValue({ event in
                if event == "worker entered" { context.record() }
                load.observe(event)
            }) { try await ExternalSubtitle(path: file.path).read() }
            await load.settle()
            let timing = load.lock.withLock { (load.ready, load.submitted, load.worker) }
            try #require(timing.0)
            let submitted = try #require(timing.1), entered = try #require(timing.2)
            let delay = submitted.duration(to: entered)
            let worker = context.lock.withLock { (context.qos, context.main) }
            print("SUBTITLE_CONTENTION CPUs=\(count) submitted-to-worker=\(delay) qos=\(worker.0) main=\(worker.1)")
            #expect(delay < .seconds(1))
            #expect(worker.0 >= QOS_CLASS_DEFAULT.rawValue && !worker.1)
            #expect(document.cues.count == 1 && document.cues[0].text == "Generated caption")
            #expect(document.canonicalData == bytes)
            #expect(try Data(contentsOf: file) == bytes)
        } catch {
            await load.settle()
            throw error
        }
    }
}
#endif
