#if DEBUG
import Foundation
import Testing
@testable import StaxRipMac

// Explicit qualification workload only. Existing default tests and their
// scheduling are unchanged; this consumes every reported CPU for three seconds.
struct SourceWorkerContentionTests {
    private final class Load: @unchecked Sendable {
        let lock = NSLock(), group = DispatchGroup()
        var entered = 0, ready = false
        var submitted: ContinuousClock.Instant?, worker: ContinuousClock.Instant?
        var checksum: UInt64 = 0
        let count: Int
        init(count: Int) { self.count = count }
        func observe(_ event: String) {
            if event == "submitting worker" {
                let deadline = ContinuousClock.now.advanced(by: .seconds(1))
                for _ in 0..<count {
                    group.enter()
                    DispatchQueue(label: "StaxRip.test-source-contention", qos: .userInitiated).async {
                        self.lock.withLock { self.entered += 1 }
                        let end = ContinuousClock.now.advanced(by: .seconds(3))
                        var state: UInt64 = 123456789
                        while ContinuousClock.now < end {
                            for _ in 0..<10000 { state = state &* 6364136223846793005 &+ 1442695040888963407 }
                        }
                        self.lock.withLock { self.checksum ^= state }
                        self.group.leave()
                    }
                }
                while lock.withLock({ entered < count }), ContinuousClock.now < deadline {
                    Thread.sleep(forTimeInterval: 0.001)
                }
                lock.withLock { ready = entered == count && ContinuousClock.now < deadline; submitted = .now }
            } else if event == "worker entered" {
                lock.withLock { worker = .now }
            }
        }
        func settle() async {
            await withCheckedContinuation { continuation in
                group.notify(queue: DispatchQueue(label: "StaxRip.test-source-contention-join")) { continuation.resume() }
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["STAXRIP_SOURCE_WORKER_STRESS"] == "1"), .timeLimit(.minutes(1)))
    func sourceWorkerStartsDuringBoundedCPUContention() async throws {
        let count = ProcessInfo.processInfo.activeProcessorCount
        try #require((2...32).contains(count), "This opt-in fixture supports two through 32 reported CPUs")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("source-contention-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("source"), bytes = Data("abc".utf8)
        try bytes.write(to: file)
        let load = Load(count: count)
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
