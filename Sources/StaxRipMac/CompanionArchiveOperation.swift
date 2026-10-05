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
        /// Actual returned exclusive commit, not a persisted recovery receipt.
        let published: ResultSetStaging.Published?
        /// Actual owned stage removal in this attempt; no authority over a later path.
        let removed: ResultSetStaging.Removed?
        var errorDescription: String? {
            if published != nil { return "Companion result was published; access is retained for ownership review. No cleanup is authorized." }
            if removed != nil { return "Owned companion stage was removed; access is retained for close review. No cleanup is authorized." }
            return "Companion access is retained for ownership review. No cleanup is authorized."
        }
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
        var beforeAssociationRelease: @Sendable () throws -> Void = {}
        var associationClosed: @Sendable (Int) -> Void = { _ in }
        // Report uncertainty only after both actual outer closes succeed.
        var refuseAssociationClose: @Sendable () -> Bool = { false }
        var acquisitionClosed: @Sendable (Int) -> Void = { _ in }
        var archiveClosed: @Sendable (Int) -> Void = { _ in }
        var refuseArchiveClose: @Sendable () -> Bool = { false }
    }
    @TaskLocal static var testBoundary = Boundary()
    static func retainedForTesting(_ id: UUID) -> Bool { retained[id] != nil }
    static func retainedStageForTesting(_ id: UUID) -> ResultSetStaging? { retained[id]?.stage }
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
        let access = try acquire(source: source, directory: parent, reason: "StaxRip original companion preservation", environment: environment)
        let pins = access.pins
        #if DEBUG
        boundary.pinned(pins.descriptors)
        #endif
        var published: ResultSetStaging.Published?
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
            published = result
            try pins.check()
            // Cancellation after commit is still success unless ownership refuses.
            let closed = try access.finishChecked(archive: true)
            #if DEBUG
            boundary.archiveClosed(closed)
            #else
            _ = closed
            #endif
            return result
        } catch {
            if let inner = error as? OriginalCompanionTransaction.SourceSettlementFailure {
                // An inner source close may refuse after the exclusive commit,
                // before the transaction can return its actual Published value.
                throw retain(access, error: inner, locator: inner.intendedStage,
                             environment: environment, published: inner.published)
            }
            if let inner = error as? OriginalCompanionTransaction.CreationSettlementFailure {
                throw retain(access, error: inner, locator: inner.intendedStage, environment: environment)
            }
            if let inner = error as? OriginalCompanionTransaction.StagingSettlementFailure {
                throw retain(access, error: inner, locator: inner.intendedStage,
                             environment: environment, published: inner.published)
            }
            if let published {
                // Transaction already returned its exclusive commit. Never discard
                // or classify this as an unpublished pre-commit failure.
                throw retain(access, error: error, locator: published.directory,
                             environment: environment, published: published)
            }
            let stage: URL?
            if let e = error as? OriginalCompanionTransaction.UnsettledPhaseFailure { stage = e.intendedStage }
            else if let e = error as? OriginalCompanionTransaction.CleanupFailure { stage = e.intendedStage }
            else { stage = nil }
            if let stage {
                throw retain(access, error: error, locator: stage, environment: environment)
            }
            if error is any CompanionUnsettledOwnership {
                throw retain(access, error: error, locator: parent, environment: environment)
            }
            do { try pins.check() }
            catch { throw retain(access, error: error, locator: parent, environment: environment) }
            do {
                let closed = try access.finishChecked(archive: true)
                #if DEBUG
                boundary.archiveClosed(closed)
                #else
                _ = closed
                #endif
            } catch { throw retain(access, error: error, locator: parent, environment: environment) }
            throw error
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
        let access = try acquire(source: source, directory: candidate, reason: "StaxRip original companion review", environment: environment)
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
            let closed = try access.finishChecked(archive: true)
            #if DEBUG
            boundary.archiveClosed(closed)
            #else
            _ = closed
            #endif
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
            do {
                let closed = try access.finishChecked(archive: true)
                #if DEBUG
                boundary.archiveClosed(closed)
                #else
                _ = closed
                #endif
            } catch { throw retain(access, error: error, locator: candidate, environment: environment) }
            throw error
        }
    }
    /// Development original base-frame association. The caller owns an explicit
    /// empty private spool folder. This operation neither removes nor publishes it.
    static func associateOriginalFrames(source: URL, spoolDirectory: URL,
                                        tool: DolbyDecoderProcess.Tool, threads: Int = 4,
                                        timeout: Double = 120,
                                        limits: DolbyAssociationSpool.Limits = .init()) async throws -> CompanionDiskCheck.SourceFrameReceipt {
        try Task.checkCancellation()
        guard [source, spoolDirectory].allSatisfy({ $0.isFileURL && !$0.path.utf8.contains(0) }),
              [1, 4].contains(threads), timeout.isFinite, timeout > 0, timeout <= 120 else { throw refused() }
        #if DEBUG
        let environment = testEnvironment, boundary = testBoundary
        #else
        let environment = Environment()
        #endif
        guard !executing, retained.isEmpty, environment.retainedActivitySeconds.isFinite,
              environment.retainedActivitySeconds > 0, environment.retainedActivitySeconds <= 120 else { throw refused() }
        executing = true
        defer { executing = false }
        let access = try acquire(source: source, directory: spoolDirectory,
                                reason: "StaxRip original source frame association", environment: environment)
        let pins = access.pins
        #if DEBUG
        boundary.pinned(pins.descriptors)
        #endif
        do {
            try pins.check()
            #if DEBUG
            try boundary.phase("association")
            #endif
            let result = try await CompanionDiskCheck.associateOriginalFrames(source: source, in: spoolDirectory,
                tool: tool, threads: threads, timeout: timeout, limits: limits)
            try pins.check()
            try Task.checkCancellation()
            #if DEBUG
            try boundary.beforeAssociationRelease()
            #endif
            let closed = try access.finishChecked()
            #if DEBUG
            boundary.associationClosed(closed)
            #else
            _ = closed
            #endif
            return result
        } catch {
            // D127 returns after its worker/database/source/helper unwind except
            // for the shared uncertainty marker. Keep grants on either that marker
            // or loss of the explicit outer path identity. No file cleanup follows.
            if error is any CompanionUnsettledOwnership {
                throw retain(access, error: error, locator: spoolDirectory, environment: environment)
            }
            do { try pins.check() }
            catch { throw retain(access, error: error, locator: spoolDirectory, environment: environment) }
            do {
                #if DEBUG
                try boundary.beforeAssociationRelease()
                #endif
                let closed = try access.finishChecked()
                #if DEBUG
                boundary.associationClosed(closed)
                #else
                _ = closed
                #endif
            }
            catch { throw retain(access, error: error, locator: spoolDirectory, environment: environment) }
            throw error
        }
    }
    /// Development original base-sample association. The caller owns an explicit
    /// empty private spool folder. This operation neither removes nor publishes it.
    static func associateOriginalSamples(source: URL, spoolDirectory: URL,
                                        tool: DolbyDecoderProcess.Tool, threads: Int = 4,
                                        timeout: Double = 120,
                                        limits: DolbyAssociationSpool.Limits = .init()) async throws -> CompanionDiskCheck.SourceSampleReceipt {
        try Task.checkCancellation()
        guard [source, spoolDirectory].allSatisfy({ $0.isFileURL && !$0.path.utf8.contains(0) }),
              [1, 4].contains(threads), timeout.isFinite, timeout > 0, timeout <= 120 else { throw refused() }
        #if DEBUG
        let environment = testEnvironment, boundary = testBoundary
        #else
        let environment = Environment()
        #endif
        guard !executing, retained.isEmpty, environment.retainedActivitySeconds.isFinite,
              environment.retainedActivitySeconds > 0, environment.retainedActivitySeconds <= 120 else { throw refused() }
        executing = true
        defer { executing = false }
        let access = try acquire(source: source, directory: spoolDirectory,
                                reason: "StaxRip original source sample association", environment: environment)
        let pins = access.pins
        #if DEBUG
        boundary.pinned(pins.descriptors)
        #endif
        do {
            try pins.check()
            #if DEBUG
            try boundary.phase("sample-association")
            #endif
            let result = try await CompanionDiskCheck.associateOriginalSamples(source: source, in: spoolDirectory,
                tool: tool, threads: threads, timeout: timeout, limits: limits)
            try pins.check()
            try Task.checkCancellation()
            #if DEBUG
            try boundary.beforeAssociationRelease()
            #endif
            let closed = try access.finishChecked()
            #if DEBUG
            boundary.associationClosed(closed)
            #else
            _ = closed
            #endif
            return result
        } catch {
            // D131/D132 return after its worker/database/source/helper unwind except
            // for the shared uncertainty marker. Keep grants on either that marker
            // or loss of the explicit outer path identity. No file cleanup follows.
            if error is any CompanionUnsettledOwnership {
                throw retain(access, error: error, locator: spoolDirectory, environment: environment)
            }
            do { try pins.check() }
            catch { throw retain(access, error: error, locator: spoolDirectory, environment: environment) }
            do {
                #if DEBUG
                try boundary.beforeAssociationRelease()
                #endif
                let closed = try access.finishChecked()
                #if DEBUG
                boundary.associationClosed(closed)
                #else
                _ = closed
                #endif
            }
            catch { throw retain(access, error: error, locator: spoolDirectory, environment: environment) }
            throw error
        }
    }
    /// Development original crop association. The caller owns an explicit
    /// empty private spool folder. This operation neither removes nor publishes it.
    static func associateOriginalCrops(source: URL, spoolDirectory: URL,
                                       tool: DolbyDecoderProcess.Tool, request: DolbyDecoderStream.CropRequest, threads: Int = 4,
                                       timeout: Double = 120,
                                       limits: DolbyAssociationSpool.Limits = .init()) async throws -> CompanionDiskCheck.SourceCropReceipt {
        try Task.checkCancellation()
        guard [source, spoolDirectory].allSatisfy({ $0.isFileURL && !$0.path.utf8.contains(0) }),
              [1, 4].contains(threads), timeout.isFinite, timeout > 0, timeout <= 120 else { throw refused() }
        #if DEBUG
        let environment = testEnvironment, boundary = testBoundary
        #else
        let environment = Environment()
        #endif
        guard !executing, retained.isEmpty, environment.retainedActivitySeconds.isFinite,
              environment.retainedActivitySeconds > 0, environment.retainedActivitySeconds <= 120 else { throw refused() }
        executing = true
        defer { executing = false }
        let access = try acquire(source: source, directory: spoolDirectory,
                                reason: "StaxRip original source crop association", environment: environment)
        let pins = access.pins
        #if DEBUG
        boundary.pinned(pins.descriptors)
        #endif
        do {
            try pins.check()
            #if DEBUG
            try boundary.phase("crop-association")
            #endif
            let result = try await CompanionDiskCheck.associateOriginalCrops(source: source, in: spoolDirectory,
                tool: tool, request: request, threads: threads, timeout: timeout, limits: limits)
            try pins.check()
            try Task.checkCancellation()
            #if DEBUG
            try boundary.beforeAssociationRelease()
            #endif
            let closed = try access.finishChecked()
            #if DEBUG
            boundary.associationClosed(closed)
            #else
            _ = closed
            #endif
            return result
        } catch {
            // D144/D132 return after its worker/database/source/helper unwind except
            // for the shared uncertainty marker. Keep grants on either that marker
            // or loss of the explicit outer path identity. No file cleanup follows.
            if error is any CompanionUnsettledOwnership {
                throw retain(access, error: error, locator: spoolDirectory, environment: environment)
            }
            do { try pins.check() }
            catch { throw retain(access, error: error, locator: spoolDirectory, environment: environment) }
            do {
                #if DEBUG
                try boundary.beforeAssociationRelease()
                #endif
                let closed = try access.finishChecked()
                #if DEBUG
                boundary.associationClosed(closed)
                #else
                _ = closed
                #endif
            }
            catch { throw retain(access, error: error, locator: spoolDirectory, environment: environment) }
            throw error
        }
    }
    /// Joint source Video/caller crop facts remain distinct from origin or pixel proof.
    /// Explicit grants and concrete pins cover the same source/open-spool worker.
    static func associateOriginalVideoCrops(source: URL, spoolDirectory: URL,
                                       tool: DolbyDecoderProcess.Tool, request: DolbyDecoderStream.CropRequest, threads: Int = 4,
                                       timeout: Double = 120,
                                       limits: DolbyAssociationSpool.Limits = .init()) async throws -> CompanionDiskCheck.SourceVideoCropReceipt {
        try Task.checkCancellation()
        guard [source, spoolDirectory].allSatisfy({ $0.isFileURL && !$0.path.utf8.contains(0) }),
              [1, 4].contains(threads), timeout.isFinite, timeout > 0, timeout <= 120 else { throw refused() }
        #if DEBUG
        let environment = testEnvironment, boundary = testBoundary
        #else
        let environment = Environment()
        #endif
        guard !executing, retained.isEmpty, environment.retainedActivitySeconds.isFinite,
              environment.retainedActivitySeconds > 0, environment.retainedActivitySeconds <= 120 else { throw refused() }
        executing = true
        defer { executing = false }
        let access = try acquire(source: source, directory: spoolDirectory,
                                reason: "StaxRip original source Video/crop association", environment: environment)
        let pins = access.pins
        #if DEBUG
        boundary.pinned(pins.descriptors)
        #endif
        do {
            try pins.check()
            #if DEBUG
            try boundary.phase("video-crop-association")
            #endif
            let result = try await CompanionDiskCheck.associateOriginalVideoCrops(source: source, in: spoolDirectory,
                tool: tool, request: request, threads: threads, timeout: timeout, limits: limits)
            try pins.check()
            try Task.checkCancellation()
            #if DEBUG
            try boundary.beforeAssociationRelease()
            #endif
            let closed = try access.finishChecked()
            #if DEBUG
            boundary.associationClosed(closed)
            #else
            _ = closed
            #endif
            return result
        } catch {
            // D148/D132 return after the worker/database/source/helper unwind except
            // for the shared uncertainty marker. Keep grants on either that marker
            // or loss of the explicit outer path identity. No file cleanup follows.
            if error is any CompanionUnsettledOwnership {
                throw retain(access, error: error, locator: spoolDirectory, environment: environment)
            }
            do { try pins.check() }
            catch { throw retain(access, error: error, locator: spoolDirectory, environment: environment) }
            do {
                #if DEBUG
                try boundary.beforeAssociationRelease()
                #endif
                let closed = try access.finishChecked()
                #if DEBUG
                boundary.associationClosed(closed)
                #else
                _ = closed
                #endif
            }
            catch { throw retain(access, error: error, locator: spoolDirectory, environment: environment) }
            throw error
        }
    }
    /// Joint source parameter/VCL/caller crop facts remain distinct from origin or pixel proof.
    /// Explicit grants and concrete pins cover the same source/open-spool worker.
    static func associateOriginalParameterCrops(source: URL, spoolDirectory: URL,
                                       tool: DolbyDecoderProcess.Tool, request: DolbyDecoderStream.CropRequest, threads: Int = 4,
                                       timeout: Double = 120,
                                       limits: DolbyAssociationSpool.Limits = .init()) async throws -> CompanionDiskCheck.SourceParameterCropReceipt {
        try Task.checkCancellation()
        guard [source, spoolDirectory].allSatisfy({ $0.isFileURL && !$0.path.utf8.contains(0) }),
              [1, 4].contains(threads), timeout.isFinite, timeout > 0, timeout <= 120 else { throw refused() }
        #if DEBUG
        let environment = testEnvironment, boundary = testBoundary
        #else
        let environment = Environment()
        #endif
        guard !executing, retained.isEmpty, environment.retainedActivitySeconds.isFinite,
              environment.retainedActivitySeconds > 0, environment.retainedActivitySeconds <= 120 else { throw refused() }
        executing = true
        defer { executing = false }
        let access = try acquire(source: source, directory: spoolDirectory,
                                reason: "StaxRip original source parameter/crop association", environment: environment)
        let pins = access.pins
        #if DEBUG
        boundary.pinned(pins.descriptors)
        #endif
        do {
            try pins.check()
            #if DEBUG
            try boundary.phase("parameter-crop-association")
            #endif
            let result = try await CompanionDiskCheck.associateOriginalParameterCrops(source: source, in: spoolDirectory,
                tool: tool, request: request, threads: threads, timeout: timeout, limits: limits)
            try pins.check()
            try Task.checkCancellation()
            #if DEBUG
            try boundary.beforeAssociationRelease()
            #endif
            let closed = try access.finishChecked()
            #if DEBUG
            boundary.associationClosed(closed)
            #else
            _ = closed
            #endif
            return result
        } catch {
            // D153/D132 return after the worker/database/source/helper unwind except
            // for the shared uncertainty marker. Keep grants on either that marker
            // or loss of the explicit outer path identity. No file cleanup follows.
            if error is any CompanionUnsettledOwnership {
                throw retain(access, error: error, locator: spoolDirectory, environment: environment)
            }
            do { try pins.check() }
            catch { throw retain(access, error: error, locator: spoolDirectory, environment: environment) }
            do {
                #if DEBUG
                try boundary.beforeAssociationRelease()
                #endif
                let closed = try access.finishChecked()
                #if DEBUG
                boundary.associationClosed(closed)
                #else
                _ = closed
                #endif
            }
            catch { throw retain(access, error: error, locator: spoolDirectory, environment: environment) }
            throw error
        }
    }
    /// Concrete rollback ownership exists before scopes or descriptors are tried.
    /// An uncertain partial close retains grants even before activity begins.
    private static func acquire(source: URL, directory: URL, reason: String,
                                environment: Environment) throws -> Access {
        let access = Access(source: source, directory: directory)
        do { try access.acquire(source: source, directory: directory, reason: reason, environment: environment) }
        catch {
            do {
                let closed = try access.finishChecked()
                #if DEBUG
                testBoundary.acquisitionClosed(closed)
                #else
                _ = closed
                #endif
            }
            catch { throw retain(access, error: error, locator: directory, environment: environment) }
            throw error
        }
        return access
    }
    private static func retain(_ access: Access, error: Error, locator: URL, environment: Environment,
                               published: ResultSetStaging.Published? = nil) -> ReviewFailure {
        let id = UUID(); retained[id] = access
        // Retain the concrete transaction owner, not only its review locator.
        // Dropping the error or expiring energy must not run its fallback deinit.
        if let e = error as? OriginalCompanionTransaction.SourceSettlementFailure { access.stage = e.retainedStage }
        else if let e = error as? OriginalCompanionTransaction.StagingSettlementFailure { access.stage = e.retainedStage }
        else if let e = error as? OriginalCompanionTransaction.UnsettledPhaseFailure { access.stage = e.retainedStage }
        else if let e = error as? OriginalCompanionTransaction.CleanupFailure { access.stage = e.retainedStage }
        // Expiry ends only temporary energy. Dropped errors do not release access
        // or authorize cleanup, adoption, publication or a successful review.
        DispatchQueue.main.asyncAfter(deadline: .now() + environment.retainedActivitySeconds) {
            retained[id]?.endActivity()
        }
        return ReviewFailure(operationError: error, reviewID: id, intendedStage: locator, published: published,
            removed: (error as? OriginalCompanionTransaction.CleanupFailure)?.removed)
    }
    private nonisolated static func refused() -> NativeExportError { .invalid("Native companion access refused. No result was published.") }

    @MainActor private final class Access {
        let pins: Pins
        // No production release/recovery API exists for uncertain stage ownership.
        var stage: ResultSetStaging?
        private var ends: [() -> Void] = []
        private var activityEnd: (() -> Void)?
        init(source: URL, directory: URL) { pins = Pins(source: source, directory: directory) }
        func acquire(source: URL, directory: URL, reason: String, environment: Environment) throws {
            if let end = try environment.access(source) { ends.append(end) }
            if let end = try environment.access(directory) { ends.append(end) }
            try pins.open()
            activityEnd = environment.activity(reason)
        }
        func endActivity() { let end = activityEnd; activityEnd = nil; end?() }
        func finish() {
            pins.close()
            for end in ends.reversed() { end() }; ends.removeAll()
            endActivity()
        }
        @MainActor func finishChecked(archive: Bool = false) throws -> Int {
            let closed = try pins.closeChecked()
            #if DEBUG
            let reported = archive ? CompanionArchiveOperation.testBoundary.refuseArchiveClose
                : CompanionArchiveOperation.testBoundary.refuseAssociationClose
            if closed > 0 && reported() { throw Pins.CloseFailure() }
            #endif
            for end in ends.reversed() { end() }; ends.removeAll()
            endActivity()
            return closed
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
        init(source: URL, directory: URL) { self.source = source; self.directory = directory }
        func open() throws {
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
        struct CloseFailure: CompanionUnsettledOwnership {}
        func closeChecked() throws -> Int {
            // Consume each number before close. An uncertain close must never be
            // retried against a possibly reused descriptor. Grants remain held.
            let owned = fds; fds.removeAll()
            var failed = false
            for fd in owned { if Darwin.close(fd) != 0 { failed = true } }
            if failed { throw CloseFailure() }
            return owned.count
        }
        func close() { _ = try? closeChecked() }
        deinit { close() }
    }
}
