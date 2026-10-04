import Foundation
import Darwin

/// Internal phase ownership only. Trusted implementations must settle all workers
/// and processes before returning. No native archive action or verifier is installed.
enum OriginalCompanionTransaction {
    enum Retention: Sendable {
        case metadataOnly, entireContainer
        var limits: [String: Int64] {
            var values: [String: Int64] = [
                "original-track-entry-payload.bin": 1 << 20, "hevc-configuration.bin": 1 << 20,
                "original-rpu.bin": 1 << 29, "rpu-index.jsonl": 1 << 29,
                "source-audit.jsonl": 1 << 30, "manifest.json": 1 << 20]
            if self == .entireContainer { values["original-container.mkv"] = 1 << 40 }
            return values
        }
    }
    struct FileID: Equatable, Sendable {
        let device: UInt64
        let inode: UInt64
        init(_ value: stat) {
            device = UInt64(bitPattern: Int64(value.st_dev)); inode = UInt64(value.st_ino)
        }
        init(device: UInt64, inode: UInt64) { self.device = device; self.inode = inode }
    }
    struct Contents: Sendable {
        let retention: Retention
        let sourceID: FileID
        let stageID: FileID
        let sourceBytes: Int64
        let sourceSHA256: String
        let packets: Int64
        let records: Int64
        let enhancementNALs: Int64
        let members: [ResultSetStaging.Member]
    }
    struct Verification: Sendable {
        let contents: Contents
        let originalComponentsMatchSource: Bool
        let sourceIdentityChecked: Bool
        let decodedFrameAssociation: String
        let immutableSnapshot: Bool
        let stableImporter: Bool
    }
    struct CleanupFailure: Error, LocalizedError {
        let operationError: Error
        let cleanupError: Error
        let intendedStage: URL
        var errorDescription: String? { "Companion operation failed; its temporary stage needs cleanup review." }
    }
    typealias Producer = @Sendable (URL) async throws -> Contents
    typealias Verifier = @Sendable (URL, Contents) async throws -> Verification

    private static func failure(_ message: String) -> NativeExportError {
        .invalid("Companion transaction: \(message)")
    }
    private static func hash(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private static func validate(_ value: Contents, retention: Retention, source: Source, stage: FileID) throws {
        let limits = retention.limits
        guard value.retention == retention, value.sourceID == source.id, value.stageID == stage,
              value.sourceBytes == source.bytes, hash(value.sourceSHA256),
              (1...2_000_000).contains(value.packets), (1...2_000_000).contains(value.records),
              (0...4_000_000_000_000).contains(value.enhancementNALs),
              value.members.count == limits.count, Set(value.members.map(\.name)) == Set(limits.keys),
              value.members.allSatisfy({ m in
                  guard let maximum = limits[m.name] else { return false }
                  return (1...maximum).contains(m.byteCount) && hash(m.sha256)
              }) else { throw failure("Invalid source, retention or component receipt.") }
    }
    private static func equal(_ a: Contents, _ b: Contents) -> Bool {
        guard a.retention == b.retention, a.sourceID == b.sourceID, a.stageID == b.stageID,
              a.sourceBytes == b.sourceBytes, a.sourceSHA256 == b.sourceSHA256,
              a.packets == b.packets, a.records == b.records, a.enhancementNALs == b.enhancementNALs else { return false }
        let left = Dictionary(uniqueKeysWithValues: a.members.map { ($0.name, ($0.byteCount, $0.sha256)) })
        return b.members.allSatisfy { left[$0.name]?.0 == $0.byteCount && left[$0.name]?.1 == $0.sha256 }
    }

    /// Caller supplies trusted settled phases; no untrusted document chooses them.
    /// There is no cancellation check after commit: report the actual publication.
    static func execute(source url: URL, in parent: URL, destinationName: String, retention: Retention,
                        produce: Producer, verify: Verifier) async throws -> ResultSetStaging.Published {
        try Task.checkCancellation()
        try ResultSetStaging.validateDestinationName(destinationName)
        guard parent.isFileURL, !parent.path.utf8.contains(0) else { throw failure("Invalid destination parent.") }
        var existing = stat()
        let destination = parent.appendingPathComponent(destinationName)
        guard lstat(destination.path, &existing) != 0, errno == ENOENT else { throw failure("Destination exists or cannot be inspected.") }
        let source = try Source(url)
        let stage = try ResultSetStaging.create(in: parent)
        let directory = stage.originalDirectoryURL
        do {
            _ = try stage.fileURL("manifest.json")
            var info = stat()
            guard lstat(directory.path, &info) == 0, info.st_mode & 0o7777 == 0o700,
                  info.st_uid == geteuid() else { throw failure("Stage is not private.") }
            let stageID = FileID(info)
            try source.check()
            try Task.checkCancellation()
            let produced = try await produce(directory) // Must settle before return/throw.
            try Task.checkCancellation()
            try source.check()
            try validate(produced, retention: retention, source: source, stage: stageID)
            let verified = try await verify(directory, produced) // Separate authoritative phase.
            try Task.checkCancellation()
            try source.check()
            try validate(verified.contents, retention: retention, source: source, stage: stageID)
            guard verified.originalComponentsMatchSource, verified.sourceIdentityChecked,
                  verified.decodedFrameAssociation == "not-established", !verified.immutableSnapshot,
                  !verified.stableImporter, equal(produced, verified.contents) else {
                throw failure("Independent semantic receipts do not agree.")
            }
            return try await stage.publish(as: destinationName, members: produced.members, preCommit: { try source.check() })
        } catch {
            let operation = error
            do { try stage.discard() }
            catch {
                // Return a reviewable ownership error; never follow a substituted stage.
                throw CleanupFailure(operationError: operation, cleanupError: error, intendedStage: directory)
            }
            throw operation
        }
    }

    private final class Source: @unchecked Sendable {
        private let url: URL
        private let fd: Int32
        private let initial: stat
        var id: FileID { FileID(initial) }
        var bytes: Int64 { initial.st_size }
        init(_ url: URL) throws {
            guard url.isFileURL, !url.path.utf8.contains(0) else { throw failure("Invalid source.") }
            let opened = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC | O_NOCTTY)
            guard opened >= 0 else { throw failure("Cannot open original source.") }
            var descriptor = stat(), path = stat()
            guard fstat(opened, &descriptor) == 0, descriptor.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
                  (1...Int64(1 << 40)).contains(descriptor.st_size), lstat(url.path, &path) == 0,
                  Self.same(descriptor, path) else {
                Darwin.close(opened); throw failure("Source is unsafe or changed.")
            }
            self.url = url; fd = opened; initial = descriptor
        }
        deinit { Darwin.close(fd) }
        private static func same(_ a: stat, _ b: stat) -> Bool {
            FileID(a) == FileID(b) && a.st_mode == b.st_mode && a.st_nlink == b.st_nlink &&
                a.st_uid == b.st_uid && a.st_size == b.st_size &&
                a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec &&
                a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
        }
        func check() throws {
            var descriptor = stat(), path = stat()
            guard fstat(fd, &descriptor) == 0, lstat(url.path, &path) == 0,
                  Self.same(initial, descriptor), Self.same(initial, path) else { throw failure("Original source identity changed.") }
        }
    }
}
