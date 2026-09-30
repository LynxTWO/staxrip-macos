import Foundation
import Darwin

// Local intent and historical status only. Reading this never starts a process or deletes media.
struct BatchJournal: Codable {
    var version = 5
    var jobs: [QueueJob]
    var statuses: [UUID: BatchStatus]
    var updated = Date()

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StaxRipMac", isDirectory: true).appendingPathComponent("last-batch.json")
    }

    func validated() throws -> Self {
        guard [1, 2, 3, 4, 5].contains(version) else { throw SessionError.invalid("Unsupported batch recovery version.") }
        guard version >= 5 || jobs.allSatisfy({ $0.configuration.externalSubtitle == nil }) else {
            throw SessionError.invalid("External subtitle references require recovery version 5.")
        }
        _ = try SessionDocument(configuration: EncodeConfiguration(), outputFolder: "/", outputStem: "recovery", jobs: jobs).validated()
        let ids = Set(jobs.map(\.id))
        let phases: Set<String> = ["Pending", "Inspecting", "Encoding", "Verifying", "Completed", "Failed", "Cancelled", "Interrupted"]
        guard Set(statuses.keys).isSubset(of: ids) else { throw SessionError.invalid("Recovery status refers to an unknown job.") }
        for job in jobs {
            guard let state = statuses[job.id] else { continue }
            guard phases.contains(state.phase), state.progress.isFinite, (0...1).contains(state.progress), state.detail.utf8.count <= 100_000,
                  state.destination == nil || state.destination == URL(fileURLWithPath: job.destination) else {
                throw SessionError.invalid("Invalid batch recovery status.")
            }
            if state.phase == "Completed", state.destination == nil { throw SessionError.invalid("Completed recovery status is missing its output.") }
        }
        return self
    }

    func restoredStatuses() -> [UUID: BatchStatus] {
        var result = statuses
        for job in jobs {
            guard let state = result[job.id] else { continue }
            if ["Inspecting", "Encoding", "Verifying"].contains(state.phase) {
                result[job.id] = BatchStatus(phase: "Interrupted", detail: "Previous run ended before completion was recorded. Review the destination before retrying. Partial files may remain beside it; nothing was resumed or removed.")
            } else if state.phase == "Completed", !FileManager.default.fileExists(atPath: job.destination) {
                result[job.id] = BatchStatus(phase: "Failed", detail: "Previously completed output is no longer available. Check the destination volume before retrying.")
            }
        }
        return result
    }

    static func read(from url: URL) throws -> Self {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 5_000_001) ?? Data()
        guard data.count <= 5_000_000 else { throw SessionError.invalid("Batch recovery file exceeds 5 MB.") }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Self.self, from: data).validated()
    }

    func write(to url: URL) throws {
        _ = try validated()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        guard data.count <= 5_000_000 else { throw SessionError.invalid("Batch recovery data exceeds 5 MB.") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

// Keep the lock file in place: unlinking a live lock allows a second inode/lock owner.
final class BatchJournalLease {
    private let descriptor: Int32
    init(journalURL: URL) throws {
        try FileManager.default.createDirectory(at: journalURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let lockURL = journalURL.appendingPathExtension("lock")
        let fd = Darwin.open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(fd)
            throw SessionError.invalid("Another app instance is using this batch journal. Finish or cancel its batch first.")
        }
        descriptor = fd
    }
    deinit { flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
}
