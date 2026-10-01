#if DEBUG
import Foundation
import Darwin
import Testing
@testable import StaxRipMac

struct PublicationWorkerContentionTests {
    private final class Observation: @unchecked Sendable {
        let lock = NSLock()
        var qos: UInt32 = 0, onMain = true
        func record() { lock.withLock { qos = qos_class_self().rawValue; onMain = Thread.isMainThread } }
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["STAXRIP_PUBLICATION_WORKER_STRESS"] == "1"), .timeLimit(.minutes(1)))
    func publicationStartsDuringBoundedCPUContention() async throws {
        let count = ProcessInfo.processInfo.activeProcessorCount
        try #require((2...32).contains(count), "This opt-in fixture supports two through 32 reported CPUs")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("publication-contention-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let staged = root.appendingPathComponent("staged"), destination = root.appendingPathComponent("output")
        let bytes = Data("generated publication fixture".utf8)
        try bytes.write(to: staged)
        let load = WorkerContentionLoad(count: count), operation = Observation()
        do {
            try await ExportPublication.$observeBoundary.withValue({ load.observe($0) }) {
                try #require(Task.currentPriority == .medium, "The controlled request must retain default task priority")
                try await ExportPublication.publishAsync(staged: staged, destination: destination) { source, output in
                    operation.record()
                    try ExportPublication.publish(staged: source, destination: output)
                }
            }
            await load.settle()
            let timing = load.lock.withLock { (load.ready, load.submitted, load.worker) }
            try #require(timing.0, "All owned CPU workers must start within the setup bound")
            let submission = try #require(timing.1), worker = try #require(timing.2)
            let delay = submission.duration(to: worker)
            print("PUBLICATION_CONTENTION CPUs=\(count) submitted-to-worker=\(delay)")
            #expect(delay < .seconds(1))
            let context = operation.lock.withLock { (operation.qos, operation.onMain) }
            #expect(context.0 >= QOS_CLASS_DEFAULT.rawValue)
            #expect(!context.1)
            #expect(try Data(contentsOf: staged) == bytes)
            #expect(try Data(contentsOf: destination) == bytes)
        } catch {
            await load.settle()
            throw error
        }
    }
}
#endif
