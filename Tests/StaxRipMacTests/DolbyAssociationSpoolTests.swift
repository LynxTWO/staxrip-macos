import Foundation
import Darwin
import Testing
@testable import StaxRipMac

struct DolbyAssociationSpoolTests {
    typealias Spool = DolbyAssociationSpool
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("generated-association-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]); return root
    }
    private func packet(_ index: Int64, pts: Int64 = 0) -> Spool.Packet {
        .init(index:index,inputOffset:16+index*1024,blockOffset:8+index*1024,ptsNS:pts,durationNS:UInt64.max,
              invisible:index%2 == 0,keyframe:nil,discardable:false,encodedBytes:1000,sha256:String(repeating:"a",count:64))
    }
    private func rpu(_ index: Int64, packet: Spool.Packet, nal: Int64 = 1) -> Spool.RPU {
        .init(index:index,packetIndex:packet.index,nalIndex:nal,ptsNS:packet.ptsNS,inputOffset:packet.inputOffset+20,
              archiveDelimiterOffset:index*104,payloadBytes:100,sha256:String(repeating:"b",count:64))
    }
    @Test func signedDuplicatesAndMultipleRPUsRoundTripWithoutDeduplication() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at:root) }
        let times: [Int64] = [.min,0,0,-1,.max]
        var escaped: Spool?
        try Spool.withSpool(in:root,sourceBytes:100_000) { store in
            escaped=store
            for (index,pts) in times.enumerated() {
                let p=packet(Int64(index),pts:pts); try store.append(.packet(p))
                try store.append(.rpu(rpu(Int64(index*2),packet:p)))
                try store.append(.rpu(rpu(Int64(index*2+1),packet:p,nal:3)))
            }
            #expect(try store.finishSourcePass(expected:.init(packets:5,rpus:10)) == .init(packets:5,rpus:10))
            for (index,pts) in times.enumerated() {
                let p=packet(Int64(index),pts:pts)
                #expect(try store.packet(p.index) == p)
                #expect(try store.rpu(Int64(index*2)) == rpu(Int64(index*2),packet:p))
                #expect(try store.rpu(Int64(index*2+1)) == rpu(Int64(index*2+1),packet:p,nal:3))
            }
            #expect(!store.hasPendingStatements)
        }
        #expect(escaped?.ownedPinsClosed == true)
        #expect(throws: (any Error).self) { _ = try escaped?.packet(0) }
        #expect(try FileManager.default.contentsOfDirectory(atPath:root.path) == [Spool.name])
    }
    @Test func actualSQLitePageFullPoisonsPassAndClosesPins() throws {
        let root=try directory(); defer { try? FileManager.default.removeItem(at:root) }
        var escaped: Spool?, refused=false, poisonedRefusal=false, written: Int64=0
        #expect(throws:(any Error).self) { try Spool.withSpool(in:root,sourceBytes:20_000_000,limits:.init(pages:8,records:10_000)) { store in
            escaped=store
            do { for index in Int64(0)..<10_000 { try store.append(.packet(packet(index))); written += 1 } }
            catch Spool.Failure.storageFull { refused=true }
            #expect(refused)
            do { _ = try store.finishSourcePass(expected:.init(packets:10_000,rpus:0)) }
            catch { poisonedRefusal=true }
        } }
        // withSpool refuses even if the caller catches a poisoned pass.
        #expect(escaped?.ownedPinsClosed == true)
        #expect(poisonedRefusal)
        #expect(written > 0 && written < 10_000)
        let size = try #require(try FileManager.default.attributesOfItem(atPath:root.appendingPathComponent(Spool.name).path)[.size] as? NSNumber).int64Value
        #expect(size <= 8*4096)
        print("GENERATED_SPOOL_PAGE_FULL rows=\(written) file_bytes=\(size) closed=\(escaped?.ownedPinsClosed == true)")
    }
    @Test func cancellationDuringAppendOrAfterSealCannotYieldSuccess() throws {
        for late in [false,true] {
            let root=try directory(); defer { try? FileManager.default.removeItem(at:root) }
            var cancelled=false, escaped: Spool?
            #expect(throws:CancellationError.self) {
                try Spool.withSpool(in:root,sourceBytes:100_000,checkpoint:{ if cancelled { throw CancellationError() } }) { store in
                    escaped=store
                    try store.append(.packet(packet(0)))
                    if late { _ = try store.finishSourcePass(expected:.init(packets:1,rpus:0)) }
                    cancelled=true
                    if !late { try store.append(.packet(packet(1))) }
                }
            }
            #expect(escaped?.ownedPinsClosed == true)
        }
    }
    @Test func wrongCountsSequenceAndMissingRowsRefuse() throws {
        for variant in 0..<6 {
            let root=try directory(); defer { try? FileManager.default.removeItem(at:root) }
            #expect(throws:(any Error).self) {
                try Spool.withSpool(in:root,sourceBytes:100_000,limits:.init(records:1)) { store in
                    let p=packet(0); try store.append(.packet(p))
                    switch variant {
                    case 0: _ = try store.finishSourcePass(expected:.init(packets:2,rpus:0))
                    case 1: try store.append(.packet(p))
                    case 2: try store.append(.packet(packet(1)))
                    case 3: try store.append(.rpu(rpu(1,packet:p)))
                    case 4: _ = try store.packet(0)
                    default:
                        _ = try store.finishSourcePass(expected:.init(packets:1,rpus:0)); _ = try store.rpu(0)
                    }
                }
            }
        }
    }
    @Test func fixedExclusiveFileAndUnsafeFoldersRefuse() throws {
        for variant in 0..<4 {
            let root=try directory(); defer { try? FileManager.default.removeItem(at:root) }
            let file=root.appendingPathComponent(Spool.name)
            switch variant {
            case 0: try Data("prior".utf8).write(to:file)
            case 1: try FileManager.default.createSymbolicLink(atPath:file.path,withDestinationPath:"absent")
            case 2: try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:root.path)
            default: try Data("prior".utf8).write(to:root.appendingPathComponent("other"))
            }
            #expect(throws:(any Error).self) { try Spool.withSpool(in:root,sourceBytes:100_000) { _ in Issue.record("unsafe stage admitted") } }
            if variant == 0 { #expect(try Data(contentsOf:file) == Data("prior".utf8)) }
        }
    }
    @Test func finalPathReplacementAndExtraMembershipRefuseWithoutDeletingFiles() throws {
        for extra in [false,true] {
            let root=try directory(); defer { try? FileManager.default.removeItem(at:root) }
            var escaped: Spool?
            #expect(throws:(any Error).self) {
                try Spool.withSpool(in:root,sourceBytes:100_000) { store in
                    escaped=store; try store.append(.packet(packet(0)))
                    _ = try store.finishSourcePass(expected:.init(packets:1,rpus:0))
                    if !extra { try FileManager.default.moveItem(at:root.appendingPathComponent(Spool.name),to:root.appendingPathComponent("retained.sqlite")) }
                    try Data("prior".utf8).write(to:root.appendingPathComponent(extra ? "extra" : Spool.name))
                }
            }
            #expect(escaped?.ownedPinsClosed == true)
            #expect(try Data(contentsOf:root.appendingPathComponent(extra ? "extra" : Spool.name)) == Data("prior".utf8))
        }
    }
}
