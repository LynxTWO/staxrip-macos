import Foundation
import CryptoKit
import Testing
@testable import StaxRipMac

@Suite(.serialized)
struct CompanionOriginalSPSCheckTests {
    typealias SPS = CompanionOriginalSPSCheck
    private struct Writer {
        var bits: [UInt8] = []
        mutating func put(_ value: Int, _ count: Int) {
            for shift in (0..<count).reversed() { bits.append(UInt8(value >> shift & 1)) }
        }
        mutating func ue(_ value: Int) {
            let n = value+1, width = Int.bitWidth-n.leadingZeroBitCount
            put(0,width-1); put(n,width)
        }
        func bytes() -> Data {
            var b = bits; b.append(1); while !b.count.isMultiple(of: 8) { b.append(0) }
            return Data(stride(from: 0, to: b.count, by: 8).map { i in b[i..<i+8].reduce(0) { $0 << 1 | $1 } })
        }
    }
    private func nal(width: Int = 176, height: Int = 112, crop: [Int]? = [0,7,0,7],
                     sub: Int = 0, id: Int = 0, chroma: Int = 1, depth: Int = 2,
                     reserved: Int = 0) -> Data {
        var w = Writer(); w.put(0,4); w.put(sub,3); w.put(1,1)
        w.put(2,8); w.put(0,32); w.put(0,16); w.put(0,32); w.put(120,8)
        for _ in 0..<sub { w.put(1,1); w.put(1,1) }
        if sub > 0 { for _ in sub..<8 { w.put(reserved,2) } }
        for _ in 0..<sub { w.put(0,16); w.put(0,32); w.put(0,32); w.put(0,8); w.put(120,8) }
        w.ue(id); w.ue(chroma); if chroma == 3 { w.put(0,1) }
        w.ue(width); w.ue(height); w.put(crop == nil ? 0 : 1,1)
        if let crop { for n in crop { w.ue(n) } }; w.ue(depth); w.ue(depth)
        var escaped = Data([0x42,1]), zeros = 0
        for b in w.bytes() {
            if zeros == 2 && b <= 3 { escaped.append(3); zeros = 0 }
            escaped.append(b); zeros = b == 0 ? zeros+1 : 0
        }
        return escaped
    }
    private func configuration(_ units: [Data], width: Int = 4) -> Data {
        var d = Data(repeating: 0, count: 23); d[0]=1; d[21]=UInt8(width-1); d[22]=1
        d.append(contentsOf: [0xa1,UInt8(units.count >> 8),UInt8(units.count & 255)])
        for n in units { d.append(contentsOf: [UInt8(n.count >> 8),UInt8(n.count & 255)]);d.append(n) };return d
    }
    @Test func finitePrefixGeometryChromaUnitsAndOpaqueSublayerRegions() throws {
        for sub in 0...6 {
            for width in 1...4 {
                let cfg = configuration([nal(sub:sub,id:15)],width:width), r = try SPS.readConfiguration(cfg)
                #expect(r.codedWidth == 176 && r.codedHeight == 112 && r.conformanceCrop == [0,14,0,14])
                #expect(r.visibleWidth == 162 && r.visibleHeight == 98 && r.spsID == 15 && r.maxSubLayersMinus1 == sub && r.profileIDC == 2)
                #expect(r.configurationSHA256 == DolbyInspection.hex(SHA256.hash(data:cfg)))
                #expect(!r.completeSPSConformanceVerified && !r.activePictureParameterSetSelectionVerified && !r.independentSourceROIProvenanceVerified && !r.independentSampleValuesVerified && !r.editedPictureSemanticsVerified)
            }
        }
        let zero = try SPS.readConfiguration(configuration([nal(width:160,height:96,crop:nil)]))
        #expect(zero.conformanceCrop == [0,0,0,0] && zero.visibleWidth == 160)
        // Arbitrary unparsed suffix can change while this finite prefix still passes.
        let changed = nal()+Data([0xff]); let r = try SPS.readConfiguration(configuration([changed]))
        #expect(r.codedWidth == 176 && !r.completeSPSConformanceVerified)
    }
    @Test func missingDuplicateLayerTemporalEscapeAndTruncationRefuse() throws {
        let good = nal()
        var forbidden = good; forbidden[0] |= 0x80
        var layer = good; layer[1]=9
        var temporal = good; temporal[1]=2
        let invalids = [configuration([]), configuration([good,good]),configuration([forbidden]),configuration([layer]),configuration([temporal]),
            configuration([good+Data([0,0,0,0x80])]),configuration([good+Data([0,0,1])]),configuration([good+Data([0,0,2])]),
            configuration([good+Data([0,0,3,4])]),configuration([good+Data([0,0,3])]),configuration([good+Data([0])])]
        for cfg in invalids { #expect(throws:(any Error).self) { try SPS.readConfiguration(cfg) } }
        for count in 0..<16 { #expect(throws:(any Error).self) { try SPS.readConfiguration(configuration([Data(good.prefix(count))])) } }
        for cfg in [configuration([nal(sub:7)]),configuration([nal(id:16)]),configuration([nal(id:65535)]),configuration([nal(sub:1,reserved:1)])] {
            #expect(throws:(any Error).self) { try SPS.readConfiguration(cfg) }
        }
        #expect(throws:CancellationError.self) { try SPS.readConfiguration(configuration([good]),checkpoint:{throw CancellationError()}) }
    }
    @Test func boundedDimensionsWindowDepthChromaAndGolombRefuse() throws {
        for n in [nal(width:0),nal(width:1),nal(width:175),nal(width:16386),nal(height:0),nal(crop:[88,0,0,0]),nal(crop:[40,48,0,0]),nal(crop:[0,0,56,0]),nal(crop:[8193,0,0,0]),nal(chroma:0),nal(chroma:2),nal(chroma:3),nal(depth:0),nal(depth:9)] {
            #expect(throws:(any Error).self) { try SPS.readConfiguration(configuration([n])) }
        }
        // Escaped zero bytes in the opaque suffix do not validate that suffix.
        var n = nal(); n.append(contentsOf:[0,0,3,0,0,3,0,0x80])
        let prefix = try SPS.readConfiguration(configuration([n])); #expect(!prefix.completeSPSConformanceVerified)
        #expect(throws:(any Error).self) { try SPS.readConfiguration(Data(repeating:0,count:(1<<20)+1)) }
    }
    private func element(_ id: UInt64, _ payload: Data) -> Data {
        var value=id, ids:[UInt8]=[];repeat{ids.insert(UInt8(value&255),at:0);value >>= 8}while value != 0
        var width=1;while UInt64(payload.count)>=(UInt64(1)<<(7*width))-1{width+=1}
        let size=UInt64(payload.count)|UInt64(1)<<(7*width)
        return Data(ids+(0..<width).reversed().map{UInt8(size>>(8*$0)&255)})+payload
    }
    private func source(_ cfg: Data, inBand: UInt8? = nil, repeats: Int = 1) -> Data {
        let track=element(0xae,element(0xd7,Data([1]))+element(0x83,Data([1]))+element(0x86,Data("V_MPEGH/ISO/HEVC".utf8))+element(0x63a2,cfg))
        var packet=Data([0,0,0,3,0x7c,1,0xaa])
        if let inBand {packet.append(contentsOf:[0,0,0,3,inBand<<1,1,0x80])}
        let cluster=element(0x1f43b675,element(0xe7,Data([0]))+(0..<repeats).reduce(Data()){d,_ in d+element(0xa3,Data([0x81,0,0,0x80])+packet)})
        return element(0x1a45dfa3,element(0x4282,Data("matroska".utf8)))+element(0x18538067,element(0x1549a966,element(0x2ad7b1,Data([1])))+element(0x1654ae6b,track)+cluster)
    }
    private func view(_ d: Data) -> CompanionDiskCheck.ReadView {
        .init(sourceBytes:Int64(d.count),source:{o,n in d.subdata(in:Int(o)..<Int(o)+n)},component:{_ in throw CancellationError()},checkpoint:{})
    }
    @Test func freshSelectionBindsAllTrackFactsAndRefusesStaleConfiguration() throws {
        let d=source(configuration([nal()])), v=view(d), t=try CompanionOriginalTrackCheck.readSource(v)
        #expect(try SPS.readSource(v,track:t).visibleWidth == 162)
        for field in 0..<7 {
            let bad=CompanionOriginalTrackCheck.Receipt(trackNumber:t.trackNumber+(field == 0 ? 1:0),originalPayloadOffset:t.originalPayloadOffset+(field == 1 ? 1:0),payloadBytes:t.payloadBytes+(field == 2 ? 1:0),configurationBytes:t.configurationBytes+(field == 3 ? 1:0),nalLengthBytes:field == 4 ? 1:t.nalLengthBytes,payloadSHA256:field == 5 ? String(repeating:"a",count:64):t.payloadSHA256,configurationSHA256:field == 6 ? String(repeating:"b",count:64):t.configurationSHA256,originalTrackAndConfigurationMatch:true)
            #expect(throws:(any Error).self) {try SPS.readSource(v,track:bad)}
        }
        let changed=source(configuration([nal(width:192)])), changedView=view(changed)
        #expect(throws:(any Error).self) {try SPS.readSource(changedView,track:t)}
        let actual=try CompanionOriginalTrackCheck.readSource(changedView), read=try SPS.readSource(changedView,track:actual)
        #expect(read.codedWidth == 192 && !read.activePictureParameterSetSelectionVerified)
    }
    @Test func sourceWorkerRefusesInBandParameterSetsWithoutWideningOldSourceAPI() async throws {
        for kind in [UInt8(32),33,34] {
            let d=source(configuration([nal()]),inBand:kind), root=FileManager.default.temporaryDirectory.appendingPathComponent("source-sps-prefix-"+UUID().uuidString)
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);defer{try? FileManager.default.removeItem(at:root)}
            let input=root.appendingPathComponent("source.mkv"), old=root.appendingPathComponent("old"), new=root.appendingPathComponent("new")
            try d.write(to:input);for u in [old,new]{try FileManager.default.createDirectory(at:u,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])}
            _ = try await CompanionDiskCheck.spoolOriginalSource(source:input,in:old)
            await #expect(throws:(any Error).self){try await CompanionDiskCheck.spoolOriginalSourceSPSGeometryPrefix(source:input,in:new)}
            #expect(try Data(contentsOf:input) == d)
        }
    }
    @Test func sourceWorkerRecordSQLiteBoundsAndReadFinalCancellationSettle() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("source-sps-bounds-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        defer{print("GENERATED_SPS_SOURCE_BOUNDS "+root.path)}
        let input=root.appendingPathComponent("source.mkv"),bytes=source(configuration([nal()]),repeats:2000)
        try bytes.write(to:input)
        for kind in ["records","pages","read-cancel","final-cancel"] {
            let folder=root.appendingPathComponent(kind);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
            let gate=DolbySampleProcessTests.Gate(),cancel=kind.hasSuffix("cancel")
            let limits=DolbyAssociationSpool.Limits(pages:kind == "pages" ? 8:131_072,records:kind == "records" ? 1:2_000_000)
            let task=Task {defer{gate.signal.finish()};return try await CompanionDiskCheck.$testBoundary.withValue(.init(beforeFinal:{if kind == "final-cancel"{gate.hold()}},originalTrackRead:{_,_ in if kind == "read-cancel"{gate.hold()}})){
                try await CompanionDiskCheck.spoolOriginalSourceSPSGeometryPrefix(source:input,in:folder,limits:limits)
            }}
            if cancel{for await _ in gate.stream{break};task.cancel();gate.release.signal()}
            do{_ = try await task.value;Issue.record("Bounded SPS source refusal admitted")}catch is CancellationError{#expect(cancel)}catch{#expect(!cancel)}
            if kind == "pages"{let n=(try FileManager.default.attributesOfItem(atPath:folder.appendingPathComponent(DolbyAssociationSpool.name).path)[.size] as? NSNumber)?.intValue;#expect(n == 8*4096)}
            #expect(try Data(contentsOf:input) == bytes)
        }
    }
    @Test func actualGeneratedHEVCConfigurationsSourceSpoolCountsAndFinalRefusals() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("source-sps-native-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        var retain=true;defer{if retain{print("GENERATED_SPS_SOURCE_REVIEW "+root.path)}else{try? FileManager.default.removeItem(at:root)}}
        _ = try await RustFixtureBuild.generate(.reference,at:root,copiesIn:root)
        for name in ["single","group","wide-vint","conformance","whole-gop"] {
            let input=root.appendingPathComponent(name+".mkv"), bytes=try Data(contentsOf:input), folder=root.appendingPathComponent("spool-"+name)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
            let r=try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched:{_ in Issue.record("SPS prefix source-only path launched decoder")})){
                try await CompanionDiskCheck.spoolOriginalSourceSPSGeometryPrefix(source:input,in:folder)
            }
            #expect(r.originalConfigurationSPSPrefixBoundToSource && r.selectedPacketParameterSetNALsAbsent && !r.activePictureParameterSetSelectionVerified && !r.independentSourceFrameAssociationVerified && !r.independentSourceROIProvenanceVerified && !r.independentSampleValuesVerified && !r.editedPictureSemanticsVerified)
            #expect(r.geometry.codedWidth == (name == "conformance" ? 176:160) && r.geometry.codedHeight == (name == "conformance" ? 112:96))
            #expect(r.geometry.conformanceCrop == (name == "conformance" ? [0,14,0,14]:[0,0,0,0]))
            #expect(r.source.packets.packets == (name == "whole-gop" ? 24:4) && r.source.packets.records == r.source.packets.packets)
            #expect(r.geometry.configurationSHA256 == r.source.track.configurationSHA256 && r.source.sourceSHA256 == DolbyInspection.hex(SHA256.hash(data:bytes)))
            #expect(try Data(contentsOf:input) == bytes)
        }
        for extra in [false,true] {
            let input=root.appendingPathComponent("final-"+UUID().uuidString), bytes=try Data(contentsOf:root.appendingPathComponent("single.mkv")), folder=root.appendingPathComponent("final-spool-"+UUID().uuidString)
            try bytes.write(to:input);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
            await CompanionDiskCheck.$testBoundary.withValue(.init(beforeFinal:{
                do {if extra {try Data([42]).write(to:folder.appendingPathComponent("extra"))}else{try FileManager.default.moveItem(at:input,to:input.appendingPathExtension("original"));try bytes.write(to:input)}}catch{Issue.record("Generated SPS final substitution failed")}
            })) {await #expect(throws:(any Error).self){try await CompanionDiskCheck.spoolOriginalSourceSPSGeometryPrefix(source:input,in:folder)}}
            retain=true;#expect(try Data(contentsOf:input) == bytes)
        }
    }
}
