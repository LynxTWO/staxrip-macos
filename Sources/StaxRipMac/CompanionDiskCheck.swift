import Foundation
import Darwin
import CryptoKit

/// Unused internal disk/source/component settlement, with explicit progressively
/// stronger source-dependent checks. Source observation spooling is explicit;
/// no import or native archive action.
enum CompanionDiskCheck {
    typealias Transaction = OriginalCompanionTransaction
    struct Receipt: Sendable {
        let contents: Transaction.Contents
        let fullContainerMatchesOriginalBytes: Bool
        let originalTrack: CompanionOriginalTrackCheck.Receipt?
        let originalPackets: CompanionOriginalPacketCheck.Receipt?
        let originalIndex: CompanionOriginalIndexCheck.Receipt?
        let originalAudit: CompanionOriginalAuditCheck.Receipt?
        let originalMetadata: CompanionOriginalMetadataCheck.Receipt?
        var originalMetadataSemanticsVerified: Bool { originalMetadata != nil }
    }
    struct Boundary: Sendable {
        var progress: @Sendable (String, Int64) -> Void = { _, _ in }
        var beforeFinal: @Sendable () -> Void = {}
        var originalTrackRead: @Sendable (Int64, Int) -> Void = { _, _ in }
        var originalComponentRead: @Sendable (String, Int64, Int) -> Void = { _, _, _ in }
    }
    #if DEBUG
    @TaskLocal static var testBoundary = Boundary()
    #endif
    private final class Cancellation: @unchecked Sendable {
        private let lock = NSLock(); private var requested = false
        func cancel() { lock.withLock { requested = true } }
        func check() throws { if lock.withLock({ requested }) { throw CancellationError() } }
    }
    private static func failure() -> NativeExportError { .invalid("Companion disk verification refused. No successful integrity receipt.") }
    /// Integrity only. Original track/configuration/packet/RPU semantics are not inferred.
    static func verify(source: URL, stage: URL, contents: Transaction.Contents) async throws -> Receipt {
        try await settle(source: source, stage: stage, contents: contents, originalTrack: false, originalPackets: false, originalIndex: false, originalAudit: false)
    }
    /// Partial native semantic prerequisite, never full original-components admission.
    static func verifyOriginalTrack(source: URL, stage: URL, contents: Transaction.Contents) async throws -> Receipt {
        try await settle(source: source, stage: stage, contents: contents, originalTrack: true, originalPackets: false, originalIndex: false, originalAudit: false)
    }
    /// Source packet/raw-RPU prerequisite only; index/audit/manifest semantics remain false.
    static func verifyOriginalPackets(source: URL, stage: URL, contents: Transaction.Contents) async throws -> Receipt {
        try await settle(source: source, stage: stage, contents: contents, originalTrack: true, originalPackets: true, originalIndex: false, originalAudit: false)
    }
    /// Persisted original index/manifest prerequisite; audit/metadata semantics remain false.
    static func verifyOriginalIndexAndManifest(source: URL, stage: URL, contents: Transaction.Contents) async throws -> Receipt {
        try await settle(source: source, stage: stage, contents: contents, originalTrack: true, originalPackets: true, originalIndex: true, originalAudit: false)
    }
    /// Stored audit framing/source facts; compact metadata truth remains unverified.
    static func verifyOriginalAudit(source: URL, stage: URL, contents: Transaction.Contents) async throws -> Receipt {
        try await settle(source: source, stage: stage, contents: contents, originalTrack: true, originalPackets: true, originalIndex: true, originalAudit: true)
    }
    /// Complete source-dependent original component comparison; not a portable importer or release action.
    static func verifyOriginalMetadata(source: URL, stage: URL, contents: Transaction.Contents,
                                       tool: CompanionMetadataProcess.Tool) async throws -> Receipt {
        try await settle(source: source, stage: stage, contents: contents, originalTrack: true, originalPackets: true,
                         originalIndex: true, originalAudit: true, metadataTool: tool)
    }
    /// Explicit read-only review of surviving files against the original source.
    /// No lost coordinator receipt, path discovery, import or cleanup authority.
    static func reviewOriginalCandidate(source: URL, candidate: URL, retention: Transaction.Retention,
                                        tool: CompanionMetadataProcess.Tool) async throws -> Receipt {
        try await settle(source: source, stage: candidate, input: .candidate(retention), originalTrack: true,
                         originalPackets: true, originalIndex: true, originalAudit: true, metadataTool: tool)
    }
    struct SourceSpoolReceipt: Sendable {
        let sourceID: Transaction.FileID
        let sourceBytes: Int64
        let sourceSHA256: String
        let track: CompanionOriginalTrackCheck.Receipt
        let packets: CompanionOriginalPacketCheck.Receipt
        let timestampScale: UInt64
        let unknownSegment: Bool
        let independentSourceFrameAssociationVerified = false
        let editedPictureSemanticsVerified = false
    }
    struct SourceFrameReceipt: Sendable {
        let source: SourceSpoolReceipt
        let decoder: DolbyDecoderStream.Receipt
        let independentSourceFrameAssociationVerified = true
        let editedPictureSemanticsVerified = false
    }
    /// Fixed decoder observations bound to independently reconstructed original
    /// source facts. Summary values still rely on the admitted decoder implementation.
    struct SourceSampleReceipt: Sendable {
        let source: SourceSpoolReceipt
        let decoder: DolbyDecoderStream.Receipt
        let independentSourceFrameAssociationVerified = true
        let independentSampleSourceAssociationVerified = true
        let independentSampleValuesVerified = false
        let editedPictureSemanticsVerified = false
    }
    private struct DecoderRequest: Sendable {
        var profile: DolbyDecoderStream.Profile = .metadata
        let tool: DolbyDecoderProcess.Tool
        let threads: Int
        let timeout: Double
    }
    /// Unused development association. Caller owns explicit empty private folder
    /// and source access; this establishes no release or edited-picture admission.
    static func associateOriginalFrames(source: URL, in directory: URL, tool: DolbyDecoderProcess.Tool,
                                        threads: Int = 4, timeout: Double = 120,
                                        limits: DolbyAssociationSpool.Limits = .init()) async throws -> SourceFrameReceipt {
        guard [1,4].contains(threads), timeout.isFinite, timeout > 0, timeout <= 120 else { throw failure() }
        let result=try await sourceWork(source:source,in:directory,limits:limits,
                                       decoder:.init(tool:tool,threads:threads,timeout:timeout))
        guard let decoder=result.1 else { throw failure() }
        return .init(source:result.0,decoder:decoder)
    }
    /// Distinct development sample path on the same pinned source/open-store worker.
    /// Caller owns folder/access; no resource controller, edits or release action.
    static func associateOriginalSamples(source: URL, in directory: URL, tool: DolbyDecoderProcess.Tool,
                                         threads: Int = 4, timeout: Double = 120,
                                         limits: DolbyAssociationSpool.Limits = .init()) async throws -> SourceSampleReceipt {
        guard [1,4].contains(threads), timeout.isFinite, timeout > 0, timeout <= 120 else { throw failure() }
        let result = try await sourceWork(source: source, in: directory, limits: limits,
            decoder: .init(profile: .baseSamples, tool: tool, threads: threads, timeout: timeout))
        guard let decoder = result.1 else { throw failure() }
        return .init(source: result.0, decoder: decoder)
    }
    struct SourceOwnershipFailure: CompanionUnsettledOwnership {}
    /// Source-only observations into an exclusive disposable database. Caller
    /// owns the empty private folder/access and retains it on uncertain close.
    /// Neither companion equality nor decoder association follows from this pass.
    static func spoolOriginalSource(source: URL, in directory: URL,
                                    limits: DolbyAssociationSpool.Limits = .init()) async throws -> SourceSpoolReceipt {
        try await sourceWork(source:source,in:directory,limits:limits,decoder:nil).0
    }
    private static func sourceWork(source: URL, in directory: URL, limits: DolbyAssociationSpool.Limits,
                                   decoder: DecoderRequest?) async throws -> (SourceSpoolReceipt,DolbyDecoderStream.Receipt?) {
        try Task.checkCancellation()
        let cancelled = Cancellation()
        #if DEBUG
        let boundary = testBoundary
        let decoderBoundary = DolbyDecoderProcess.testBoundary
        #else
        let boundary = Boundary()
        let decoderBoundary = DolbyDecoderProcess.Boundary()
        #endif
        let result: (SourceSpoolReceipt,DolbyDecoderStream.Receipt?) = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue(label: "StaxRip.original-source-spool", qos: .userInitiated).async {
                    continuation.resume(with: Result {
                        try cancelled.check()
                        let file = try File(url: source, maximum: 1 << 40)
                        let outcome = Result {
                            let hash = try file.hash(cancelled: cancelled, original: nil) { boundary.progress("source", $0) }
                            try file.check(source)
                            let view = ReadView(sourceBytes: file.bytes, source: { offset, count in
                                try cancelled.check()
                                guard offset >= 0, count >= 0, count <= 1 << 20,
                                      offset <= file.bytes, Int64(count) <= file.bytes - offset else { throw failure() }
                                boundary.originalTrackRead(offset, count)
                                return try file.read(offset: offset, count: count, cancelled: cancelled)
                            }, component: { _ in throw failure() }, checkpoint: cancelled.check)
                            let receipt = try DolbyAssociationSpool.withSpool(in: directory, sourceBytes: file.bytes,
                                                                            limits: limits, checkpoint: cancelled.check) { spool in
                                let track = try CompanionOriginalTrackCheck.readSource(view)
                                var timing: (UInt64, Bool)?
                                let packets = try CompanionOriginalPacketCheck.readSource(view, track: track, begin: { scale, unknown in
                                    guard timing == nil else { throw failure() }; timing = (scale, unknown)
                                }, observe: { try spool.append($0) })
                                _ = try spool.finishSourcePass(expected: .init(packets: packets.packets, rpus: packets.records))
                                guard let timing else { throw failure() }
                                var decoded: DolbyDecoderStream.Receipt?
                                if let decoder {
                                    try spool.startDecoderPass(profile: decoder.profile)
                                    // No second worker, nested async wait or closed-store adoption.
                                    let actual: DolbyDecoderStream.Receipt
                                    switch decoder.profile {
                                    case .metadata:
                                        actual = try DolbyDecoderProcess.runOwned(tool:decoder.tool,source:source,
                                            threads:decoder.threads,observe:{ try spool.acceptDecoderRow($0,track:track) },
                                            timeout:decoder.timeout,checkCancellation:cancelled.check,boundary:decoderBoundary)
                                    case .baseSamples:
                                        actual = try DolbyDecoderProcess.runOwnedSamples(tool:decoder.tool,source:source,
                                            threads:decoder.threads,observeSamples:{ try spool.acceptSampleObservation($0) },
                                            observe:{ try spool.acceptDecoderRow($0,track:track) },
                                            timeout:decoder.timeout,checkCancellation:cancelled.check,boundary:decoderBoundary)
                                    case .cropSamples: throw Self.failure()
                                    }
                                    guard actual.source == SourceFingerprint(sha256:hash,byteCount:file.bytes),
                                          actual.configurationSHA256 == track.configurationSHA256,
                                          actual.packets == packets.packets, actual.frames == packets.packets else { throw failure() }
                                    try spool.finishDecoderPass(actual); decoded=actual
                                }
                                let finalHash = try file.hash(cancelled: cancelled, original: nil) { boundary.progress("source-recheck", $0) }
                                guard finalHash == hash else { throw failure() }
                                boundary.beforeFinal()
                                try file.check(source); try cancelled.check()
                                return (SourceSpoolReceipt(sourceID: file.id, sourceBytes: file.bytes, sourceSHA256: hash,
                                    track: track, packets: packets, timestampScale: timing.0, unknownSegment: timing.1),decoded)
                            }
                            try file.check(source); try cancelled.check()
                            return receipt
                        }
                        // An uncertain actual close supersedes success or ordinary
                        // refusal. The caller must retain its owned folder/access.
                        try file.closeChecked()
                        return try outcome.get()
                    })
                }
            }
        } onCancel: { cancelled.cancel() }
        try Task.checkCancellation(); return result
    }
    private enum Input: Sendable {
        case provided(Transaction.Contents), candidate(Transaction.Retention)
        var retention: Transaction.Retention {
            switch self { case .provided(let c): return c.retention; case .candidate(let r): return r }
        }
        var provided: Transaction.Contents? {
            if case .provided(let c) = self { return c }; return nil
        }
    }
    struct ReadView {
        let sourceBytes: Int64
        let source: (Int64, Int) throws -> Data
        let component: (String) throws -> Data
        let checkpoint: () throws -> Void
        var componentBytes: (String) throws -> Int64 = { _ in throw failure() }
        var componentRead: (String, Int64, Int) throws -> Data = { _, _, _ in throw failure() }
    }
    private static func settle(source: URL, stage: URL, contents: Transaction.Contents, originalTrack: Bool, originalPackets: Bool, originalIndex: Bool, originalAudit: Bool, metadataTool: CompanionMetadataProcess.Tool? = nil) async throws -> Receipt {
        try await settle(source: source, stage: stage, input: .provided(contents), originalTrack: originalTrack,
                         originalPackets: originalPackets, originalIndex: originalIndex, originalAudit: originalAudit, metadataTool: metadataTool)
    }
    private static func settle(source: URL, stage: URL, input: Input, originalTrack: Bool, originalPackets: Bool,
                               originalIndex: Bool, originalAudit: Bool, metadataTool: CompanionMetadataProcess.Tool? = nil) async throws -> Receipt {
        try Task.checkCancellation()
        let cancelled = Cancellation()
        #if DEBUG
        let boundary = testBoundary
        let metadataBoundary = CompanionMetadataProcess.testBoundary
        #else
        let boundary = Boundary()
        let metadataBoundary = CompanionMetadataProcess.Boundary()
        #endif
        let result: Receipt = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue(label: "StaxRip.companion-disk-check", qos: .userInitiated).async {
                    continuation.resume(with: Result {
                        try check(source: source, stage: stage, input: input, originalTrack: originalTrack, originalPackets: originalPackets, originalIndex: originalIndex, originalAudit: originalAudit, metadataTool: metadataTool, metadataBoundary: metadataBoundary, cancelled: cancelled, boundary: boundary)
                    })
                }
            }
        } onCancel: { cancelled.cancel() }
        try Task.checkCancellation(); return result
    }
    private static func check(source url: URL, stage urlStage: URL, input: Input,
                              originalTrack: Bool, originalPackets: Bool, originalIndex: Bool, originalAudit: Bool, metadataTool: CompanionMetadataProcess.Tool?, metadataBoundary: CompanionMetadataProcess.Boundary, cancelled: Cancellation, boundary: Boundary) throws -> Receipt {
        try cancelled.check()
        let source = try File(url: url, maximum: 1 << 40), directory = try Directory(urlStage)
        let limits = input.retention.limits, expected = Set(limits.keys), provided = input.provided
        guard try directory.names() == expected else { throw failure() }
        if let c = provided {
            guard source.id == c.sourceID, directory.id == c.stageID, source.bytes == c.sourceBytes,
                  (1...2_000_000).contains(c.packets), (1...2_000_000).contains(c.records),
                  (0...4_000_000_000_000).contains(c.enhancementNALs), c.members.count == expected.count,
                  Set(c.members.map(\.name)) == expected else { throw failure() }
        }
        let sourceHash = try source.hash(cancelled: cancelled, original: nil, progress: { count in
            #if DEBUG
            boundary.progress("source", count)
            #endif
        })
        if let c = provided { guard sourceHash == c.sourceSHA256 else { throw failure() } }
        var opened: [String: File] = [:], actualMembers: [ResultSetStaging.Member] = []
        defer { withExtendedLifetime((source, directory, opened)) {} }
        for name in expected.sorted() {
            try cancelled.check()
            guard let maximum = limits[name] else { throw failure() }
            let file = try File(name: name, directory: directory.fd, maximum: maximum)
            opened[name] = file
            if let c = provided {
                guard let member = c.members.first(where: { $0.name == name }), (1...maximum).contains(member.byteCount),
                      file.bytes == member.byteCount else { throw failure() }
            }
            let original = name == "original-container.mkv" ? source : nil
            if original != nil { guard file.bytes == source.bytes else { throw failure() } }
            let digest = try file.hash(cancelled: cancelled, original: original, progress: { count in
                #if DEBUG
                boundary.progress(name, count)
                #endif
            })
            if let c = provided {
                guard let member = c.members.first(where: { $0.name == name }), file.bytes == member.byteCount,
                      digest == member.sha256 else { throw failure() }
            }
            actualMembers.append(.init(name: name, byteCount: file.bytes, sha256: digest))
        }
        let contents: Transaction.Contents
        if let c = provided { contents = c }
        else {
            guard let manifest = opened["manifest.json"], manifest.bytes <= 1 << 20 else { throw failure() }
            let bytes = try manifest.read(offset: 0, count: Int(manifest.bytes), cancelled: cancelled)
            #if DEBUG
            boundary.originalComponentRead("manifest.json", 0, Int(manifest.bytes))
            #endif
            try cancelled.check()
            // Only bootstrap bounded count claims. D111 then admits the whole
            // exact manifest schema and D110 reconstructs those counts from source.
            let claims = try CompanionArchiveJSON.object(bytes, maximum: 1 << 20)
            contents = .init(retention: input.retention, sourceID: source.id, stageID: directory.id,
                sourceBytes: source.bytes, sourceSHA256: sourceHash,
                packets: Int64(try CompanionArchiveJSON.unsigned(claims, "packets", 1...2_000_000)),
                records: Int64(try CompanionArchiveJSON.unsigned(claims, "records", 1...2_000_000)),
                enhancementNALs: Int64(try CompanionArchiveJSON.unsigned(claims, "enhancement_nals", 0...4_000_000_000_000)),
                members: actualMembers)
        }
        let track: CompanionOriginalTrackCheck.Receipt?
        let packets: CompanionOriginalPacketCheck.Receipt?
        let index: CompanionOriginalIndexCheck.Receipt?
        let audit: CompanionOriginalAuditCheck.Receipt?
        let metadata: CompanionOriginalMetadataCheck.Receipt?
        if originalTrack {
            let view = ReadView(sourceBytes: source.bytes, source: { offset, count in
                guard offset >= 0, count >= 0, count <= 1 << 20, offset <= source.bytes,
                      Int64(count) <= source.bytes - offset else { throw failure() }
                let data = try source.read(offset: offset, count: count, cancelled: cancelled)
                #if DEBUG
                boundary.originalTrackRead(offset, count)
                #endif
                try cancelled.check(); return data
            }, component: { name in
                guard ["original-track-entry-payload.bin", "hevc-configuration.bin"].contains(name),
                      let file = opened[name], file.bytes <= 1 << 20 else { throw failure() }
                return try file.read(offset: 0, count: Int(file.bytes), cancelled: cancelled)
            }, checkpoint: { try cancelled.check() }, componentBytes: { name in
                guard ["original-rpu.bin", "rpu-index.jsonl", "manifest.json", "source-audit.jsonl"].contains(name), let file = opened[name] else { throw failure() }
                return file.bytes
            }, componentRead: { name, offset, count in
                guard ["original-rpu.bin", "rpu-index.jsonl", "manifest.json", "source-audit.jsonl"].contains(name), let file = opened[name], offset >= 0,
                      count >= 0, count <= 1 << 20, offset <= file.bytes,
                      Int64(count) <= file.bytes - offset else { throw failure() }
                let data = try file.read(offset: offset, count: count, cancelled: cancelled)
                #if DEBUG
                boundary.originalComponentRead(name, offset, count)
                #endif
                try cancelled.check(); return data
            })
            let selected = try CompanionOriginalTrackCheck.read(view)
            track = selected
            if originalAudit {
                let checked = try CompanionOriginalAuditCheck.read(view, track: selected, contents: contents)
                audit = checked; index = checked.index; packets = checked.index.packets
                if let tool = metadataTool {
                    metadata = try CompanionOriginalMetadataCheck.read(view, source: url, contents: contents, audit: checked, tool: tool, boundary: metadataBoundary)
                } else { metadata = nil }
            } else if originalIndex {
                metadata = nil; audit = nil
                let checked = try CompanionOriginalIndexCheck.read(view, track: selected, contents: contents)
                index = checked; packets = checked.packets
            } else if originalPackets {
                metadata = nil; audit = nil; index = nil
                let result = try CompanionOriginalPacketCheck.read(view, track: selected)
                guard result.packets == contents.packets, result.records == contents.records,
                      result.enhancementNALs == contents.enhancementNALs else { throw failure() }
                packets = result
            } else { packets = nil; index = nil; audit = nil; metadata = nil }
        } else { track = nil; packets = nil; index = nil; audit = nil; metadata = nil }
        #if DEBUG
        boundary.beforeFinal()
        #endif
        try cancelled.check(); try source.check(url); try directory.check()
        guard try directory.names() == expected else { throw failure() }
        for (name, file) in opened { try cancelled.check(); try file.check(name: name, directory: directory.fd) }
        try cancelled.check()
        return .init(contents: contents, fullContainerMatchesOriginalBytes: contents.retention == .entireContainer, originalTrack: track, originalPackets: packets, originalIndex: index, originalAudit: audit, originalMetadata: metadata)
    }
    private static func same(_ a: stat, _ b: stat) -> Bool {
        Transaction.FileID(a) == Transaction.FileID(b) && a.st_mode == b.st_mode && a.st_uid == b.st_uid &&
            a.st_nlink == b.st_nlink && a.st_size == b.st_size &&
            a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec &&
            a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
    }
    private final class File {
        let fd: Int32, initial: stat
        private var closed = false
        var id: Transaction.FileID { .init(initial) }
        var bytes: Int64 { initial.st_size }
        init(url: URL, maximum: Int64) throws {
            guard url.isFileURL, !url.path.utf8.contains(0) else { throw failure() }
            let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
            guard descriptor >= 0 else { throw failure() }
            var info = stat(), path = stat()
            guard fstat(descriptor, &info) == 0, lstat(url.path, &path) == 0,
                  info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), (1...maximum).contains(info.st_size), same(info, path) else {
                Darwin.close(descriptor); throw failure()
            }
            fd = descriptor; initial = info
        }
        init(name: String, directory: Int32, maximum: Int64) throws {
            // Name comes only from the fixed exact membership/receipt schema above.
            let descriptor = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
            guard descriptor >= 0 else { throw failure() }
            var info = stat(), path = stat()
            guard fstat(descriptor, &info) == 0, fstatat(directory, name, &path, AT_SYMLINK_NOFOLLOW) == 0,
                  info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), info.st_uid == geteuid(),
                  info.st_mode & 0o7777 == 0o600, info.st_nlink == 1, (1...maximum).contains(info.st_size), same(info, path) else {
                Darwin.close(descriptor); throw failure()
            }
            fd = descriptor; initial = info
        }
        deinit { if !closed { Darwin.close(fd) } }
        func closeChecked() throws {
            guard !closed else { throw SourceOwnershipFailure() }
            closed = true // Never retry a possibly reused descriptor after close failure.
            guard Darwin.close(fd) == 0 else { throw SourceOwnershipFailure() }
        }
        func check(_ url: URL) throws {
            var info = stat(), path = stat()
            guard fstat(fd, &info) == 0, lstat(url.path, &path) == 0, same(initial, info), same(initial, path) else { throw failure() }
        }
        func check(name: String, directory: Int32) throws {
            var info = stat(), path = stat()
            guard fstat(fd, &info) == 0, fstatat(directory, name, &path, AT_SYMLINK_NOFOLLOW) == 0,
                  same(initial, info), same(initial, path) else { throw failure() }
        }
        func read(offset: Int64, count: Int, cancelled: Cancellation) throws -> Data {
            var data = Data(count: count), completed = 0
            while completed < count {
                try cancelled.check()
                let n = data.withUnsafeMutableBytes { p in pread(fd, p.baseAddress!.advanced(by: completed), count - completed, offset + Int64(completed)) }
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw failure() }; completed += n; try cancelled.check()
            }
            return data
        }
        func hash(cancelled: Cancellation, original: File?, progress: (Int64) -> Void) throws -> String {
            var hasher = SHA256(), offset: Int64 = 0
            while offset < bytes {
                try cancelled.check()
                let count = Int(min(1 << 20, bytes - offset)), data = try read(offset: offset, count: count, cancelled: cancelled)
                if let original { guard try original.read(offset: offset, count: count, cancelled: cancelled) == data else { throw failure() } }
                hasher.update(data: data); offset += Int64(count); progress(offset); try cancelled.check()
            }
            return DolbyInspection.hex(hasher.finalize())
        }
    }
    private final class Directory {
        let url: URL, fd: Int32, initial: stat
        var id: Transaction.FileID { .init(initial) }
        init(_ url: URL) throws {
            guard url.isFileURL, !url.path.utf8.contains(0) else { throw failure() }
            let descriptor = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else { throw failure() }
            var info = stat(), path = stat()
            guard fstat(descriptor, &info) == 0, lstat(url.path, &path) == 0, info.st_uid == geteuid(),
                  info.st_mode & 0o7777 == 0o700, same(info, path) else { Darwin.close(descriptor); throw failure() }
            self.url = url; fd = descriptor; initial = info
        }
        deinit { Darwin.close(fd) }
        func check() throws {
            var info = stat(), path = stat()
            guard fstat(fd, &info) == 0, lstat(url.path, &path) == 0, same(initial, info), same(initial, path) else { throw failure() }
        }
        func names() throws -> Set<String> {
            let copy = fcntl(fd, F_DUPFD_CLOEXEC, 0)
            guard copy >= 0 else { throw failure() }
            guard let entries = fdopendir(copy) else { Darwin.close(copy); throw failure() }
            defer { closedir(entries) }
            rewinddir(entries) // Duplicate descriptors share directory position.
            var result: Set<String> = []
            while true {
                errno = 0
                guard let entry = readdir(entries) else { guard errno == 0 else { throw failure() }; break }
                let count = Int(entry.pointee.d_namlen)
                guard (1...128).contains(count) else { throw failure() }
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: UInt8.self, capacity: count) { String(decoding: UnsafeBufferPointer(start: $0, count: count), as: UTF8.self) }
                }
                if name == "." || name == ".." { continue }
                guard result.count < 16, result.insert(name).inserted else { throw failure() }
            }
            return result
        }
    }
}
