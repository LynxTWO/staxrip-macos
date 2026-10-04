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
    @Test func exactRationalClockReducesBeforeMultiplyAndRefusesRoundingOverflow() throws {
        #expect(try Spool.nanoseconds(.max,timeBase:[1,1_000_000_000]) == .max)
        #expect(try Spool.nanoseconds(.min,timeBase:[1,1_000_000_000]) == .min)
        #expect(try Spool.nanoseconds(4_000_000_000_000,timeBase:[1,1_000_000]) == 4_000_000_000_000_000)
        #expect(try Spool.nanoseconds(-40,timeBase:[1,1000]) == -40_000_000)
        #expect(try Spool.nanoseconds(0,timeBase:[Int(Int32.max),3]) == 0)
        for (ticks,base) in [(Int64(1),[1,3]),(.max,[1,1]),(.min,[Int(Int32.max),1]),(1,[0,1]),(1,[1,0]),(1,[1]),(1,[Int(Int32.max)+1,1])] {
            #expect(throws:Spool.Failure.refused) { try Spool.nanoseconds(ticks,timeBase:base) }
        }
    }
    private func visible(_ index: Int64) -> Spool.Packet {
        let p=packet(index,pts:index == 0 ? 40_000_000 : 0)
        return .init(index:p.index,inputOffset:p.inputOffset,blockOffset:p.blockOffset,ptsNS:p.ptsNS,durationNS:p.durationNS,
                     invisible:false,keyframe:nil,discardable:false,encodedBytes:p.encodedBytes,sha256:p.sha256)
    }
    private func decoderTrack() -> CompanionOriginalTrackCheck.Receipt {
        .init(trackNumber:1,originalPayloadOffset:8,payloadBytes:40,configurationBytes:23,nalLengthBytes:4,
              payloadSHA256:String(repeating:"d",count:64),configurationSHA256:String(repeating:"c",count:64),originalTrackAndConfigurationMatch:false)
    }
    private func decoderRows() -> [[String:Any]] {
        let begin:[String:Any] = ["kind":"begin","version":1,"input_bytes":100000,"time_base":[1,1000],"configuration_bytes":23,"configuration_sha256":decoderTrack().configurationSHA256,"decoder":"hevc","codec_version":1,"format_version":1,"util_version":1,"automatic_codec_crop":false,"threads":4]
        func packetRow(_ i: Int64) -> [String:Any] {
            let p=visible(i);return ["kind":"packet","index":i,"pts":p.ptsNS/1_000_000,"block_input_byte_offset":p.blockOffset,"encoded_bytes":p.encodedBytes,"sha256":p.sha256]
        }
        func frame(_ f: Int64,_ i: Int64) -> [String:Any] {
            let p=visible(i),raw=rpu(i,packet:p)
            return ["kind":"frame","index":f,"packet_index":i,"block_input_byte_offset":p.blockOffset,"packet_size":p.encodedBytes,"packet_pts":p.ptsNS/1_000_000,"pts":p.ptsNS/1_000_000,"best_effort_pts":p.ptsNS/1_000_000,"width":160,"height":96,"pixel_format":"yuv420p10le","interlaced":false,"codec_crop_left_right_top_bottom":[0,0,0,0],"sample_aspect_ratio":[1,1],"rpu_bytes":raw.payloadBytes,"rpu_sha256":raw.sha256]
        }
        return [begin,packetRow(0),packetRow(1),frame(0,1),frame(1,0),["kind":"complete","version":1,"packets":2,"frames":2,"decoder_drained":true,"descriptor_unchanged":true]]
    }
    private func wire(_ rows: [[String:Any]]) throws -> Data {
        try rows.reduce(into:Data()) { d,r in d.append(try JSONSerialization.data(withJSONObject:r,options:[.sortedKeys]));d.append(10) }
    }
    private func sourceRows(_ store: Spool) throws {
        for i in Int64(0)...1 { let p=visible(i);try store.append(.packet(p));try store.append(.rpu(rpu(i,packet:p))) }
        _=try store.finishSourcePass(expected:.init(packets:2,rpus:2))
    }
    @Test func checkedCoverageBindsReorderedFramesToEncodedSourceWithoutChangingSourceRows() throws {
        let root=try directory();defer{try? FileManager.default.removeItem(at:root)}
        var escaped:Spool?
        try Spool.withSpool(in:root,sourceBytes:100_000) { store in
            escaped=store;try sourceRows(store);try store.startDecoderPass()
            let parser=try DolbyDecoderStream(source:.init(sha256:String(repeating:"a",count:64),byteCount:100000),threads:4,versions:[1,1,1],observe:{ try store.acceptDecoderRow($0,track:decoderTrack()) })
            try parser.accept(wire(decoderRows()));let actual=try parser.finish(status:0)
            try store.finishDecoderPass(actual)
            #expect(!actual.independentSourceFrameAssociationVerified)
            for i in Int64(0)...1 { #expect(try store.packet(i) == visible(i));#expect(try store.rpu(i) == rpu(i,packet:visible(i))) }
        }
        #expect(escaped?.ownedPinsClosed == true)
    }
    @Test func plausibleShapeValidForgeriesFailSourceBindingAndPoisonCoverage() throws {
        let faults:[(Int,String,Any)] = [(0,"configuration_bytes",24),(0,"configuration_sha256",String(repeating:"e",count:64)),
            (0,"time_base",[1,2000]),(1,"pts",41),(1,"block_input_byte_offset",9),(1,"encoded_bytes",999),(1,"sha256",String(repeating:"e",count:64)),
            (3,"packet_index",0),(3,"block_input_byte_offset",1033),(3,"packet_size",999),(3,"rpu_bytes",99),(3,"rpu_sha256",String(repeating:"e",count:64))]
        for (index,key,value) in faults {
            let root=try directory();defer{try? FileManager.default.removeItem(at:root)}
            var rows=decoderRows();rows[index][key]=value
            // D124's partial schema parser accepts these plausible claims alone.
            let partial=try DolbyDecoderStream(source:.init(sha256:String(repeating:"a",count:64),byteCount:100000),threads:4,versions:[1,1,1])
            try partial.accept(wire(rows));_=try partial.finish(status:0)
            #expect(throws:(any Error).self) { try Spool.withSpool(in:root,sourceBytes:100_000) { store in
                try sourceRows(store);try store.startDecoderPass()
                let checked=try DolbyDecoderStream(source:.init(sha256:String(repeating:"a",count:64),byteCount:100000),threads:4,versions:[1,1,1],observe:{try store.acceptDecoderRow($0,track:decoderTrack())})
                try checked.accept(wire(rows));try store.finishDecoderPass(checked.finish(status:0))
            } }
        }
    }
    @Test func missingCoverageAmbiguousRPUsAndInvisibleSourceCannotBeSettled() throws {
        for profile in [DolbyDecoderStream.Profile.metadata,.baseSamples] {
        for variant in 0..<4 {
            let root=try directory();defer{try? FileManager.default.removeItem(at:root)}
            #expect(throws:(any Error).self) { try Spool.withSpool(in:root,sourceBytes:100_000) { store in
                for i in Int64(0)...1 {
                    let p=variant == 3 && i == 0 ? packet(i,pts:40_000_000) : visible(i)
                    try store.append(.packet(p))
                    if variant == 1 {
                        if i == 1 { try store.append(.rpu(rpu(0,packet:p)));try store.append(.rpu(rpu(1,packet:p,nal:3))) }
                    } else {
                        try store.append(.rpu(rpu(i,packet:p)))
                        if variant == 2 && i == 1 {try store.append(.rpu(rpu(2,packet:p,nal:3)))}
                    }
                }
                _=try store.finishSourcePass(expected:.init(packets:2,rpus:variant == 2 ? 3 : 2));try store.startDecoderPass(profile:profile)
                let parser=try DolbyDecoderStream(source:.init(sha256:String(repeating:"a",count:64),byteCount:100000),threads:4,versions:[1,1,1],profile:profile,observeSamples:{if profile == .baseSamples{try store.acceptSampleObservation($0)}},observe:{ row in
                    let o=try CompanionArchiveJSON.object(row,maximum:65535,decoderSampleFields:profile == .baseSamples)
                    let kind=try CompanionArchiveJSON.string(o,"kind")
                    if variant == 0 && (kind == "frame" || kind == "sample-frame") { return }
                    try store.acceptDecoderRow(row,track:decoderTrack())
                })
                try parser.accept(wire(profile == .metadata ? decoderRows():sampleRows()));try store.finishDecoderPass(parser.finish(status:0))
            } }
        }
        }
    }

    private func sampleRows() -> [[String:Any]] {
        var rows=decoderRows()
        rows[0]["kind"]="sample-begin"; rows[5]["kind"]="sample-complete"
        let prototype=DolbySampleProcessTests.rows()[2]
        for i in [3,4] {
            rows[i]["kind"]="sample-frame"
            for key in ["sample_encoding","color_range","color_primaries","color_transfer","color_matrix","chroma_location","container_crop_applied","edited_picture_semantics_verified","coded","codec_visible"] { rows[i][key]=prototype[key] }
        }
        return rows
    }
    private func sampleParser(_ store:Spool, typed:Bool=true) throws -> DolbyDecoderStream {
        try .init(source:.init(sha256:String(repeating:"a",count:64),byteCount:100000),threads:4,versions:[1,1,1],profile:.baseSamples,
            observeSamples:{ if typed {try store.acceptSampleObservation($0)} },
            observe:{try store.acceptDecoderRow($0,track:decoderTrack())})
    }
    @Test func explicitSampleCoveragePreservesReorderedSourceAndDoesNotProveStatisticValues() throws {
        let root=try directory();defer{try? FileManager.default.removeItem(at:root)}
        var escaped:Spool?
        try Spool.withSpool(in:root,sourceBytes:100000) { store in
            escaped=store;try sourceRows(store);try store.startDecoderPass(profile:.baseSamples)
            var rows=sampleRows()
            var coded=try #require(rows[3]["coded"] as? [[String:Any]])
            coded[0]["sha256"]=String(repeating:"e",count:64);rows[3]["coded"]=coded;rows[3]["codec_visible"]=coded
            let parser=try sampleParser(store);try parser.accept(wire(rows))
            let r=try parser.finish(status:0);try store.finishDecoderPass(r)
            #expect(r.sampleFrameSummaryCount == 2 && !r.independentSampleSourceAssociationVerified)
            for i in Int64(0)...1 {#expect(try store.packet(i) == visible(i));#expect(try store.rpu(i) == rpu(i,packet:visible(i)))}
        }
        #expect(escaped?.ownedPinsClosed == true)
    }
    @Test func sampleShapeValidSourceForgeriesRefuseAndCloseOpenStore() throws {
        let faults:[(Int,String,Any)] = [(0,"configuration_bytes",24),(0,"configuration_sha256",String(repeating:"e",count:64)),
            (0,"time_base",[1,2000]),(1,"pts",41),(1,"block_input_byte_offset",9),(1,"encoded_bytes",999),(1,"sha256",String(repeating:"e",count:64)),
            (3,"packet_index",0),(3,"block_input_byte_offset",1033),(3,"packet_size",999),(3,"rpu_bytes",99),(3,"rpu_sha256",String(repeating:"e",count:64))]
        for (index,key,value) in faults {
            let root=try directory();defer{try? FileManager.default.removeItem(at:root)}
            var rows=sampleRows();rows[index][key]=value
            let partial=try DolbyDecoderStream(source:.init(sha256:String(repeating:"a",count:64),byteCount:100000),threads:4,versions:[1,1,1],profile:.baseSamples)
            try partial.accept(wire(rows));_=try partial.finish(status:0)
            var escaped:Spool?
            #expect(throws:(any Error).self){try Spool.withSpool(in:root,sourceBytes:100000){store in
                escaped=store;try sourceRows(store);try store.startDecoderPass(profile:.baseSamples)
                let checked=try sampleParser(store);try checked.accept(wire(rows));try store.finishDecoderPass(checked.finish(status:0))
            }}
            #expect(escaped?.ownedPinsClosed == true)
        }
    }
    @Test func missingTypedSampleDuplicateCallbacksMixedProfilesAndPartialCountsRefuse() throws {
        for variant in 0..<6 {
            let root=try directory();defer{try? FileManager.default.removeItem(at:root)}
            var escaped:Spool?
            #expect(throws:(any Error).self){try Spool.withSpool(in:root,sourceBytes:100000){store in
                escaped=store;try sourceRows(store);try store.startDecoderPass(profile:variant == 2 ? .metadata:.baseSamples)
                let checked=try DolbyDecoderStream(source:.init(sha256:String(repeating:"a",count:64),byteCount:100000),threads:4,versions:[1,1,1],profile:.baseSamples,observeSamples:{f in
                    if variant != 0 {try store.acceptSampleObservation(f)}
                    if variant == 1 {try store.acceptSampleObservation(f)}
                },observe:{row in
                    let o=try CompanionArchiveJSON.object(row,maximum:65535,decoderSampleFields:true)
                    let kind=try CompanionArchiveJSON.string(o,"kind")
                    if variant == 3 && kind == "sample-frame" {return}
                    try store.acceptDecoderRow(row,track:decoderTrack())
                })
                let rows=variant == 4 ? decoderRows():sampleRows()
                try checked.accept(wire(rows));let result=try checked.finish(status:0)
                if variant == 5 {
                    let forged=DolbyDecoderStream.Receipt(source:result.source,packets:result.packets,frames:result.frames,geometry:result.geometry,configurationSHA256:result.configurationSHA256,timeBase:result.timeBase)
                    try store.finishDecoderPass(forged)
                }else{try store.finishDecoderPass(result)}
            }}
            #expect(escaped?.ownedPinsClosed == true)
        }
    }

}
