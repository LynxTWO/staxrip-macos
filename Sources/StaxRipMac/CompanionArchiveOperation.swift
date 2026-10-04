import Foundation
import Darwin

/// Internal concrete native bridge. Tool capabilities currently exist only for
/// generated development qualification; no archive action or release trust exists.
@MainActor
enum CompanionArchiveOperation {
    struct ReviewFailure: CompanionUnsettledOwnership, LocalizedError {
        let operationError: Error
        let reviewID: UUID
        let intendedStage: URL
        var errorDescription: String? { "Companion access is retained for ownership review. No cleanup is authorized." }
    }
    struct Environment {
        var access: (URL) throws -> (() -> Void)? = { url in
            guard url.startAccessingSecurityScopedResource() else { return nil }
            return { url.stopAccessingSecurityScopedResource() }
        }
        var activity: ExportActivity.Factory = ExportActivity.begin
        var retainedActivitySeconds: Double = 120
    }
    #if DEBUG
    @TaskLocal static var testEnvironment = Environment()
    struct Boundary: Sendable {
        var phase: @Sendable (String) throws -> Void = { _ in }
        var pinned: @Sendable ([Int32]) -> Void = { _ in }
    }
    @TaskLocal static var testBoundary = Boundary()
    static func retainedForTesting(_ id: UUID) -> Bool { retained[id] != nil }
    /// Only controlled generated phases whose settlement was separately proved.
    /// This is deliberately absent from release code, not a recovery authority.
    static func releaseGeneratedReviewForTesting(_ id: UUID) { retained.removeValue(forKey: id)?.finish() }
    #endif
    private static var retained: [UUID: Access] = [:]
    private static var executing = false

    static func execute(source: URL, in parent: URL, destinationName: String,
                        retention: OriginalCompanionTransaction.Retention,
                        writer: CompanionWriterProcess.Tool, reader: CompanionMetadataProcess.Tool) async throws -> ResultSetStaging.Published {
        try Task.checkCancellation()
        try ResultSetStaging.validateDestinationName(destinationName)
        guard [source, parent].allSatisfy({ $0.isFileURL && !$0.path.utf8.contains(0) }) else { throw refused() }
        #if DEBUG
        let environment = testEnvironment, boundary = testBoundary
        #else
        let environment = Environment()
        #endif
        guard !executing, retained.isEmpty, environment.retainedActivitySeconds.isFinite,
              environment.retainedActivitySeconds > 0, environment.retainedActivitySeconds <= 120 else { throw refused() }
        executing = true
        defer { executing = false }
        let access = try Access(source: source, directory: parent, reason: "StaxRip original companion preservation", environment: environment)
        let pins = access.pins
        #if DEBUG
        boundary.pinned(pins.descriptors)
        #endif
        do {
            let result = try await OriginalCompanionTransaction.execute(source: source, in: parent,
                destinationName: destinationName, retention: retention, produce: { stage in
                    try pins.check()
                    #if DEBUG
                    try boundary.phase("writer")
                    #endif
                    return try await CompanionWriterProcess.run(tool: writer, source: source, stage: stage, retention: retention).contents
                }, verify: { stage, contents in
                    try pins.check()
                    #if DEBUG
                    try boundary.phase("verifier")
                    #endif
                    let disk = try await CompanionDiskCheck.verifyOriginalMetadata(source: source, stage: stage, contents: contents, tool: reader)
                    guard let metadata = disk.originalMetadata, disk.originalMetadataSemanticsVerified else { throw refused() }
                    return .init(contents: disk.contents, originalComponentsMatchSource: metadata.originalComponentsMatchSource,
                        sourceIdentityChecked: true, decodedFrameAssociation: metadata.decodedFrameAssociation,
                        immutableSnapshot: metadata.immutableSnapshot, stableImporter: metadata.stableImporter)
                })
            // Cancellation after an exclusive commit still reports actual success.
            access.finish(); return result
        } catch {
            let stage: URL?
            if let e = error as? OriginalCompanionTransaction.UnsettledPhaseFailure { stage = e.intendedStage }
            else if let e = error as? OriginalCompanionTransaction.CleanupFailure { stage = e.intendedStage }
            else { stage = nil }
            if let stage {
                throw retain(access, error: error, locator: stage, environment: environment)
            }
            access.finish(); throw error
        }
    }
    /// Source-dependent read-only examination. Candidate permission does not grant
    /// access to its parent; no directory is created, changed, published or removed.
    static func reviewCandidate(source: URL, candidate: URL,
                                retention: OriginalCompanionTransaction.Retention,
                                reader: CompanionMetadataProcess.Tool) async throws -> CompanionDiskCheck.Receipt {
        try Task.checkCancellation()
        guard [source, candidate].allSatisfy({ $0.isFileURL && !$0.path.utf8.contains(0) }) else { throw refused() }
        #if DEBUG
        let environment = testEnvironment, boundary = testBoundary
        #else
        let environment = Environment()
        #endif
        guard !executing, retained.isEmpty, environment.retainedActivitySeconds.isFinite,
              environment.retainedActivitySeconds > 0, environment.retainedActivitySeconds <= 120 else { throw refused() }
        executing = true
        defer { executing = false }
        let access = try Access(source: source, directory: candidate, reason: "StaxRip original companion review", environment: environment)
        let pins = access.pins
        #if DEBUG
        boundary.pinned(pins.descriptors)
        #endif
        do {
            try pins.check()
            #if DEBUG
            try boundary.phase("reviewer")
            #endif
            let result = try await CompanionDiskCheck.reviewOriginalCandidate(source: source, candidate: candidate, retention: retention, tool: reader)
            try pins.check()
            access.finish()
            return result
        } catch {
            // Native worker/process refusal returns only after settlement, except
            // its explicit ownership marker. Changed outer locators likewise cannot
            // establish the held access still describes the caller's selection.
            if error is any CompanionUnsettledOwnership {
                throw retain(access, error: error, locator: candidate, environment: environment)
            }
            do { try pins.check() }
            catch { throw retain(access, error: error, locator: candidate, environment: environment) }
            access.finish()
            throw error
        }
    }
    private static func retain(_ access: Access, error: Error, locator: URL, environment: Environment) -> ReviewFailure {
        let id = UUID(); retained[id] = access
        // Expiry ends only temporary energy. Dropped errors do not release access
        // or authorize cleanup, adoption, publication or a successful review.
        DispatchQueue.main.asyncAfter(deadline: .now() + environment.retainedActivitySeconds) {
            retained[id]?.endActivity()
        }
        return ReviewFailure(operationError: error, reviewID: id, intendedStage: locator)
    }
    private nonisolated static func refused() -> NativeExportError { .invalid("Native companion access refused. No result was published.") }

