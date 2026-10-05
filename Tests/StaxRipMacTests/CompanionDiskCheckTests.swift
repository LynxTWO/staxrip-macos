import Foundation
import CryptoKit
import Darwin
import Testing
@testable import StaxRipMac

@Suite(.serialized)
struct CompanionDiskCheckTests {
    typealias Writer = CompanionWriterProcess
    typealias Transaction = OriginalCompanionTransaction
    private struct Fixture {
        let root, source, stage, executable: URL
        var tool: Writer.Tool { get throws { try .development(executable, expectedSHA256: DolbyInspection.hex(SHA256.hash(data: Data(contentsOf: executable)))) } }
        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }
    private static var repo: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    private static func fixture() async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-companion-process-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        do {
            let generated = root.appendingPathComponent("generated")
            try FileManager.default.createDirectory(at: generated, withIntermediateDirectories: false)
            let helpers = try await RustFixtureBuild.generate(.staged, at: generated, copiesIn: root)
            let executable = helpers.writer
            let stage = root.appendingPathComponent("stage")
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            return .init(root: root, source: generated.appendingPathComponent("generated-source.mkv"), stage: stage, executable: executable)
        } catch { try? FileManager.default.removeItem(at: root); throw error }
    }
    private struct Wire: Decodable {
        struct Member: Decodable { let name: String; let bytes: Int64; let sha256: String }
        let retention: String
        let source_file_id, stage_file_id: [UInt64]
        let source_bytes: Int64
        let source_sha256: String
        let packets, records, enhancement_nals: Int64
        let components: [Member]
        let original_components_match_source, source_identity_checked_at_boundaries: Bool?
        let decoded_frame_association: String?
        let immutable_snapshot, stable_importer: Bool?
        func contents() throws -> Transaction.Contents {
            try #require(source_file_id.count == 2 && stage_file_id.count == 2)
            let mode: Transaction.Retention
            switch retention {
            case "metadata", "rpu-and-original-track-metadata-only": mode = .metadataOnly
            case "full", "entire-original-container": mode = .entireContainer
            default: throw NativeExportError.invalid("Unknown generated retention")
            }
            return .init(retention: mode,
                         sourceID: .init(device: source_file_id[0], inode: source_file_id[1]),
                         stageID: .init(device: stage_file_id[0], inode: stage_file_id[1]),
                         sourceBytes: source_bytes, sourceSHA256: source_sha256, packets: packets,
                         records: records, enhancementNALs: enhancement_nals,
                         members: components.map { .init(name: $0.name, byteCount: $0.bytes, sha256: $0.sha256) })
        }
    }

    private func staged(_ mode: Transaction.Retention = .metadataOnly) async throws -> (Fixture, Transaction.Contents) {
        let f = try await Self.fixture()
        do { return (f, try await Writer.run(tool: f.tool, source: f.source, stage: f.stage, retention: mode).contents) }
        catch { f.cleanup(); throw error }
    }
    @Test func actualNativeWriterDiskAndIndependentTestSemanticsPublishBothModes() async throws {
        let f = try await Self.fixture(); defer { f.cleanup() }
        let original = try Data(contentsOf: f.source), tool = try f.tool
        let reader = f.root.appendingPathComponent("staxrip-dolby-metadata-audit")
        let adapter = Self.repo.appendingPathComponent("Tools/DolbyCompanionCheck/native_transaction_fixture.py")
        for (mode, name) in [(Transaction.Retention.metadataOnly, "metadata"), (.entireContainer, "full")] {
            let result = try await Transaction.execute(source: f.source, in: f.root, destinationName: "result-" + name,
                retention: mode, produce: { directory in
                    let r = try await Writer.run(tool: tool, source: f.source, stage: directory, retention: mode)
                    let disk = try await CompanionDiskCheck.verify(source: f.source, stage: directory, contents: r.contents)
                    #expect(!disk.originalMetadataSemanticsVerified)
                    #expect(disk.fullContainerMatchesOriginalBytes == (mode == .entireContainer))
                    return disk.contents
                }, verify: { directory, _ in
                    // Development test-only independent semantic oracle, not a native runtime validator.
                    let r = try await ToolRunner().run(executable: URL(fileURLWithPath: "/usr/bin/env"), arguments: [
                        "python3", adapter.path, "verify", f.source.path, directory.path, name, f.executable.path, reader.path], stdoutLimit: 16384)
                    try #require(r.status == 0 && !r.truncated)
                    let w = try JSONDecoder().decode(Wire.self, from: r.stdout)
                    return .init(contents: try w.contents(), originalComponentsMatchSource: try #require(w.original_components_match_source as Bool?),
                        sourceIdentityChecked: try #require(w.source_identity_checked_at_boundaries as Bool?),
                        decodedFrameAssociation: try #require(w.decoded_frame_association),
                        immutableSnapshot: try #require(w.immutable_snapshot as Bool?), stableImporter: try #require(w.stable_importer as Bool?))
                })
            #expect(result.memberCount == mode.limits.count)
            #expect(try Data(contentsOf: f.source) == original)
            if mode == .entireContainer { #expect(try Data(contentsOf: result.directory.appendingPathComponent("original-container.mkv")) == original) }
        }
    }
    @Test(arguments: ["source-hash", "member-hash", "source-id", "stage-id", "count", "members", "retention"])
    func forgedReceiptsRefused(change: String) async throws {
        let (f, c) = try await staged(); defer { f.cleanup() }
        var members = c.members
        if change == "member-hash" { let m = members[0]; members[0] = .init(name: m.name, byteCount: m.byteCount, sha256: String(repeating: "0", count: 64)) }
        if change == "members" { members.removeLast() }
        let forged = Transaction.Contents(retention: change == "retention" ? .entireContainer : c.retention,
            sourceID: change == "source-id" ? .init(device: 0, inode: 0) : c.sourceID,
            stageID: change == "stage-id" ? .init(device: 0, inode: 0) : c.stageID,
            sourceBytes: c.sourceBytes, sourceSHA256: change == "source-hash" ? String(repeating: "0", count: 64) : c.sourceSHA256,
            packets: change == "count" ? 0 : c.packets, records: c.records, enhancementNALs: c.enhancementNALs, members: members)
        await #expect(throws: (any Error).self) { try await CompanionDiskCheck.verify(source: f.source, stage: f.stage, contents: forged) }
        #expect(FileManager.default.fileExists(atPath: f.stage.appendingPathComponent("manifest.json").path))
    }
    @Test(arguments: ["extra", "missing", "symlink", "hardlink", "permissions", "bytes"])
    func unsafeOrChangedDiskRefused(change: String) async throws {
        let (f, c) = try await staged(); defer { f.cleanup() }
        let component = f.stage.appendingPathComponent(c.members[0].name)
        switch change {
        case "extra": try Data([1]).write(to: f.stage.appendingPathComponent("extra"))
        case "missing": try FileManager.default.removeItem(at: component)
        case "symlink": try FileManager.default.removeItem(at: component); try FileManager.default.createSymbolicLink(at: component, withDestinationURL: f.source)
        case "hardlink": try #require(link(component.path, f.root.appendingPathComponent("alias").path) == 0)
        case "permissions": try #require(chmod(component.path, 0o644) == 0)
        default: let h = try FileHandle(forWritingTo: component); try h.write(contentsOf: Data([0xff])); try h.close()
        }
        await #expect(throws: (any Error).self) { try await CompanionDiskCheck.verify(source: f.source, stage: f.stage, contents: c) }
        #expect(FileManager.default.fileExists(atPath: f.stage.path))
    }
    @Test(arguments: ["source", "component", "stage"])
    func finalIdentityAndContentChangesRefused(change: String) async throws {
        let (f, c) = try await staged(); defer { f.cleanup() }
        await CompanionDiskCheck.$testBoundary.withValue(.init(beforeFinal: {
            do {
                if change == "stage" {
                    try FileManager.default.moveItem(at: f.stage, to: f.root.appendingPathComponent("retained-stage"))
                    try FileManager.default.createDirectory(at: f.stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                } else {
                    let target = change == "source" ? f.source : f.stage.appendingPathComponent(c.members[0].name)
                    let h = try FileHandle(forWritingTo: target); try h.write(contentsOf: Data([0xfe])); try h.close()
                }
            } catch { Issue.record("Generated mutation failed") }
        })) {
            await #expect(throws: (any Error).self) { try await CompanionDiskCheck.verify(source: f.source, stage: f.stage, contents: c) }
        }
        #expect(FileManager.default.fileExists(atPath: f.stage.path))
    }
    @Test func completeContainerComparisonRefusesSelfConsistentWrongCopy() async throws {
        let (f, c) = try await staged(.entireContainer); defer { f.cleanup() }
        let copy = f.stage.appendingPathComponent("original-container.mkv")
        let h = try FileHandle(forWritingTo: copy); try h.write(contentsOf: Data([0xff])); try h.close()
        let changedDigest = DolbyInspection.hex(SHA256.hash(data: try Data(contentsOf: copy)))
        let members = c.members.map { m in
            m.name == "original-container.mkv" ? ResultSetStaging.Member(name: m.name, byteCount: m.byteCount,
                sha256: changedDigest) : m
        }
        let forged = Transaction.Contents(retention: c.retention, sourceID: c.sourceID, stageID: c.stageID,
            sourceBytes: c.sourceBytes, sourceSHA256: c.sourceSHA256, packets: c.packets, records: c.records,
            enhancementNALs: c.enhancementNALs, members: members)
        await #expect(throws: (any Error).self) { try await CompanionDiskCheck.verify(source: f.source, stage: f.stage, contents: forged) }
    }
    @Test func multiChunkExactContainerComparisonChecksLaterBytes() async throws {
        let (f, c) = try await staged(.entireContainer); defer { f.cleanup() }
        let copy = f.stage.appendingPathComponent("original-container.mkv")
        let padding = Data(repeating: 0x5a, count: 3 << 20)
        for url in [f.source, copy] {
            let h = try FileHandle(forWritingTo: url); _ = try h.seekToEnd(); try h.write(contentsOf: padding); try h.close()
        }
        // Opaque integrity-only generated data; no Matroska/semantic admission claim.
        func current() throws -> Transaction.Contents {
            let sourceData = try Data(contentsOf: f.source)
            let members = try c.members.map { m in
                let data = try Data(contentsOf: f.stage.appendingPathComponent(m.name))
                return ResultSetStaging.Member(name: m.name, byteCount: Int64(data.count), sha256: DolbyInspection.hex(SHA256.hash(data: data)))
            }
            return .init(retention: c.retention, sourceID: c.sourceID, stageID: c.stageID,
                sourceBytes: Int64(sourceData.count), sourceSHA256: DolbyInspection.hex(SHA256.hash(data: sourceData)),
                packets: c.packets, records: c.records, enhancementNALs: c.enhancementNALs, members: members)
        }
        let passed = try await CompanionDiskCheck.verify(source: f.source, stage: f.stage, contents: current())
        #expect(passed.fullContainerMatchesOriginalBytes && !passed.originalMetadataSemanticsVerified)
        let h = try FileHandle(forWritingTo: copy); try h.seek(toOffset: (2 << 20) + 17)
        try h.write(contentsOf: Data([0x7f])); try h.close()
        let forged = try current() // Hash agrees with altered copy; later original bytes must still disagree.
        await #expect(throws: (any Error).self) { try await CompanionDiskCheck.verify(source: f.source, stage: f.stage, contents: forged) }
    }

    @Test func alreadyCancelledTaskDoesNotAdmitDiskReceipt() async throws {
        let (f, c) = try await staged(); defer { f.cleanup() }
        let gate = Gate()
        let task = Task {
            gate.hold()
            return try await CompanionDiskCheck.verify(source: f.source, stage: f.stage, contents: c)
        }
        for await _ in gate.entered { break }; task.cancel(); gate.release.signal()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.stage.path).count == c.members.count)
    }
    private final class Gate: @unchecked Sendable {
        let entered: AsyncStream<Void>; private let signal: AsyncStream<Void>.Continuation
        let release = DispatchSemaphore(value: 0)
        init() { let p = AsyncStream<Void>.makeStream(); entered = p.stream; signal = p.continuation }
        func hold() { signal.yield(()); signal.finish(); if release.wait(timeout: .now() + 30) != .success { Issue.record("Generated disk gate expired") } }
    }
    @Test(arguments: ["source", "manifest.json", "late"])
    func cancellationWaitsForActualReadWorkerAndRefusesLateResult(point: String) async throws {
        let (f, c) = try await staged(); defer { f.cleanup() }; let gate = Gate()
        let task = Task {
            try await CompanionDiskCheck.$testBoundary.withValue(.init(progress: { name, _ in
                if name == point { gate.hold() }
            }, beforeFinal: { if point == "late" { gate.hold() } })) {
                try await CompanionDiskCheck.verify(source: f.source, stage: f.stage, contents: c)
            }
        }
        for await _ in gate.entered { break }; task.cancel()
        #expect(FileManager.default.fileExists(atPath: f.stage.appendingPathComponent("manifest.json").path))
        gate.release.signal()
        await #expect(throws: CancellationError.self) { try await task.value }
        // Worker has returned, all its descriptor owners have unwound; checker does not remove caller files.
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.stage.path).count == c.members.count)
    }
    private final class AdmissionCloses: @unchecked Sendable {
        private let lock = NSLock(); private var values: [String?] = []
        func add(_ component: String?, _ status: Int32, _ code: Int32) { lock.withLock { #expect(status == 0 && code == 0); values.append(component) } }
        func expect(_ expected: [String?]) { lock.withLock { #expect(values == expected) } }
    }
    @Test func sourceURLAdmissionRollbackChecksRealCloseAndPropagatesCause() async throws {
        for variant in ["empty", "directory", "missing", "alias", "cancel", "reported", "substitution"] {
            let f = try await Self.fixture(), closes = AdmissionCloses()
            let input = f.root.appendingPathComponent("admission-source"), moved = f.root.appendingPathComponent("original-admission-source")
            if variant == "directory" { try FileManager.default.createDirectory(at: input, withIntermediateDirectories: false) }
            else if variant == "alias" { try FileManager.default.createSymbolicLink(at: input, withDestinationURL: f.source) }
            else if variant != "missing" { try (variant == "substitution" ? Data("prior".utf8) : Data()).write(to: input) }
            let boundary = CompanionDiskCheck.Boundary(fileOpened: { _ in
                if variant == "cancel" { throw CancellationError() }
                if variant == "substitution" { try FileManager.default.moveItem(at: input, to: moved); try Data("prior".utf8).write(to: input) }
            }, admissionClosed: { closes.add($0,$1,$2) }, refuseAdmissionClose: { _ in variant == "reported" })
            do {
                _ = try await CompanionDiskCheck.$testBoundary.withValue(boundary) { try await CompanionDiskCheck.spoolOriginalSource(source: input, in: f.stage) }
                Issue.record("Invalid source admission returned receipt")
            } catch let error as CompanionDiskCheck.FileAdmissionFailure {
                #expect(variant == "reported" && error.operationError is NativeExportError && error.component == nil)
                #expect(error.closeStatus == 0 && error.closeErrno == 0 && error.reportedAfterActualClose)
            } catch is CancellationError { #expect(variant == "cancel") }
            catch { #expect(variant != "reported" && variant != "cancel") }
            closes.expect(["missing","alias"].contains(variant) ? [] : [nil])
            let names = try FileManager.default.contentsOfDirectory(atPath: f.stage.path); #expect(names.isEmpty)
            if variant == "substitution" {
                let selectedBytes = try Data(contentsOf: input), originalBytes = try Data(contentsOf: moved)
                #expect(selectedBytes == Data("prior".utf8) && originalBytes == Data("prior".utf8))
            }
            if variant == "reported" { print("GENERATED_RETAINED_SOURCE_ADMISSION \(f.root.path)") }
            else { f.cleanup() }
        }
    }
    @Test func retainedComponentAdmissionRollbackIsCheckedWithoutClaimingLaterCloses() async throws {
        for reported in [false,true] {
            let (f,c) = try await staged()
            let selected = try #require(c.members.map(\.name).sorted().first), url = f.stage.appendingPathComponent(selected)
            let original = try Data(contentsOf: url), closes = AdmissionCloses()
            do {
                _ = try await CompanionDiskCheck.$testBoundary.withValue(.init(fileOpened: { component in
                    if component == selected { #expect(chmod(url.path,0o644) == 0) }
                }, admissionClosed: { closes.add($0,$1,$2) }, refuseAdmissionClose: { _ in reported })) {
                    try await CompanionDiskCheck.verify(source: f.source, stage: f.stage, contents: c)
                }
                Issue.record("Unsafe component admission returned receipt")
            } catch let error as CompanionDiskCheck.FileAdmissionFailure {
                #expect(reported && error.component == selected && error.operationError is NativeExportError && error.reportedAfterActualClose)
            } catch { #expect(!reported) }
            closes.expect([selected]); #expect(try Data(contentsOf: url) == original)
            if reported { print("GENERATED_RETAINED_COMPONENT_ADMISSION \(f.root.path)") }
            else { f.cleanup() }
        }
    }

    private final class EnumerationCloses: @unchecked Sendable {
        private let lock = NSLock(); private var values: [String] = []
        func add(_ pass: CompanionDiskCheck.EnumerationPass, _ role: CompanionDiskCheck.EnumerationRole, _ status: Int32, _ code: Int32) {
            lock.withLock { #expect(status == 0 && code == 0); values.append(pass.rawValue + "/" + role.rawValue) }
        }
        func expect(_ expected: [String]) { lock.withLock { #expect(values == expected) } }
    }
    private final class EnumerationJoins: @unchecked Sendable {
        private let lock = NSLock(); private var launched: [pid_t] = [], joined: [pid_t] = []
        func launch(_ p: pid_t) { lock.withLock { launched.append(p) } }
        func join(_ p: pid_t) { lock.withLock { joined.append(p) } }
        func expectOne() {
            let values = lock.withLock { (launched,joined) }; #expect(values.0.count == 1 && values.0 == values.1)
            for p in values.0 { var status: Int32 = 0; #expect(waitpid(p,&status,WNOHANG) == -1 && errno == ECHILD) }
        }
    }
    @Test func actualMembershipEnumerationChecksTransferredStreamAndUntransferredDuplicateBothModes() async throws {
        for mode in [Transaction.Retention.metadataOnly,.entireContainer] {
            let joins=EnumerationJoins()
            let (f,c)=try await Writer.$testBoundary.withValue(.init(launched:{ joins.launch($0) },settled:{ joins.join($0) })) { try await staged(mode) }
            let original=try Data(contentsOf:f.source); joins.expectOne()
            for variant in ["normal","initial-denied","final-denied","initial-duplicate-cancel","initial-stream-cancel","final-stream-cancel","body-bound"] {
                let closes=EnumerationCloses()
                let extra = variant == "body-bound" ? (0..<17).map { f.stage.appendingPathComponent("generated-extra-"+String($0)) } : []
                for url in extra { try Data([1]).write(to:url) }
                do {
                    let result=try await CompanionDiskCheck.$testBoundary.withValue(.init(
                        enumerationOpened:{ pass,role in
                            if variant == pass.rawValue+"-"+role.rawValue+"-cancel" { throw CancellationError() }
                        },allowEnumerationStream:{ pass in variant != pass.rawValue+"-denied" },
                        enumerationClosed:{ closes.add($0,$1,$2,$3) })) {
                        try await CompanionDiskCheck.verify(source:f.source,stage:f.stage,contents:c)
                    }
                    #expect(variant == "normal" && result.fullContainerMatchesOriginalBytes == (mode == .entireContainer))
                } catch {
                    if error is any CompanionUnsettledOwnership { print("GENERATED_UNCERTAIN_ENUMERATION " + f.root.path); throw error }
                    #expect(variant != "normal")
                    if variant.hasSuffix("cancel") { #expect(error is CancellationError) } else { #expect(error is NativeExportError) }
                }
                let expected: [String]
                switch variant {
                case "initial-denied","initial-duplicate-cancel": expected=["initial/duplicate"]
                case "initial-stream-cancel","body-bound": expected=["initial/stream"]
                case "final-denied": expected=["initial/stream","final/duplicate"]
                default: expected=["initial/stream","final/stream"]
                }
                closes.expect(expected)
                for url in extra { try FileManager.default.removeItem(at:url) }
                #expect(try Data(contentsOf:f.source) == original)
            }
            f.cleanup()
        }
    }
    private final class EnumerationGate: @unchecked Sendable {
        let entered: AsyncStream<Void>, signal: AsyncStream<Void>.Continuation
        let release=DispatchSemaphore(value:0)
        init() { let p=AsyncStream<Void>.makeStream(); entered=p.stream; signal=p.continuation }
        func hold() { signal.yield(()); signal.finish(); if release.wait(timeout:.now()+30) != .success { Issue.record("Generated enumeration gate expired") } }
    }
    @Test func actualEnumerationTaskCancellationWaitsForConsumedDuplicateOrStream() async throws {
        for point in ["initial/duplicate","initial/stream","final/duplicate","final/stream"] {
            let joins=EnumerationJoins()
            let (f,c)=try await Writer.$testBoundary.withValue(.init(launched:{ joins.launch($0) },settled:{ joins.join($0) })) { try await staged() }
            let original=try Data(contentsOf:f.source), closes=EnumerationCloses(), gate=EnumerationGate(); joins.expectOne()
            let task=Task {
                defer { gate.signal.finish() }
                return try await CompanionDiskCheck.$testBoundary.withValue(.init(enumerationOpened:{ pass,role in
                    if point == pass.rawValue+"/"+role.rawValue { gate.hold() }
                },enumerationClosed:{ closes.add($0,$1,$2,$3) })) { try await CompanionDiskCheck.verify(source:f.source,stage:f.stage,contents:c) }
            }
            for await _ in gate.entered { break }; task.cancel(); gate.release.signal()
            do { _=try await task.value; Issue.record("Cancelled enumeration returned receipt") }
            catch { if error is any CompanionUnsettledOwnership { print("GENERATED_UNCERTAIN_ENUMERATION " + f.root.path); throw error }; #expect(error is CancellationError) }
            closes.expect(point.hasPrefix("final") ? ["initial/stream",point] : [point])
            #expect(try Data(contentsOf:f.source) == original)
            let names=try FileManager.default.contentsOfDirectory(atPath:f.stage.path); #expect(Set(names) == Set(c.members.map(\.name)))
            f.cleanup()
        }
    }

    private final class DirectoryAdmissionCloses: @unchecked Sendable {
        private let lock = NSLock(); private var statuses: [Int32] = []
        func add(_ status: Int32, _ code: Int32) { lock.withLock { #expect(status == 0 && code == 0); statuses.append(status) } }
        func expect(_ count: Int) { lock.withLock { #expect(statuses.count == count) } }
    }
    @Test func positiveDirectoryAdmissionRollbackChecksActualGuardCallbackAndSubstitutionRefusals() throws {
        for point in ["mode", "callback", "substitution", "missing", "symlink", "file"] {
            let root=FileManager.default.temporaryDirectory.appendingPathComponent("generated-directory-admission-"+UUID().uuidString)
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
            let selected=root.appendingPathComponent("selected"), moved=root.appendingPathComponent("original-selected")
            try FileManager.default.createDirectory(at:selected,withIntermediateDirectories:false,attributes:[.posixPermissions:point == "mode" ? 0o755 : 0o700])
            var target=selected
            if point == "missing" { target=root.appendingPathComponent("missing") }
            if point == "symlink" { target=root.appendingPathComponent("link"); try FileManager.default.createSymbolicLink(at:target,withDestinationURL:selected) }
            if point == "file" { target=root.appendingPathComponent("file"); try Data([1]).write(to:target) }
            let closes=DirectoryAdmissionCloses()
            do {
                _=try CompanionDiskCheck.Directory.admit(target,boundary:.init(directoryAdmissionOpened:{ directory in
                    var info=stat(); let status=fstat(directory.descriptorForTesting,&info); #expect(status == 0)
                    if point == "callback" { throw NativeExportError.invalid("Generated directory admission refusal") }
                    if point == "substitution" { try FileManager.default.moveItem(at:selected,to:moved); try FileManager.default.createDirectory(at:selected,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]) }
                },directoryAdmissionClosed:{ closes.add($0,$1) }),checkpoint:{})
                Issue.record("Refused directory admission returned")
            } catch { if error is any CompanionUnsettledOwnership { print("GENERATED_UNEXPECTED_DIRECTORY_ADMISSION " + root.path); throw error }; #expect(error is NativeExportError) }
            closes.expect(["missing","symlink","file"].contains(point) ? 0 : 1)
            try FileManager.default.removeItem(at:root)
        }
    }

}
