import Foundation
import CryptoKit
import Darwin
import Testing
@testable import StaxRipMac

/// Opt-in actual storage qualification. The harness creates a new bounded image;
/// ordinary tests never fill a destination or select an existing owner volume.
@Suite(.serialized)
struct CompanionAPFSCapacityTests {
    typealias Writer = CompanionWriterProcess
    typealias Transaction = OriginalCompanionTransaction
    private struct Fixture {
        let root, source, stage, executable, reader: URL
        var tool: Writer.Tool { get throws { try .development(executable, expectedSHA256: DolbyInspection.hex(SHA256.hash(data: Data(contentsOf: executable)))) } }
        var readerTool: CompanionMetadataProcess.Tool { get throws { try .development(reader, expectedSHA256: DolbyInspection.hex(SHA256.hash(data: Data(contentsOf:reader)))) } }
        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }
    private static var repo: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    private static func fixture() async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-companion-capacity-source-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        do {
            let generated = root.appendingPathComponent("generated")
            try FileManager.default.createDirectory(at: generated, withIntermediateDirectories: false)
            let cargo = repo.appendingPathComponent("Tools/DolbyMetadataAudit/Cargo.toml")
            // This serialized suite owns its feature-specific artifacts. Other suites
            // must not replace binaries between a successful Cargo build and copy.
            let buildTarget = repo.appendingPathComponent("Tools/DolbyMetadataAudit/target/native-companion-capacity-fixtures")
            let f = try await ToolRunner().run(executable: URL(fileURLWithPath: "/usr/bin/env"), arguments: [
                "STAXRIP_GENERATED_COMPANION_FIXTURE_DIRECTORY=" + generated.path, "cargo", "test", "--locked",
                "--target-dir",buildTarget.path,"--manifest-path", cargo.path, "original_companions_preserve_raw_bytes_encoded_order_and_distinct_retention"])
            try #require(f.status == 0)
            let b = try await ToolRunner().run(executable: URL(fileURLWithPath: "/usr/bin/env"), arguments: [
                "cargo", "build", "--release", "--locked", "--features", "development-companion-writer", "--bin",
                "staxrip-dolby-companion-writer", "--target-dir",buildTarget.path,"--manifest-path", cargo.path])
            try #require(b.status == 0)
            let executable = root.appendingPathComponent("staxrip-dolby-companion-writer")
            try FileManager.default.copyItem(at: buildTarget.appendingPathComponent("release/staxrip-dolby-companion-writer"), to: executable)
            let rb = try await ToolRunner().run(executable: URL(fileURLWithPath:"/usr/bin/env"), arguments:["cargo","build","--release","--locked","--features","development-companion-writer","--bin","staxrip-dolby-metadata-audit","--target-dir",buildTarget.path,"--manifest-path",cargo.path])
            try #require(rb.status == 0)
            let reader = root.appendingPathComponent("staxrip-dolby-metadata-audit")
            try FileManager.default.copyItem(at: buildTarget.appendingPathComponent("release/staxrip-dolby-metadata-audit"),to:reader)
            let stage = root.appendingPathComponent("stage")
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            return .init(root: root, source: generated.appendingPathComponent("generated-source.mkv"), stage: stage, executable: executable, reader: reader)
        } catch { try? FileManager.default.removeItem(at: root); throw error }
    }
    private final class State: @unchecked Sendable {
        private let lock=NSLock();private var child:pid_t=0,joined:pid_t=0
        func launch(_ p:pid_t) { lock.withLock { child=p } }
        var hasLaunched:Bool { lock.withLock { child > 0 } }
        func settle(_ p:pid_t) { lock.withLock { joined=p } }
        func assertJoined() {
            let p=lock.withLock { (child,joined) };#expect(p.0 > 0 && p.0 == p.1)
            var status:Int32=0;#expect(waitpid(p.0,&status,WNOHANG) == -1 && errno == ECHILD)
        }
    }

    private struct Mounted {
        let url:URL,token:String,id:Transaction.FileID,capacity:Int64
        func check() throws {
            var s=stat();try #require(lstat(url.path,&s)==0 && Transaction.FileID(s)==id)
            try #require(try String(contentsOf:url.appendingPathComponent(".staxrip-companion-apfs-fixture"),encoding:.utf8) == "StaxRip companion APFS fixture v1 " + token + "\n")
        }
        static func read() async throws -> Self {
            let path=try #require(ProcessInfo.processInfo.environment["STAXRIP_COMPANION_APFS_RECEIPT"])
            let receipt=URL(fileURLWithPath:path),raw=try Data(contentsOf:receipt)
            try #require(raw.count<=16384)
            let v=try #require(JSONSerialization.jsonObject(with:raw) as? [String:Any])
            try #require(v["version"] as? Int == 1 && v["state"] as? String == "attached")
            let token=try #require(v["token"] as? String),mount=URL(fileURLWithPath:try #require(v["mount"] as? String)).standardizedFileURL
            try #require(UUID(uuidString:token) != nil)
            var s=stat(),p=stat(),fs=statfs()
            try #require(lstat(mount.path,&s)==0 && lstat(mount.deletingLastPathComponent().path,&p)==0 && s.st_dev != p.st_dev)
            try #require(s.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR))
            try #require(String(s.st_dev)==v["mountDevice"] as? String && String(s.st_ino)==v["mountInode"] as? String)
            try #require(statfs(mount.path,&fs)==0)
            let name=withUnsafePointer(to:&fs.f_fstypename) { $0.withMemoryRebound(to:CChar.self,capacity:Int(MFSTYPENAMELEN)) { String(cString:$0) } }
            try #require(name=="apfs")
            let a=try FileManager.default.attributesOfFileSystem(forPath:mount.path)
            let capacity=try #require((a[.systemSize] as? NSNumber)?.int64Value)
            try #require(capacity>0 && capacity<=64<<20 && ((a[.systemFreeSize] as? NSNumber)?.int64Value ?? 0)>8<<20)
            let disk=try await ToolRunner().run(executable:URL(fileURLWithPath:"/usr/sbin/diskutil"),arguments:["info","-plist",mount.path])
            try #require(disk.status==0 && !disk.truncated)
            let info=try #require(PropertyListSerialization.propertyList(from:disk.stdout,format:nil) as? [String:Any])
            try #require(info["VolumeUUID"] as? String == v["volumeUUID"] as? String && info["DeviceNode"] as? String == v["volumeDevice"] as? String)
            let result=Self(url:mount,token:token,id:.init(s),capacity:capacity);try result.check();return result
        }
    }
    private final class Filler {
        let url:URL
        private var fd:Int32
        let id:Transaction.FileID
        private(set) var bytes=0
        init(_ url:URL) throws {
            self.url=url;fd=Darwin.open(url.path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0o600)
            try #require(fd>=0);var s=stat();try #require(fstat(fd,&s)==0);id = .init(s)
        }
        deinit { close() }
        func close() { if fd>=0 { Darwin.close(fd);fd = -1 } }
        func check() throws {
            var a=stat(),b=stat();try #require(fstat(fd,&a)==0 && lstat(url.path,&b)==0 && Transaction.FileID(a)==id && Transaction.FileID(b)==id)
        }
        func fill() throws {
            try check();let data=[UInt8](repeating:0x5a,count:65536);var exhausted=false
            while bytes+data.count<=64<<20 {
                let n=data.withUnsafeBytes { Darwin.write(fd,$0.baseAddress!,$0.count) }
                if n<0 { exhausted=errno==ENOSPC;break };try #require(n>0);bytes+=n
            }
            let synced=fsync(fd),e=errno
            try #require(exhausted || (synced<0 && e==ENOSPC),"Generated filler must reach actual ENOSPC")
        }

    }
    private func members(_ url:URL) throws -> [String:Data] {
        try Dictionary(uniqueKeysWithValues:FileManager.default.contentsOfDirectory(atPath:url.path).map { ($0,try Data(contentsOf:url.appendingPathComponent($0))) })
    }
    @Test(.enabled(if:ProcessInfo.processInfo.environment["STAXRIP_COMPANION_APFS_RECEIPT"] != nil))
    func actualFullCopyENOSPCSettlesBeforeCleanupAndNativeRetry() async throws {
        let mount=try await Mounted.read(),f=try await Self.fixture()
        let owned=mount.url.appendingPathComponent("owned-"+UUID().uuidString)
        try mount.check();try FileManager.default.createDirectory(at:owned,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        var ownStat=stat();try #require(lstat(owned.path,&ownStat)==0);let ownedID=Transaction.FileID(ownStat)
        var retain=false,processesSettled=true
        defer {
            if !retain {
                if (try? mount.check()) != nil {
                    var s=stat();if lstat(owned.path,&s)==0 && Transaction.FileID(s)==ownedID { try? FileManager.default.removeItem(at:owned) }
                }
                f.cleanup()
            }
            if processesSettled { print("COMPANION_APFS_SETTLED " + mount.token) }
        }
        let h=try FileHandle(forWritingTo:f.source),end=try h.seekToEnd(),padding:UInt64=32<<20
        var encoded=(padding|(1<<56)).bigEndian
        var header=Data([0xec]);withUnsafeBytes(of:&encoded) { header.append(contentsOf:$0) }
        try h.write(contentsOf:header);try h.truncate(atOffset:end+UInt64(header.count)+padding);try h.close()
        let original=try Data(contentsOf:f.source),writer=try f.tool,reader=try f.readerTool
        let verification:Transaction.Verifier={ directory,c in
            let r=try await CompanionDiskCheck.verifyOriginalMetadata(source:f.source,stage:directory,contents:c,tool:reader)
            let m=try #require(r.originalMetadata)
            return .init(contents:r.contents,originalComponentsMatchSource:r.originalMetadataSemanticsVerified && m.originalComponentsMatchSource,
                sourceIdentityChecked:true,decodedFrameAssociation:m.decodedFrameAssociation,immutableSnapshot:m.immutableSnapshot,stableImporter:m.stableImporter)
        }
        do {
            let prior=try await Transaction.execute(source:f.source,in:owned,destinationName:"prior",retention:.metadataOnly,
                produce:{ directory in try await Writer.run(tool:writer,source:f.source,stage:directory,retention:.metadataOnly).contents },verify:verification)
            let priorBytes=try members(prior.directory)
            let reservation=owned.appendingPathComponent("reservation")
            let reserve=try FileHandle(forWritingTo:{ () throws -> URL in
                try #require(FileManager.default.createFile(atPath:reservation.path,contents:nil,attributes:[.posixPermissions:0o600]));return reservation
            }())
            try reserve.write(contentsOf:Data(repeating:0x6a,count:2<<20));try reserve.synchronize();try reserve.close()
            let filler=try Filler(owned.appendingPathComponent("filler"));try mount.check();try filler.fill()
            try FileManager.default.removeItem(at:reservation)
            let child=State();let observed=PartialState()
            do {
                try await Writer.$testBoundary.withValue(.init(launched:{child.launch($0)},settled:{child.settle($0)})) {
                    try await Transaction.execute(source:f.source,in:owned,destinationName:"result",retention:.entireContainer,produce:{ directory in
                        do {
                            let result=try await Writer.run(tool:writer,source:f.source,stage:directory,retention:.entireContainer)
                            Issue.record("Full destination returned producer receipt");return result.contents
                        } catch {
                            if error is any CompanionUnsettledOwnership { throw error }
                            child.assertJoined()
                            let partial=try Data(contentsOf:directory.appendingPathComponent("original-container.mkv"))
                            try #require(partial.count>0 && partial.count<original.count && partial == original.prefix(partial.count),"Actual incomplete original-container copy required")
                            try #require(error is Writer.StorageFullFailure,"Writer must classify its actual component ENOSPC");observed.record(partial.count)
                            throw error
                        }
                    },verify:{ _,_ in Issue.record("Failed producer invoked verifier");throw NativeExportError.invalid("Generated refusal") })
                }
                Issue.record("Full disk transaction returned success")
            } catch is Writer.StorageFullFailure { /* Actual output ENOSPC after settled writer refusal. */ }
            child.assertJoined();try #require(observed.bytes>0)
            #expect(!FileManager.default.fileExists(atPath:owned.appendingPathComponent("result").path))
            #expect(Set(try FileManager.default.contentsOfDirectory(atPath:owned.path)) == ["prior","filler"])
            #expect(try members(prior.directory)==priorBytes && Data(contentsOf:f.source)==original)
            try mount.check();try filler.check();filler.close();try FileManager.default.removeItem(at:filler.url)
            let completed=try await Transaction.execute(source:f.source,in:owned,destinationName:"result",retention:.entireContainer,
                produce:{ directory in try await Writer.run(tool:writer,source:f.source,stage:directory,retention:.entireContainer).contents },verify:verification)
            #expect(try Data(contentsOf:completed.directory.appendingPathComponent("original-container.mkv"))==original)
            #expect(Set(try FileManager.default.contentsOfDirectory(atPath:completed.directory.path))==Set(Transaction.Retention.entireContainer.limits.keys))
            #expect(try members(prior.directory)==priorBytes && Data(contentsOf:f.source)==original)
            await #expect(throws:(any Error).self) {
                try await Transaction.execute(source:f.source,in:owned,destinationName:"result",retention:.entireContainer,produce:{ _ in Issue.record("Existing result launched producer");throw NativeExportError.invalid("Generated refusal") },verify:verification)
            }
            #expect(Set(try FileManager.default.contentsOfDirectory(atPath:owned.path)) == ["prior","result"])
            print("COMPANION_APFS_RESULT " + mount.token + " capacity=" + String(mount.capacity) + " source_bytes=" + String(original.count) + " filler_bytes=" + String(filler.bytes) + " partial_container_bytes=" + String(observed.bytes) + " actual_ENOSPC=true native_retry=true")
        } catch {
            if error is any CompanionUnsettledOwnership { processesSettled=false;retain=true }
            if error is Transaction.CleanupFailure { retain=true }
            throw error
        }
    }
    private final class PartialState:@unchecked Sendable {
        private let lock=NSLock();private var count=0
        var bytes:Int { lock.withLock {count} }
        func record(_ n:Int) { lock.withLock {count=n} }
    }
}