    private final class Access {
        let pins: Pins
        private var ends: [() -> Void]
        private var activityEnd: (() -> Void)?
        init(source: URL, directory: URL, reason: String, environment: Environment) throws {
            var acquired: [() -> Void] = []
            do {
                if let end = try environment.access(source) { acquired.append(end) }
                if let end = try environment.access(directory) { acquired.append(end) }
                pins = try Pins(source: source, directory: directory)
            } catch { for end in acquired.reversed() { end() }; throw error }
            ends = acquired
            activityEnd = environment.activity(reason)
        }
        func endActivity() { let end = activityEnd; activityEnd = nil; end?() }
        func finish() {
            pins.close()
            for end in ends.reversed() { end() }; ends.removeAll()
            endActivity()
        }
    }
    /// Concrete descriptors establish current access, not immutable snapshots or
    /// sandbox bookmark rights. They close only after all native phases return.
    private final class Pins: @unchecked Sendable {
        private let source, directory: URL
        private var fds: [Int32] = []
        private var identities: [stat] = []
        #if DEBUG
        var descriptors: [Int32] { fds }
        #endif
        init(source: URL, directory: URL) throws {
            self.source = source; self.directory = directory
            do {
                for (url, directory) in [(source, false), (directory, true)] {
                    let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_NOCTTY | O_CLOEXEC | (directory ? O_DIRECTORY : 0))
                    guard fd >= 0 else { throw refused() }
                    fds.append(fd)
                    var s = stat(), p = stat()
                    guard fstat(fd, &s) == 0, lstat(url.path, &p) == 0,
                          s.st_mode & mode_t(S_IFMT) == mode_t(directory ? S_IFDIR : S_IFREG),
                          directory || (1...Int64(1 << 40)).contains(s.st_size), Self.same(s, p, directory: directory) else { throw refused() }
                    identities.append(s)
                }
            } catch { close(); throw error }
        }
        func check() throws {
            guard fds.count == 2 else { throw refused() }
            for (i, url) in [source, directory].enumerated() {
                var s = stat(), p = stat()
                guard fstat(fds[i], &s) == 0, lstat(url.path, &p) == 0,
                      Self.same(identities[i], s, directory: i == 1), Self.same(identities[i], p, directory: i == 1) else { throw refused() }
            }
        }
        private static func same(_ a: stat, _ b: stat, directory: Bool) -> Bool {
            guard a.st_dev == b.st_dev, a.st_ino == b.st_ino, a.st_uid == b.st_uid, a.st_mode == b.st_mode else { return false }
            return directory || (a.st_size == b.st_size && a.st_nlink == b.st_nlink &&
                a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec &&
                a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec)
        }
        func close() { for fd in fds { Darwin.close(fd) }; fds.removeAll() }
        deinit { close() }
    }
}
