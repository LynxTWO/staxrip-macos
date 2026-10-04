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
        let access = try Access(source: source, parent: parent, environment: environment)
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
                let id = UUID(); retained[id] = access
                // Expiry ends only the temporary energy request. Scope/pin retention
                // survives dropped errors and never authorizes deletion or success.
                DispatchQueue.main.asyncAfter(deadline: .now() + environment.retainedActivitySeconds) {
                    retained[id]?.endActivity()
                }
                throw ReviewFailure(operationError: error, reviewID: id, intendedStage: stage)
            }
            access.finish(); throw error
        }
    }
    private nonisolated static func refused() -> NativeExportError { .invalid("Native companion access refused. No result was published.") }

    private final class Access {
        let pins: Pins
        private var ends: [() -> Void]
        private var activityEnd: (() -> Void)?
        init(source: URL, parent: URL, environment: Environment) throws {
            var acquired: [() -> Void] = []
            do {
                if let end = try environment.access(source) { acquired.append(end) }
                if let end = try environment.access(parent) { acquired.append(end) }
                pins = try Pins(source: source, parent: parent)
            } catch { for end in acquired.reversed() { end() }; throw error }
            ends = acquired
            activityEnd = environment.activity("StaxRip original companion preservation")
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
        private let source, parent: URL
        private var fds: [Int32] = []
        private var identities: [stat] = []
        #if DEBUG
        var descriptors: [Int32] { fds }
        #endif
        init(source: URL, parent: URL) throws {
            self.source = source; self.parent = parent
            do {
                for (url, directory) in [(source, false), (parent, true)] {
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
            for (i, url) in [source, parent].enumerated() {
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
