#if DEBUG
import Foundation
import Testing
@testable import StaxRipMac

// Explicit qualification workload only. Existing default tests and their
// scheduling are unchanged; this consumes every reported CPU for three seconds.
struct SourceWorkerContentionTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["STAXRIP_SOURCE_WORKER_STRESS"] == "1"), .timeLimit(.minutes(1)))
    func sourceWorkerStartsDuringBoundedCPUContention() async throws {
        let count = ProcessInfo.processInfo.activeProcessorCount
        try #require((2...32).contains(count), "This opt-in fixture supports two through 32 reported CPUs")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("source-contention-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("source"), bytes = Data("abc".utf8)
        try bytes.write(to: file)
        let load = WorkerContentionLoad(count: count)
        do {
            let result = try await ExportSourceFingerprint.$observeBoundary.withValue({ load.observe($0) }) {
                try #require(Task.currentPriority == .medium, "The controlled request must retain default task priority")
                return try await ExportSourceFingerprint.read(file)
            }
            await load.settle()
            let observation = load.lock.withLock { (load.ready, load.submitted, load.worker) }
            try #require(observation.0, "All owned CPU workers must start within the setup bound")
            let submission = try #require(observation.1), worker = try #require(observation.2)
            let delay = submission.duration(to: worker)
            print("SOURCE_CONTENTION CPUs=\(count) submitted-to-worker=\(delay)")
            #expect(delay < .seconds(1))
            #expect(result.sha256 == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
            #expect(result.byteCount == 3)
            #expect(try Data(contentsOf: file) == bytes)
        } catch {
            await load.settle()
            throw error
        }
    }
}
#endif
