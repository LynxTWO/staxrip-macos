import Foundation
import CryptoKit
import Darwin
import Testing
@testable import StaxRipMac

struct ExportSourceFingerprintTests {
    private final class WorkerObservation: @unchecked Sendable {
        private let lock = NSLock()
        private var value: (qos: UInt32, mainThread: Bool)?
        func record() { lock.withLock { if value == nil { value = (qos_class_self().rawValue, Thread.isMainThread) } } }
        func snapshot() -> (qos: UInt32, mainThread: Bool)? { lock.withLock { value } }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [TaskPriority.medium, .high])
    func foregroundRequestKeepsWorkerPriorityWithoutReadingOnMain(priority: TaskPriority) async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("source"), bytes = Data("abc".utf8)
        try bytes.write(to: file)
        let observation = WorkerObservation()
        let task = Task.detached(priority: priority) {
            try await ExportSourceFingerprint.read(file) { _, _ in observation.record() }
        }
        let result = try await task.value
        let worker = try #require(observation.snapshot())
        // A higher-priority waiter may promote the task. The worker must at
        // least retain this explicitly requested floor, never force utility.
        let minimum = priority == .high ? QOS_CLASS_USER_INITIATED.rawValue : QOS_CLASS_DEFAULT.rawValue
        #expect(worker.qos >= minimum)
        #expect(!worker.mainThread)
        #expect(result.sha256 == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(result.byteCount == 3)
        #expect(try Data(contentsOf: file) == bytes)
    }

    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("source-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
    private final class Progress: @unchecked Sendable {
        let lock = NSLock()
        var values: [(Int64, Int64)] = []
        func append(_ a: Int64, _ b: Int64) { lock.lock(); values.append((a, b)); lock.unlock() }
        func snapshot() -> [(Int64, Int64)] { lock.lock(); defer { lock.unlock() }; return values }
    }
    @Test func knownDigestsMultipleChunksSymlinksAndBoundedProgress() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("source"), link = root.appendingPathComponent("link")
        try Data("abc".utf8).write(to: file)
        let small = try await ExportSourceFingerprint.read(file)
        #expect(small.sha256 == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(small.byteCount == 3)
        let bytes = Data((0..<(5 * 1024 * 1024 + 17)).map { UInt8($0 % 251) })
        try bytes.write(to: file)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        let progress = Progress()
        let large = try await ExportSourceFingerprint.read(link) { progress.append($0, $1) }
        #expect(large.byteCount == bytes.count)
        #expect(large.sha256 == SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
        let values = progress.snapshot()
        #expect(values.count <= 101 && values.count > 2)
        #expect(values.first?.0 == 0 && values.last?.0 == Int64(bytes.count))
        #expect(values.allSatisfy { $0.1 == bytes.count })
        #expect(zip(values, values.dropFirst()).allSatisfy { $0.0.0 < $0.1.0 })
    }
    @Test(.timeLimit(.minutes(1))) func rejectsMissingEmptyDirectoryAndFIFOWithoutWaitingForWriter() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let empty = root.appendingPathComponent("empty"), fifo = root.appendingPathComponent("fifo")
        try Data().write(to: empty)
        try #require(mkfifo(fifo.path, 0o600) == 0)
        for file in [empty, fifo, root, root.appendingPathComponent("missing")] {
            await #expect(throws: (any Error).self) { try await ExportSourceFingerprint.read(file) }
        }
    }
    @Test(arguments: ["append", "rewrite", "replace", "truncate"])
    func detectsChangesWhileReading(change: String) async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("source")
        try Data(repeating: 7, count: 2 * 1024 * 1024).write(to: file)
        await #expect(throws: (any Error).self) {
            try await ExportSourceFingerprint.read(file) { count, _ in
                guard count == 0 else { return }
                do {
                    if change == "replace" {
                        try Data(repeating: 8, count: 2 * 1024 * 1024).write(to: file, options: .atomic)
                    } else {
                        let handle = try FileHandle(forWritingTo: file); defer { try? handle.close() }
                        if change == "append" { try handle.seekToEnd(); try handle.write(contentsOf: Data([9])) }
                        if change == "truncate" { try handle.truncate(atOffset: 1) }
                        if change == "rewrite" {
                            try handle.write(contentsOf: Data([8]))
                            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 10)], ofItemAtPath: file.path)
                        }
                    }
                } catch { Issue.record(error) }
            }
        }
    }
    private final class Gate: @unchecked Sendable {
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let lock = NSLock(); var finished = false
        func finish() { lock.lock(); finished = true; lock.unlock() }
        func isFinished() -> Bool { lock.lock(); defer { lock.unlock() }; return finished }
    }
    @Test(.timeLimit(.minutes(1))) func cancellationAwaitsWorkerAndAlreadyCancelledNeverReads() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("source"); try Data(repeating: 7, count: 2 * 1024 * 1024).write(to: file)
        let gate = Gate()
        let task = Task {
            defer { gate.finish() }
            return try await ExportSourceFingerprint.read(file) { count, _ in
                if count == 0 { gate.entered.signal(); gate.release.wait() }
            }
        }
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { gate.entered.wait(); continuation.resume() }
        }
        task.cancel()
        #expect(!gate.isFinished())
        gate.release.signal()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(gate.isFinished())
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ExportSourceFingerprint.read(file) { _, _ in Issue.record("Cancelled reader emitted progress") }
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(try Data(contentsOf: file) == Data(repeating: 7, count: 2 * 1024 * 1024))
    }
}
