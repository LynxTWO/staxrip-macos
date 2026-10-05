import Foundation
import CryptoKit
import Darwin
import Testing
@testable import StaxRipMac

struct ResultSetStagingTests {
    private func folder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("result-set-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
    private func fixture(_ stage: ResultSetStaging, marker: UInt8 = 7) throws -> [ResultSetStaging.Member] {
        // Opaque generated component bytes: no playable media/archive semantics claimed.
        let payloads: [(String, Data)] = [
            ("media.bin", Data(repeating: marker, count: 2 * 1024 * 1024 + 17)),
            ("original-metadata.bin", Data([marker, 8, 9, 10])),
            ("manifest.json", Data("{\"fixture\":true}".utf8))]
        return try payloads.map { name, data in
            try data.write(to: stage.fileURL(name))
            return .init(name: name, byteCount: Int64(data.count), sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
        }
    }
    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    @Test func exactVerifiedSetMovesTogetherAndCannotBeDiscardedAfterCommit() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let stage = try ResultSetStaging.create(in: root), members = try fixture(stage)
        let original = try stage.fileURL("media.bin"), owned = original.deletingLastPathComponent()
        let inode = try FileManager.default.attributesOfItem(atPath: owned.path)[.systemFileNumber] as? NSNumber
        let result = try await stage.publish(as: "result", members: members)
        #expect(result.verifiedBytes == members.reduce(0) { $0 + $1.byteCount })
        #expect(result.memberCount == 3)
        #expect(!exists(owned))
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: result.directory.path)) == Set(members.map(\.name)))
        #expect(try FileManager.default.attributesOfItem(atPath: result.directory.path)[.systemFileNumber] as? NSNumber == inode)
        for member in members {
            let data = try Data(contentsOf: result.directory.appendingPathComponent(member.name))
            #expect(Int64(data.count) == member.byteCount)
            #expect(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == member.sha256)
        }
        #expect(throws: (any Error).self) { try stage.discard() }
        await #expect(throws: (any Error).self) { try await stage.publish(as: "another", members: members) }
        #expect(exists(result.directory) && !exists(root.appendingPathComponent("another")))
    }

    @Test(arguments: ["file", "directory", "symlink"])
    func destinationCollisionNeverReplacesAnything(kind: String) async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let stage = try ResultSetStaging.create(in: root), members = try fixture(stage)
        let result = root.appendingPathComponent("result")
        switch kind {
        case "file": try Data("keep".utf8).write(to: result)
        case "directory": try FileManager.default.createDirectory(at: result, withIntermediateDirectories: false)
        default: try FileManager.default.createSymbolicLink(at: result, withDestinationURL: root.appendingPathComponent("absent"))
        }
        var before = stat(); try #require(lstat(result.path, &before) == 0)
        await #expect(throws: (any Error).self) { try await stage.publish(as: "result", members: members) }
        var after = stat(); try #require(lstat(result.path, &after) == 0)
        #expect(before.st_ino == after.st_ino && before.st_mode == after.st_mode)
        if kind == "file" { #expect(try Data(contentsOf: result) == Data("keep".utf8)) }
        if kind == "directory" { #expect(try FileManager.default.contentsOfDirectory(atPath: result.path).isEmpty) }
        if kind == "symlink" { #expect(try FileManager.default.destinationOfSymbolicLink(atPath: result.path) == root.appendingPathComponent("absent").path) }
        let retry = try await stage.publish(as: "new-result", members: members)
        #expect(retry.memberCount == 3 && exists(retry.directory))
    }

    @Test(arguments: ["missing", "extra", "length", "hash", "manifest-hash"])
    func incompleteOrCorruptRequestedSetRefusesAndLeavesExistingSourceAlone(change: String) async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.bin"), sourceData = Data("generated source".utf8)
        try sourceData.write(to: source)
        let stage = try ResultSetStaging.create(in: root), members = try fixture(stage)
        let archive = try stage.fileURL("original-metadata.bin")
        switch change {
        case "missing": try FileManager.default.removeItem(at: archive)
        case "extra": try Data([1]).write(to: stage.fileURL("unexpected.bin"))
        case "length": try Data([1]).write(to: archive)
        case "hash": try Data([1, 2, 3, 4]).write(to: archive)
        default: try Data(repeating: 32, count: Int(members[2].byteCount)).write(to: stage.fileURL("manifest.json"))
        }
        await #expect(throws: (any Error).self) { try await stage.publish(as: "result", members: members) }
        #expect(!exists(root.appendingPathComponent("result")))
        #expect(try Data(contentsOf: source) == sourceData)
        try stage.discard()
    }

    @Test(arguments: ["symlink", "hardlink", "fifo", "directory"])
    func linkedAndSpecialMembersAreNeverTraversed(kind: String) async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let stage = try ResultSetStaging.create(in: root), members = try fixture(stage)
        let archive = try stage.fileURL("original-metadata.bin"), protected = root.appendingPathComponent("protected.bin")
        let bytes = try Data(contentsOf: archive); try bytes.write(to: protected)
        try FileManager.default.removeItem(at: archive)
        switch kind {
        case "symlink": try FileManager.default.createSymbolicLink(at: archive, withDestinationURL: protected)
        case "hardlink": try FileManager.default.linkItem(at: protected, to: archive)
        case "fifo": try #require(mkfifo(archive.path, 0o600) == 0)
        default: try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: false)
        }
        await #expect(throws: (any Error).self) { try await stage.publish(as: "result", members: members) }
        #expect(!exists(root.appendingPathComponent("result")))
        if kind == "directory" {
            // Cleanup refuses recursion; the caller must settle its known producer.
            #expect(throws: (any Error).self) { try stage.discard() }
            try FileManager.default.removeItem(at: archive)
        }
        try stage.discard()
        #expect(try Data(contentsOf: protected) == bytes)
    }

    @Test(arguments: ["../escape", ".hidden", "a/b", "a\u{0}b", "", String(repeating: "x", count: 121)])
    func untrustedNamesCannotEscapeTheStage(name: String) async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let stage = try ResultSetStaging.create(in: root), members = try fixture(stage)
        #expect(throws: (any Error).self) { try stage.fileURL(name) }
        await #expect(throws: (any Error).self) { try await stage.publish(as: name, members: members) }
        try stage.discard()
    }

    @Test func malformedReceiptsRefuseBeforePublication() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let stage = try ResultSetStaging.create(in: root), members = try fixture(stage)
        let bad: [[ResultSetStaging.Member]] = [Array(members.dropLast()), members + [members[0]],
            [.init(name: "media.bin", byteCount: 0, sha256: members[0].sha256)] + Array(members.dropFirst()),
            [.init(name: "media.bin", byteCount: Int64.max, sha256: members[0].sha256)] + Array(members.dropFirst()),
            [.init(name: "media.bin", byteCount: members[0].byteCount, sha256: String(repeating: "z", count: 64))] + Array(members.dropFirst()),
            Array(members.dropLast()) + [.init(name: "other.json", byteCount: 1, sha256: members[2].sha256)],
            Array(members.dropLast()) + [.init(name: "manifest.json", byteCount: 1_048_577, sha256: members[2].sha256)]]
        for rows in bad {
            await #expect(throws: (any Error).self) { try await stage.publish(as: "result", members: rows) }
        }
        #expect(!exists(root.appendingPathComponent("result")))
        try stage.discard()
    }

    @Test(arguments: ["rewrite", "replace", "append", "extra"])
    func mutationAfterHashingRefuses(change: String) async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let stage = try ResultSetStaging.create(in: root), members = try fixture(stage)
        let archive = try stage.fileURL("original-metadata.bin"), extra = try stage.fileURL("extra.bin")
        await ResultSetStaging.$testBoundary.withValue(.init(beforeCommit: {
            switch change {
            case "rewrite": try Data([1, 2, 3, 4]).write(to: archive)
            case "replace": try Data([7, 8, 9, 10]).write(to: archive, options: .atomic)
            case "append":
                let handle = try FileHandle(forWritingTo: archive); defer { try? handle.close() }
                try handle.seekToEnd(); try handle.write(contentsOf: Data([1]))
            default: try Data([1]).write(to: extra)
            }
        })) {
            await #expect(throws: (any Error).self) { try await stage.publish(as: "result", members: members) }
        }
        #expect(!exists(root.appendingPathComponent("result")))
        try stage.discard()
    }

    @Test func substitutedStageIsNeitherPublishedNorRemoved() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let stage = try ResultSetStaging.create(in: root), members = try fixture(stage)
        let owned = try stage.fileURL("media.bin").deletingLastPathComponent()
        let moved = root.appendingPathComponent("moved-stage")
        try FileManager.default.moveItem(at: owned, to: moved)
        try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: false)
        let sentinel = owned.appendingPathComponent("keep.bin"); try Data([42]).write(to: sentinel)
        await #expect(throws: (any Error).self) { try await stage.publish(as: "result", members: members) }
        #expect(throws: (any Error).self) { try stage.discard() }
        #expect(try Data(contentsOf: sentinel) == Data([42]))
        #expect(exists(moved.appendingPathComponent("media.bin")))
        #expect(!exists(root.appendingPathComponent("result")))
    }

    private final class Gate: @unchecked Sendable {
        let release = DispatchSemaphore(value: 0)
        let entered: AsyncStream<Bool>
        private let signal: AsyncStream<Bool>.Continuation
        private let lock = NSLock()
        private var didEnter = false
        init() {
            let pair = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
            entered = pair.stream; signal = pair.continuation
        }
        func holdOnce() throws {
            let first = lock.withLock { if didEnter { return false }; didEnter = true; return true }
            if first {
                #expect(!Thread.isMainThread)
                signal.yield(true); signal.finish()
                guard release.wait(timeout: .now() + 30) == .success else { throw NativeExportError.invalid("Generated semantic gate was not released") }
            }
        }
        func waitForEntry() async throws {
            var iterator = entered.makeAsyncIterator()
            try #require(await iterator.next() == true)
        }
    }

    @Test func cancellationBeforeCommitAwaitsWorkerAndPreservesOwnedCleanup() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let stage = try ResultSetStaging.create(in: root), members = try fixture(stage), gate = Gate()
        let task = Task {
            try await ResultSetStaging.$testBoundary.withValue(.init(progress: { _ in try gate.holdOnce() })) {
                try await stage.publish(as: "result", members: members)
            }
        }
        try await gate.waitForEntry(); task.cancel()
        #expect(throws: (any Error).self) { try stage.discard() }
        await #expect(throws: (any Error).self) { try await stage.publish(as: "second", members: members) }
        #expect(!exists(root.appendingPathComponent("result")))
        gate.release.signal()
        await #expect(throws: CancellationError.self) { try await task.value }
        try stage.discard()
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func cancellationAfterCommitReportsTheAlreadyPublishedSet() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let stage = try ResultSetStaging.create(in: root), members = try fixture(stage), gate = Gate()
        let task = Task {
            try await ResultSetStaging.$testBoundary.withValue(.init(afterCommit: { try? gate.holdOnce() })) {
                try await stage.publish(as: "result", members: members)
            }
        }
        try await gate.waitForEntry(); task.cancel()
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("result").path)) == Set(members.map(\.name)))
        #expect(throws: (any Error).self) { try stage.discard() }
        gate.release.signal()
        let result = try await task.value
        #expect(result.memberCount == 3 && exists(result.directory))
        #expect(throws: (any Error).self) { try stage.discard() }
    }

    @Test func alreadyCancelledRequestNeverTakesStageOwnership() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let stage = try ResultSetStaging.create(in: root), members = try fixture(stage)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await stage.publish(as: "result", members: members)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!exists(root.appendingPathComponent("result")))
        try stage.discard()
    }

    @Test func competingStagesPublishExactlyOneIntactSet() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let a = try ResultSetStaging.create(in: root), b = try ResultSetStaging.create(in: root)
        let ma = try fixture(a, marker: 11), mb = try fixture(b, marker: 22)
        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            group.addTask { (try? await a.publish(as: "result", members: ma)) != nil }
            group.addTask { (try? await b.publish(as: "result", members: mb)) != nil }
            var values: [Bool] = []; for await value in group { values.append(value) }; return values
        }
        #expect(results.filter { $0 }.count == 1)
        let result = root.appendingPathComponent("result")
        let media = try Data(contentsOf: result.appendingPathComponent("media.bin"))
        let marker = try #require(media.first)
        #expect(marker == 11 || marker == 22)
        #expect(media.allSatisfy { $0 == marker })
        #expect(try Data(contentsOf: result.appendingPathComponent("original-metadata.bin")).first == marker)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: result.path)) == Set(ma.map(\.name)))
        if marker == 11 { try b.discard() } else { try a.discard() }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["result"])
    }

    private final class Closes: @unchecked Sendable {
        private let lock = NSLock(); private var roles: [ResultSetStaging.CloseRole] = []
        func record(_ role: ResultSetStaging.CloseRole) { lock.withLock { roles.append(role) } }
        func count(_ role: ResultSetStaging.CloseRole) -> Int { lock.withLock { roles.filter { $0 == role }.count } }
    }
    @Test func checkedTransientClosesAndAfterCommitRefusalPreserveActualResult() async throws {
        for refusal in [false, true] {
            let root = try folder(), closes = Closes(); var keep = refusal
            defer { if keep { print("GENERATED_STAGE_TRANSIENT_REVIEW " + root.path) } else { try? FileManager.default.removeItem(at: root) } }
            try await ResultSetStaging.$testBoundary.withValue(.init(closed: { closes.record($0) }, refuseClose: { refusal && $0 == .member("media.bin") })) {
                let stage = try ResultSetStaging.create(in: root), members = try fixture(stage)
                let actual: ResultSetStaging.Published
                do { actual = try await stage.publish(as: "result", members: members); #expect(!refusal) }
                catch let e as ResultSetStaging.SettlementFailure {
                    #expect(refusal && e.closeFailures.count == 1 && e.operationError == nil)
                    #expect(e.closeFailures[0].reportedAfterActualClose && e.closeFailures[0].role == .member("media.bin"))
                    actual = try #require(e.published)
                    #expect(e.intendedStage == actual.directory && e.errorDescription?.contains("was published") == true)
                }
                #expect(actual.directory == root.appendingPathComponent("result") && actual.memberCount == 3)
                #expect(actual.verifiedBytes == members.reduce(0) { $0 + $1.byteCount })
                for member in members { #expect(closes.count(.member(member.name)) == 1); #expect(try Data(contentsOf: actual.directory.appendingPathComponent(member.name)).count == Int(member.byteCount)) }
                #expect(closes.count(.directoryStream) == 2)
                #expect(throws: (any Error).self) { try stage.discard() }
                await #expect(throws: (any Error).self) { try await stage.publish(as: "second", members: members) }
                for member in members { #expect(closes.count(.member(member.name)) == 1) }
                if !refusal { keep = false }
            }
        }
    }
    @Test func streamCloseRefusesBeforePublicationOrAnyDiscardUnlink() async throws {
        for discarding in [false, true] {
            let root = try folder(), closes = Closes()
            defer { print("GENERATED_STAGE_STREAM_REVIEW " + root.path) }
            try await ResultSetStaging.$testBoundary.withValue(.init(closed: { closes.record($0) }, refuseClose: { $0 == .directoryStream })) {
                let stage = try ResultSetStaging.create(in: root), members = try fixture(stage)
                let before = try members.map { try Data(contentsOf: stage.fileURL($0.name)) }
                do {
                    if discarding { try stage.discard() } else { _ = try await stage.publish(as: "result", members: members) }
                    Issue.record("Stream close refusal returned ordinary result")
                } catch let e as ResultSetStaging.SettlementFailure {
                    #expect(e.published == nil && e.closeFailures.count == 1 && e.closeFailures[0].reportedAfterActualClose)
                    #expect(e.intendedStage == stage.originalDirectoryURL)
                }
                #expect(closes.count(.directoryStream) == 1 && !exists(root.appendingPathComponent("result")))
                for (i, member) in members.enumerated() { #expect(try Data(contentsOf: stage.originalDirectoryURL.appendingPathComponent(member.name)) == before[i]) }
                #expect(throws: (any Error).self) { try stage.discard() }
                await #expect(throws: (any Error).self) { try await stage.publish(as: "second", members: members) }
                #expect(closes.count(.directoryStream) == 1)
            }
        }
    }
    @Test func failedMemberAdmissionClosesBeforeRefusalAndPreservesCause() async throws {
        let root = try folder(), closes = Closes(); defer { print("GENERATED_STAGE_MEMBER_REVIEW " + root.path) }
        try await ResultSetStaging.$testBoundary.withValue(.init(closed: { closes.record($0) }, refuseClose: { $0 == .member("media.bin") })) {
            let stage = try ResultSetStaging.create(in: root), members = try fixture(stage)
            try Data([1]).write(to: stage.fileURL("media.bin"))
            do { _ = try await stage.publish(as: "result", members: members); Issue.record("Malformed member returned success") }
            catch let e as ResultSetStaging.SettlementFailure {
                #expect(e.operationError is NativeExportError && e.published == nil && e.closeFailures.count == 1)
                #expect(e.closeFailures[0].reportedAfterActualClose)
            }
            #expect(closes.count(.member("media.bin")) == 1 && closes.count(.directoryStream) == 1)
            #expect(throws: (any Error).self) { try stage.discard() }
            #expect(try Data(contentsOf: stage.originalDirectoryURL.appendingPathComponent("media.bin")) == Data([1]))
        }
    }
    @Test func refusedStreamAdmissionChecksActualDescriptorRollbackWithoutRetry() async throws {
        for reported in [false, true] {
            let root = try folder(), closes = Closes(); defer { print("GENERATED_STAGE_ENUMERATION_REVIEW " + root.path) }
            try await ResultSetStaging.$testBoundary.withValue(.init(closed: { closes.record($0) }, refuseClose: { reported && $0 == .enumerationDescriptor }, refuseStreamAdmission: { true })) {
                let stage = try ResultSetStaging.create(in: root), members = try fixture(stage)
                do { _ = try await stage.publish(as: "result", members: members); Issue.record("Stream admission returned result") }
                catch let e as ResultSetStaging.SettlementFailure { #expect(reported && e.published == nil && e.operationError is NativeExportError) }
                catch { #expect(!reported && error is NativeExportError) }
                #expect(closes.count(.enumerationDescriptor) == 1 && closes.count(.directoryStream) == 0)
                if reported { #expect(throws: (any Error).self) { try stage.fileURL("manifest.json") }; #expect(throws: (any Error).self) { try stage.discard() } }
                else { #expect(try stage.fileURL("manifest.json") == stage.originalDirectoryURL.appendingPathComponent("manifest.json")) }
                #expect(closes.count(.enumerationDescriptor) == 1 && !exists(root.appendingPathComponent("result")))
            }
        }
    }

    @Test func activeCancellationWithMemberCloseRefusalSettlesWorkerAndRetainsCause() async throws {
        let root = try folder(), gate = Gate(), closes = Closes()
        defer { print("GENERATED_CANCELLED_STAGE_CLOSE_REVIEW " + root.path) }
        try await ResultSetStaging.$testBoundary.withValue(.init(progress: { n in if n > 0 { try gate.holdOnce() } }, closed: { closes.record($0) }, refuseClose: { $0 == .member("media.bin") })) {
            let stage = try ResultSetStaging.create(in: root), members = try fixture(stage)
            let task = Task { try await stage.publish(as: "result", members: members) }
            try await gate.waitForEntry(); task.cancel(); gate.release.signal()
            do { _ = try await task.value; Issue.record("Cancelled close refusal returned success") }
            catch let e as ResultSetStaging.SettlementFailure {
                #expect(e.operationError is CancellationError && e.published == nil && e.closeFailures.count == 1)
                #expect(e.closeFailures[0].reportedAfterActualClose)
            }
            #expect(closes.count(.member("media.bin")) == 1 && !exists(root.appendingPathComponent("result")))
            #expect(throws: (any Error).self) { try stage.discard() }
            #expect(closes.count(.member("media.bin")) == 1)
        }
    }
    @Test func creationParentRollbackChecksRealCloseAndPreservesNoDirectoryState() throws {
        for reported in [false, true] {
            let root = try folder(), closes = Closes()
            defer { if reported { print("GENERATED_CREATION_PARENT_REVIEW " + root.path) } else { try? FileManager.default.removeItem(at: root) } }
            try ResultSetStaging.$testBoundary.withValue(.init(closed: { closes.record($0) }, refuseClose: { reported && $0 == .creationParent }, creation: { point, _ in
                if point == "parent-opened" { throw CancellationError() }
            })) { () throws -> Void in
                do { _ = try ResultSetStaging.create(in: root); Issue.record("Creation rollback returned stage") }
                catch let e as ResultSetStaging.CreationSettlementFailure {
                    #expect(reported && !e.directoryCreated && !e.identityEstablished && e.reviewLocator == root)
                    #expect(e.operationError is CancellationError && e.closeFailures.count == 1 && e.closeFailures[0].reportedAfterActualClose)
                    #expect(e.errorDescription?.contains("not created") == true)
                } catch { #expect(!reported && error is CancellationError) }
                #expect(closes.count(.creationParent) == 1 && closes.count(.creationDirectory) == 0)
                #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
            }
        }
    }
    @Test func actualCreationWriteDenialClosesParentWithoutInventingStage() throws {
        let root = try folder(), closes = Closes()
        defer { _ = chmod(root.path, 0o700); try? FileManager.default.removeItem(at: root) }
        try ResultSetStaging.$testBoundary.withValue(.init(closed: { closes.record($0) }, creation: { point, _ in
            if point == "parent-opened" { try #require(chmod(root.path, 0o500) == 0) }
        })) { () throws -> Void in
            do { _ = try ResultSetStaging.create(in: root); Issue.record("POSIX creation denial returned stage") }
            catch { #expect(error is NativeExportError && !(error is any CompanionUnsettledOwnership)); #expect(error.localizedDescription.contains("system error 13")) }
            #expect(closes.count(.creationParent) == 1 && closes.count(.creationDirectory) == 0)
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        }
    }
    @Test func createdDirectoryRollbackClosesEveryOwnedRoleAndRetainsObservedFacts() throws {
        for point in ["directory-created", "directory-opened", "before-transfer"] {
          for reported in [false, true] {
            let root = try folder(), closes = Closes(); defer { print("GENERATED_CREATED_DIRECTORY_REVIEW " + root.path) }
            try ResultSetStaging.$testBoundary.withValue(.init(closed: { closes.record($0) }, refuseClose: { reported && ($0 == .creationParent || $0 == .creationDirectory) }, creation: { step, _ in
                if step == point { throw CancellationError() }
            })) { () throws -> Void in
                do { _ = try ResultSetStaging.create(in: root); Issue.record("Created rollback returned ordinary stage") }
                catch let e as ResultSetStaging.CreationSettlementFailure {
                    #expect(e.directoryCreated && e.identityEstablished == (point == "before-transfer") && e.reviewLocator == e.attemptedStage)
                    #expect(e.operationError is CancellationError)
                    let owned = point == "directory-created" ? 1 : 2
                    #expect(e.closeFailures.count == (reported ? owned : 0))
                    #expect(e.closeFailures.allSatisfy { $0.reportedAfterActualClose })
                    #expect(try FileManager.default.contentsOfDirectory(atPath: e.attemptedStage.path).isEmpty)
                }
                #expect(closes.count(.creationParent) == 1 && closes.count(.creationDirectory) == (point == "directory-created" ? 0 : 1))
                #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).count == 1)
            }
          }
        }
    }
    @Test func creationFinalSubstitutionRefusesWithoutRemovingEitherDirectory() throws {
        let root = try folder(), closes = Closes(), moved = root.appendingPathComponent("moved-created-stage")
        defer { print("GENERATED_CREATION_SUBSTITUTION_REVIEW " + root.path) }
        try ResultSetStaging.$testBoundary.withValue(.init(closed: { closes.record($0) }, creation: { point, attempted in
            if point == "before-transfer" {
                try FileManager.default.moveItem(at: attempted, to: moved)
                try FileManager.default.createDirectory(at: attempted, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                try Data([42]).write(to: attempted.appendingPathComponent("sentinel"))
            }
        })) { () throws -> Void in
            do { _ = try ResultSetStaging.create(in: root); Issue.record("Substituted creation returned stage") }
            catch let e as ResultSetStaging.CreationSettlementFailure {
                #expect(e.directoryCreated && !e.identityEstablished && e.closeFailures.isEmpty && e.operationError is NativeExportError)
                let sentinel = try Data(contentsOf: e.attemptedStage.appendingPathComponent("sentinel"))
                #expect(exists(moved) && sentinel == Data([42]))
            }
            #expect(closes.count(.creationParent) == 1 && closes.count(.creationDirectory) == 1)
        }
    }

    @Test func publishedPinsCloseOnceBeforeReturnAndNeverRetryOnDroppedStage() async throws {
        for refusal in ["none", "directory", "parent", "both"] {
            let root = try folder(), closes = Closes()
            defer { if refusal == "none" { try? FileManager.default.removeItem(at: root) } else { print("GENERATED_PUBLISHED_PIN_REVIEW " + root.path) } }
            try await ResultSetStaging.$testBoundary.withValue(.init(closed: { closes.record($0) }, refuseClose: { role in
                (role == .publishedDirectory && ["directory", "both"].contains(refusal)) || (role == .publishedParent && ["parent", "both"].contains(refusal))
            })) {
                var stage: ResultSetStaging? = try ResultSetStaging.create(in: root)
                let active = try #require(stage), members = try fixture(active)
                let actual: ResultSetStaging.Published
                do { actual = try await active.publish(as: "result", members: members); #expect(refusal == "none") }
                catch let e as ResultSetStaging.SettlementFailure {
                    #expect(refusal != "none" && e.operationError == nil)
                    #expect(e.closeFailures.count == (refusal == "both" ? 2 : 1))
                    #expect(e.closeFailures.allSatisfy { $0.reportedAfterActualClose })
                    actual = try #require(e.published); #expect(e.intendedStage == actual.directory)
                }
                #expect(active.publishedPinsConsumedForTesting)
                #expect(closes.count(.publishedDirectory) == 1 && closes.count(.publishedParent) == 1)
                #expect(actual.verifiedBytes == members.reduce(0) { $0 + $1.byteCount } && actual.memberCount == 3)
                #expect(throws: (any Error).self) { try active.discard() }
                await #expect(throws: (any Error).self) { try await active.publish(as: "second", members: members) }
                for member in members { #expect(try Data(contentsOf: actual.directory.appendingPathComponent(member.name)).count == Int(member.byteCount)) }
                stage = nil
            }
            // The stage's last strong reference ended; callbacks cannot recur in deinit.
            #expect(closes.count(.publishedDirectory) == 1 && closes.count(.publishedParent) == 1)
        }
    }
    @Test func retryablePrecommitRefusalKeepsPinsUntilRealPublication() async throws {
        let root = try folder(), closes = Closes(); defer { try? FileManager.default.removeItem(at: root) }
        try await ResultSetStaging.$testBoundary.withValue(.init(closed: { closes.record($0) })) {
            let stage = try ResultSetStaging.create(in: root), members = try fixture(stage)
            let occupied = root.appendingPathComponent("occupied"); try Data([42]).write(to: occupied)
            await #expect(throws: NativeExportError.self) { try await stage.publish(as: "occupied", members: members) }
            #expect(!stage.publishedPinsConsumedForTesting)
            #expect(closes.count(.publishedDirectory) == 0 && closes.count(.publishedParent) == 0)
            let actual = try await stage.publish(as: "result", members: members)
            #expect(stage.publishedPinsConsumedForTesting)
            #expect(closes.count(.publishedDirectory) == 1 && closes.count(.publishedParent) == 1)
            let prior = try Data(contentsOf: occupied)
            #expect(actual.memberCount == 3 && prior == Data([42]))
        }
    }
    @Test func transientUncertaintyDoesNotQualifyOrConsumeTerminalPinRoles() async throws {
        let root = try folder(), closes = Closes(); defer { print("GENERATED_TRANSIENT_PIN_REVIEW " + root.path) }
        try await ResultSetStaging.$testBoundary.withValue(.init(closed: { closes.record($0) }, refuseClose: { $0 == .member("manifest.json") })) {
            let stage = try ResultSetStaging.create(in: root), members = try fixture(stage)
            do { _ = try await stage.publish(as: "result", members: members); Issue.record("Transient refusal returned success") }
            catch let e as ResultSetStaging.SettlementFailure { #expect(e.published != nil && e.closeFailures.count == 1) }
            #expect(!stage.publishedPinsConsumedForTesting)
            #expect(closes.count(.publishedDirectory) == 0 && closes.count(.publishedParent) == 0)
        }
        // Unchecked fallback is not terminal settlement evidence or review release authority.
        #expect(closes.count(.publishedDirectory) == 0 && closes.count(.publishedParent) == 0)
    }

}
