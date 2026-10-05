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
                     reserved: Int = 0, vpsID: Int = 0, codingTail: ((inout Writer) -> Void)? = nil) -> Data {
        var w = Writer(); w.put(vpsID,4); w.put(sub,3); w.put(1,1)
        w.put(2,8); w.put(0,32); w.put(0,16); w.put(0,32); w.put(120,8)
        for _ in 0..<sub { w.put(1,1); w.put(1,1) }
        if sub > 0 { for _ in sub..<8 { w.put(reserved,2) } }
        for _ in 0..<sub { w.put(0,16); w.put(0,32); w.put(0,32); w.put(0,8); w.put(120,8) }
        w.ue(id); w.ue(chroma); if chroma == 3 { w.put(0,1) }
        w.ue(width); w.ue(height); w.put(crop == nil ? 0 : 1,1)
        if let crop { for n in crop { w.ue(n) } }; w.ue(depth); w.ue(depth)
        codingTail?(&w)
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
    private func escaped(_ payload: Data, type: UInt8) -> Data {
        var result=Data([type<<1,1]),zeros=0
        for b in payload {if zeros == 2 && b<=3{result.append(3);zeros=0};result.append(b);zeros=b == 0 ? zeros+1:0};return result
    }
    private func vps(id: Int = 0, layers: Int = 0, sub: Int = 0, base: Int = 3, reserved: Int = 65535) -> Data {
        var w=Writer();w.put(id,4);w.put(base,2);w.put(layers,6);w.put(sub,3);w.put(1,1);w.put(reserved,16)
        return escaped(w.bytes(),type:32)
    }
    private func pps(id: Int = 0, sps: Int = 0, dependent: Int = 0, output: Int = 0, extra: Int = 0) -> Data {
        var w=Writer();w.ue(id);w.ue(sps);w.put(dependent,1);w.put(output,1);w.put(extra,3)
        return escaped(w.bytes(),type:34)
    }
    private func referenceConfiguration(_ entries: [(UInt8,Bool,[Data])], width: Int = 4) -> Data {
        var d=Data(repeating:0,count:23);d[0]=1;d[21]=UInt8(width-1);d[22]=UInt8(entries.count)
        for (type,complete,units) in entries {
            d.append(contentsOf:[type | (complete ? 128:0),UInt8(units.count>>8),UInt8(units.count&255)])
            for n in units{d.append(contentsOf:[UInt8(n.count>>8),UInt8(n.count&255)]);d.append(n)}
        };return d
    }
    private func references(_ v: Data? = nil, _ s: Data? = nil, _ p: Data? = nil, complete: Bool = true) -> Data {
        referenceConfiguration([(32,complete,[v ?? vps()]),(33,complete,[s ?? nal()]),(34,complete,[p ?? pps()])])
    }
    @Test func configurationReferencePrefixesKeepRawCompletenessAndOpaqueSuffixSeparate() throws {
        for width in 1...4 {for complete in [false,true] {
            let cfg=referenceConfiguration([(32,complete,[vps(id:15,sub:6)]),(33,complete,[nal(sub:6,id:15,vpsID:15)]),(34,complete,[pps(id:63,sps:15,dependent:1,output:1,extra:7)])],width:width)
            let r=try SPS.readConfigurationReferences(cfg)
            #expect(r.vpsID == 15 && r.vpsMaxSubLayersMinus1 == 6 && r.geometry.spsID == 15 && r.ppsID == 63 && r.ppsSPSID == 15)
            #expect(r.dependentSliceSegmentsEnabled && r.outputFlagPresent && r.extraSliceHeaderBits == 7)
            #expect(r.vpsArrayComplete == complete && r.spsArrayComplete == complete && r.ppsArrayComplete == complete)
            #expect(r.configurationReferencePrefixesAgree && !r.completeParameterSetConformanceVerified && !r.activePictureParameterSetSelectionVerified && !r.independentSourceROIProvenanceVerified && !r.independentSampleValuesVerified && !r.editedPictureSemanticsVerified)
        }}
        // Arbitrary unparsed PPS/VPS suffix can pass only this prefix finding.
        let r=try SPS.readConfigurationReferences(references(vps()+Data([255]),nil,pps()+Data([255])))
        #expect(!r.completeParameterSetConformanceVerified && !r.geometry.completeSPSConformanceVerified)
    }
    @Test func configurationMissingAmbiguousMismatchedUnsupportedReferencesRefuse() throws {
        let v=vps(),s=nal(),p=pps()
        let cases=[configuration([s]),referenceConfiguration([(32,true,[v]),(33,true,[s])]),
            referenceConfiguration([(32,true,[v,v]),(33,true,[s]),(34,true,[p])]),
            referenceConfiguration([(32,true,[v]),(33,true,[s]),(34,true,[p,p])]),
            referenceConfiguration([(32,true,[v]),(33,true,[s]),(34,true,[p]),(34,false,[])]),
            references(vps(id:1)),references(nil,nil,pps(sps:1)),references(vps(layers:1)),references(vps(base:2)),references(vps(sub:7)),references(vps(reserved:0)),
            references(nil,nil,pps(id:64)),references(nil,nil,pps(id:65535)),references(nil,nil,pps(sps:16)),
            references(Data([0x40,1])),references(nil,nil,Data([0x44,1])),references(v+Data([0,0,3,4])),references(nil,nil,p+Data([0,0,1]))]
        for cfg in cases {#expect(throws:(any Error).self){try SPS.readConfigurationReferences(cfg)}}
        var reserved=references();reserved[23] |= 64
        var layer=p;layer[1]=9
        var temporal=v;temporal[1]=2
        for cfg in [reserved,references(nil,nil,layer),references(temporal)] {#expect(throws:(any Error).self){try SPS.readConfigurationReferences(cfg)}}
        for n in 2..<6{#expect(throws:(any Error).self){try SPS.readConfigurationReferences(references(Data(v.prefix(n))))}}
        #expect(try SPS.readConfiguration(configuration([s])).codedWidth == 176) // Old SPS-only API unchanged.
        #expect(throws:CancellationError.self){try SPS.readConfigurationReferences(references(),checkpoint:{throw CancellationError()})}
    }
    @Test func sourceReferencePrefixesBindFreshTrackAndPreserveNarrowInBandAdmission() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("source-parameter-prefix-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);defer{print("GENERATED_PARAMETER_PREFIX_REVIEW "+root.path)}
        for kind in [UInt8(0),32,33,34] {
            let bytes=source(references(),inBand:kind == 0 ? nil:kind),input=root.appendingPathComponent(String(kind)+".mkv"),folder=root.appendingPathComponent("spool"+String(kind))
            try bytes.write(to:input);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
            let t=try CompanionOriginalTrackCheck.readSource(view(bytes)),r=try SPS.readSourceReferences(view(bytes),track:t)
            #expect(r.geometry.configurationSHA256 == t.configurationSHA256)
            if kind == 0 {
                let bound=try await CompanionDiskCheck.spoolOriginalSourceParameterReferences(source:input,in:folder)
                #expect(bound.originalParameterReferencePrefixesBoundToSource && bound.selectedPacketParameterSetNALsAbsent && !bound.activePictureParameterSetSelectionVerified && !bound.independentSourceFrameAssociationVerified && !bound.completeParameterSetConformanceVerified)
            }else{await #expect(throws:(any Error).self){try await CompanionDiskCheck.spoolOriginalSourceParameterReferences(source:input,in:folder)}}
            #expect(try Data(contentsOf:input) == bytes)
        }
        let original=source(references()),old=try CompanionOriginalTrackCheck.readSource(view(original)),changed=source(references(nil,nil,pps(id:1)))
        #expect(throws:(any Error).self){try SPS.readSourceReferences(view(changed),track:old)}
        let fresh=try CompanionOriginalTrackCheck.readSource(view(changed)),r=try SPS.readSourceReferences(view(changed),track:fresh)
        #expect(r.ppsID == 1 && !r.activePictureParameterSetSelectionVerified)
    }
    @Test func actualGeneratedSourceParameterReferencesCountsCancellationAndFinalIdentity() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("source-parameter-native-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);defer{print("GENERATED_PARAMETER_NATIVE_REVIEW "+root.path)}
        _ = try await RustFixtureBuild.generate(.reference,at:root,copiesIn:root)
        func folder(_ name:String) throws -> URL {let u=root.appendingPathComponent(name);try FileManager.default.createDirectory(at:u,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);return u}
        for name in ["single","group","wide-vint","conformance","whole-gop"] {
            let input=root.appendingPathComponent(name+".mkv"),bytes=try Data(contentsOf:input),stage=try folder("spool-"+name)
            let r=try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched:{_ in Issue.record("Parameter reference source-only path launched decoder")})){
                try await CompanionDiskCheck.spoolOriginalSourceParameterReferences(source:input,in:stage)
            }
            #expect(r.references.ppsID == 0 && r.references.ppsSPSID == 0 && r.references.vpsID == 0 && r.references.geometry.spsID == 0)
            #expect(r.source.packets.packets == (name == "whole-gop" ? 24:4) && r.source.packets.records == r.source.packets.packets)
            #expect(r.references.geometry.codedWidth == (name == "conformance" ? 176:160) && !r.activePictureParameterSetSelectionVerified && !r.independentSourceROIProvenanceVerified && !r.independentSampleValuesVerified && !r.editedPictureSemanticsVerified)
            #expect(try Data(contentsOf:input) == bytes)
        }
        let input=root.appendingPathComponent("single.mkv"),bytes=try Data(contentsOf:input)
        for kind in ["cap","read-cancel","late-cancel","extra","source-substitute"] {
            let stage=try folder(kind),gate=DolbySampleProcessTests.Gate(),cancel=kind.hasSuffix("cancel")
            let task=Task{defer{gate.signal.finish()};return try await CompanionDiskCheck.$testBoundary.withValue(.init(beforeFinal:{if kind == "late-cancel"{gate.hold()};if kind == "extra"{do{try Data([1]).write(to:stage.appendingPathComponent("extra"))}catch{Issue.record("Generated parameter final injection failed")}};if kind == "source-substitute"{do{try FileManager.default.moveItem(at:input,to:input.appendingPathExtension("original"));try bytes.write(to:input)}catch{Issue.record("Generated parameter source substitution failed")}}},originalTrackRead:{_,_ in if kind == "read-cancel"{gate.hold()}})){
                try await CompanionDiskCheck.spoolOriginalSourceParameterReferences(source:input,in:stage,limits:.init(records:kind == "cap" ? 1:2_000_000))
            }}
            if cancel{for await _ in gate.stream{break};task.cancel();gate.release.signal()}
            do{_ = try await task.value;Issue.record("Parameter source refusal admitted")}catch is CancellationError{#expect(cancel)}catch{#expect(!cancel)}
            #expect(try Data(contentsOf:input) == bytes)
        }
    }
    @Test func sourceReferencePrefixActualEightPageSQLiteFullPreservesSource() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("source-parameter-full-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);defer{print("GENERATED_PARAMETER_FULL_REVIEW "+root.path)}
        let input=root.appendingPathComponent("source.mkv"),stage=root.appendingPathComponent("spool"),bytes=source(references(),repeats:2000)
        try bytes.write(to:input);try FileManager.default.createDirectory(at:stage,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        await #expect(throws:(any Error).self){try await CompanionDiskCheck.spoolOriginalSourceParameterReferences(source:input,in:stage,limits:.init(pages:8))}
        let size=(try FileManager.default.attributesOfItem(atPath:stage.appendingPathComponent(DolbyAssociationSpool.name).path)[.size] as? NSNumber)?.intValue
        #expect(size == 8*4096);#expect(try Data(contentsOf:input) == bytes)
    }
    private func slice(type: UInt8 = 1, pps: Int = 0, first: Int = 1, prior: Int = 0) -> Data {
        var w=Writer();w.put(first,1);if (16...23).contains(type){w.put(prior,1)};w.ue(pps)
        return Data([type<<1,1])+w.bytes()
    }
    private func prefix(_ nal: Data, payloadBytes: Int64? = nil) throws -> SPS.FirstSlicePrefix {
        try SPS.readFirstSlicePrefix(header:Data(nal.prefix(2)),prefix:nal.subdata(in:2..<min(4,nal.count)),payloadBytes:payloadBytes ?? Int64(nal.count-2))
    }
    @Test func firstSlicePrefixesBoundPPSIDsIRAPAbsenceAndTwoByteStorage() throws {
        for type in [UInt8(0),1,6,7,8,9,16,17,18,19,20,21] {for id in 0...63 {
            let r=try prefix(slice(type:type,pps:id,prior:1))
            #expect(r.ppsID == id && r.nalType == type && r.firstSliceSegmentInPicture && r.prefixBits <= 15 && r.encodedPrefixBytes <= 2)
            #expect(r.noOutputOfPriorPics == ((16...21).contains(type) ? true:nil))
            #expect(!r.completeSliceConformanceVerified && !r.activePictureParameterSetSelectionVerified)
        }}
        let tiny=slice(type:20,pps:63),r=try prefix(tiny,payloadBytes:1<<30)
        #expect(r.encodedPrefixBytes == 2 && !r.completeSliceConformanceVerified)
        // Entire opaque slice suffix, including invalid escape syntax, is not validated.
        let badSuffix=slice()+Data([0,0,1,0]),partial=try prefix(badSuffix)
        #expect(partial.ppsID == 0 && !partial.completeSliceConformanceVerified)
    }
    @Test func nonFirstReservedTemporalLayerMissingAndOversizedSlicePrefixesRefuse() throws {
        for n in [slice(first:0),slice(pps:64),slice(pps:65535),Data([2,1]),Data([2,1,0]),Data([2,1,128]),slice(type:2),slice(type:3),slice(type:4),slice(type:5)] {
            #expect(throws:(any Error).self){try prefix(n)}
        }
        for type in [UInt8(10),11,12,13,14,15,22,23,24,31,32,33,34,62,63] {#expect(throws:(any Error).self){try prefix(slice(type:type))}}
        var forbidden=slice();forbidden[0] |= 128;var layer=slice();layer[0] |= 1;var temporal=slice();temporal[1]=2
        for n in [forbidden,layer,temporal]{#expect(throws:(any Error).self){try prefix(n)}}
        #expect(throws:(any Error).self){try SPS.readFirstSlicePrefix(header:Data([2,1]),prefix:Data([0xc0,0,0]),payloadBytes:3)}
        #expect(throws:(any Error).self){try prefix(slice(),payloadBytes:(1<<40)+1)}
    }
    @Test func selectedSourceVCLReadbackPreservesSignedDuplicateRowsAndRefusesAmbiguity() throws {
        let bytes=source(references(),vcl:[slice()],times:[-2,-2,1,-1],rpuCopies:2),v=view(bytes),track=try CompanionOriginalTrackCheck.readSource(v)
        var rows:[CompanionOriginalPacketCheck.VCLReference]=[]
        let r=try CompanionOriginalPacketCheck.readSourceVCLReferences(v,track:track,observeVCL:{rows.append($0)})
        #expect(rows.map(\.packetIndex) == [0,1,2,3] && rows.map(\.ptsNS) == [-2,-2,1,-1] && rows.allSatisfy{$0.nalIndex == 2})
        #expect(r.summary.prefixes == 4 && r.packets.records == 8 && r.summary.peakPrefixBytes <= 2 && !r.summary.activePictureParameterSetSelectionVerified)
        for list in [[],[slice(),slice()],[slice(first:0)],[slice(pps:1)],[slice(type:22)]] {
            let d=source(references(),vcl:list),t=try CompanionOriginalTrackCheck.readSource(view(d))
            #expect(throws:(any Error).self){try CompanionOriginalPacketCheck.readSourceVCLReferences(view(d),track:t)}
            _ = try CompanionOriginalPacketCheck.readSource(view(d),track:t) // Old source framing remains separate.
        }
        let changed=source(references(nil,nil,pps(id:1)),vcl:[slice(pps:1)]),stale=try CompanionOriginalTrackCheck.readSource(view(bytes))
        #expect(throws:(any Error).self){try CompanionOriginalPacketCheck.readSourceVCLReferences(view(changed),track:stale)}
        let fresh=try CompanionOriginalTrackCheck.readSource(view(changed)),repaired=try CompanionOriginalPacketCheck.readSourceVCLReferences(view(changed),track:fresh)
        #expect(repaired.parameters.ppsID == 1 && !repaired.summary.activePictureParameterSetSelectionVerified)
    }
    @Test func largeOpaqueSourceVCLHashesInChunksAndReadsOnlyTwoAdditionalPrefixBytes() throws {
        let picture=slice()+Data(repeating:0,count:(1<<21)+17),bytes=source(references(),vcl:[picture]),base=view(bytes)
        var peak=0,rows:[CompanionOriginalPacketCheck.VCLReference]=[],reads:[(Int64,Int)]=[]
        let v=CompanionDiskCheck.ReadView(sourceBytes:base.sourceBytes,source:{o,n in peak=max(peak,n);reads.append((o,n));return try base.source(o,n)},component:base.component,checkpoint:base.checkpoint)
        let t=try CompanionOriginalTrackCheck.readSource(v),r=try CompanionOriginalPacketCheck.readSourceVCLReferences(v,track:t,observeVCL:{rows.append($0)})
        let row=try #require(rows.first)
        #expect(peak <= 1<<20 && row.nalBytes > 1<<21 && r.summary.peakPrefixBytes == 2)
        #expect(reads.contains{$0.0 == row.nalOffset+2 && $0.1 == 2})
        #expect(!row.prefix.completeSliceConformanceVerified && !r.summary.activePictureParameterSetSelectionVerified)
    }
    @Test func parameterCropAdmissionRequiresVideoConfigurationAndUniqueVisibleVCLBeforeDecoder() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("parameter-crop-admission-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        defer{print("GENERATED_PARAMETER_CROP_ADMISSION_REVIEW "+root.path)}
        let video=element(0xe0,element(0xb0,Data([160]))+element(0xba,Data([96])))
        let cases=[source(configuration([nal()]),vcl:[slice()],video:video),
            source(references(),vcl:[slice(pps:1)],video:video),
            source(references(),vcl:[slice(),slice()],video:video),
            source(references(),video:video),source(references(),vcl:[slice(first:0)],video:video),
            source(references(),vcl:[slice(type:22)],video:video),
            source(references(),inBand:34,vcl:[slice()],video:video),
            source(references(),vcl:[slice()],video:video,invisible:true),source(references(),vcl:[slice()])]
        let tool=try DolbyDecoderProcess.Tool.developmentCrops(root.appendingPathComponent("Helpers/crop-probe"),
            expectedSHA256:DolbySampleProcessTests.hash,libraries:Dictionary(uniqueKeysWithValues:DolbySampleProcessTests.names.map{($0,DolbySampleProcessTests.hash)}),versions:[1,1,1])
        let request=try DolbyCropProcessTests.request()
        for (index,bytes) in cases.enumerated() {
            let input=root.appendingPathComponent(String(index)+".mkv"),folder=root.appendingPathComponent("spool"+String(index)),ledger=DecoderCloseObservations()
            try bytes.write(to:input);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
            await DolbyDecoderProcess.$testBoundary.withValue(.init(launched:{ledger.launch($0)},closed:{ledger.close($0,$1,$2)})){
                await #expect(throws:NativeExportError.self){try await CompanionDiskCheck.associateOriginalParameterCrops(source:input,in:folder,tool:tool,request:request)}
            };ledger.expect([],launched:false)
            #expect(try Data(contentsOf:input) == bytes)
        }
    }
    @Test func actualGeneratedVCLSourceCountsStorageCancellationAndFinalSelection() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("source-vcl-native-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);defer{print("GENERATED_SOURCE_VCL_REVIEW "+root.path)}
        _ = try await RustFixtureBuild.generate(.reference,at:root,copiesIn:root)
        func folder(_ name:String) throws -> URL {let u=root.appendingPathComponent(name);try FileManager.default.createDirectory(at:u,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);return u}
        for name in ["single","group","wide-vint","conformance","whole-gop"] {
            let input=root.appendingPathComponent(name+".mkv"),bytes=try Data(contentsOf:input),stage=try folder("spool-"+name)
            let r=try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched:{_ in Issue.record("VCL source-only path launched decoder")})){
                try await CompanionDiskCheck.spoolOriginalSourceVCLReferences(source:input,in:stage)
            }
            #expect(r.vcl.prefixes == (name == "whole-gop" ? 24:4) && r.vcl.prefixes == r.source.packets.packets && r.parameters.ppsID == 0 && r.vcl.peakPrefixBytes == 2)
            #expect(r.originalFirstSlicePPSPrefixesBoundToSource && !r.activePictureParameterSetSelectionVerified && !r.completeSliceAndParameterConformanceVerified && !r.independentSourceFrameAssociationVerified && !r.independentSourceROIProvenanceVerified && !r.independentSampleValuesVerified && !r.editedPictureSemanticsVerified)
            #expect(try Data(contentsOf:input) == bytes)
            print("GENERATED_SOURCE_VCL counts=\(r.vcl.prefixes) iraps=\(r.vcl.irapPrefixes)")
        }
        let input=root.appendingPathComponent("single.mkv"),bytes=try Data(contentsOf:input)
        for kind in ["cap","read-cancel","late-cancel","extra","source-substitute"] {
            let stage=try folder(kind),gate=DolbySampleProcessTests.Gate(),cancel=kind.hasSuffix("cancel")
            let task=Task{defer{gate.signal.finish()};return try await CompanionDiskCheck.$testBoundary.withValue(.init(beforeFinal:{if kind == "late-cancel"{gate.hold()};if kind == "extra"{do{try Data([1]).write(to:stage.appendingPathComponent("extra"))}catch{Issue.record("Generated VCL final extra failed")}};if kind == "source-substitute"{do{try FileManager.default.moveItem(at:input,to:input.appendingPathExtension("original"));try bytes.write(to:input)}catch{Issue.record("Generated VCL substitution failed")}}},originalTrackRead:{_,_ in if kind == "read-cancel"{gate.hold()}})){
                try await CompanionDiskCheck.spoolOriginalSourceVCLReferences(source:input,in:stage,limits:.init(records:kind == "cap" ? 1:2_000_000))
            }}
            if cancel{for await _ in gate.stream{break};task.cancel();gate.release.signal()}
            do{_ = try await task.value;Issue.record("VCL source refusal admitted")}catch is CancellationError{#expect(cancel)}catch{#expect(!cancel)}
            #expect(try Data(contentsOf:input) == bytes)
        }
        let many=root.appendingPathComponent("many.mkv"),manyBytes=source(references(),repeats:2000,vcl:[slice()]),stage=try folder("full")
        try manyBytes.write(to:many)
        await #expect(throws:(any Error).self){try await CompanionDiskCheck.spoolOriginalSourceVCLReferences(source:many,in:stage,limits:.init(pages:8))}
        let size=(try FileManager.default.attributesOfItem(atPath:stage.appendingPathComponent(DolbyAssociationSpool.name).path)[.size] as? NSNumber)?.intValue
        #expect(size == 8*4096);#expect(try Data(contentsOf:many) == manyBytes)
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
    private func source(_ cfg: Data, inBand: UInt8? = nil, repeats: Int = 1, vcl: [Data] = [], times: [Int16]? = nil, rpuCopies: Int = 1, video: Data? = nil, invisible: Bool = false) -> Data {
        let track=element(0xae,element(0xd7,Data([1]))+element(0x83,Data([1]))+element(0x86,Data("V_MPEGH/ISO/HEVC".utf8))+element(0x63a2,cfg)+(video ?? Data()))
        var packet=(0..<rpuCopies).reduce(Data()){d,_ in d+Data([0,0,0,3,0x7c,1,0xaa])}
        for n in vcl {let size=UInt32(n.count);packet.append(contentsOf:(0..<4).reversed().map{UInt8(size>>(8*$0)&255)});packet.append(n)}
        if let inBand {packet.append(contentsOf:[0,0,0,3,inBand<<1,1,0x80])}
        let cluster=element(0x1f43b675,element(0xe7,Data([0]))+(times ?? [Int16](repeating:0,count:repeats)).reduce(Data()){d,t in let bits=UInt16(bitPattern:t);return d+element(0xa3,Data([0x81,UInt8(bits>>8),UInt8(bits&255),invisible ? 0x88:0x80])+packet)})
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
    private func codingNAL(width: Int = 176, height: Int = 112, sub: Int = 0,
        all: Bool = false, poc: Int = 8, minCb: Int = 0, diff: Int = 3,
        records: [[Int]]? = nil, cropped: Bool = true) -> Data {
        nal(width: width, height: height, crop: cropped ? [0,7,0,7] : nil, sub: sub, codingTail: { w in
            w.ue(poc); w.put(all ? 1 : 0,1)
            for row in records ?? [[Int]](repeating:[3,2,0],count:all ? sub+1 : 1) {
                for value in row { w.ue(value) }
            }
            w.ue(minCb); w.ue(diff)
            // Deliberately opaque suffix; these are not complete valid SPS vectors.
            w.put(255,8)
        })
    }
    @Test func codingTreePrefixReadsFiniteOrderingAndCodedGridIndependentOfCrop() throws {
        for width in 1...4 { for sub in 0...6 { for all in [false,true] {
            let cfg=referenceConfiguration([(32,true,[vps(sub:sub)]),(33,true,[codingNAL(sub:sub,all:all)]),(34,true,[pps()])],width:width)
            let r=try SPS.readConfigurationCodingTreePrefix(cfg)
            #expect(r.columns == 3 && r.rows == 2 && r.ctbs == 6 && r.addressBits == 3 && r.pocLSBBits == 12)
            #expect(r.minCbLog2Size == 3 && r.ctbLog2Size == 6 && r.parameters.geometry.visibleWidth == 162)
            #expect(r.orderingInfoPresentForAllSubLayers == all && r.presentOrdering.count == (all ? sub+1:1))
            #expect(r.presentOrdering.first?.subLayer == (all ? 0:sub) && r.presentOrdering.last?.subLayer == sub)
            #expect(r.presentOrdering.allSatisfy{$0.bufferingMinus1 == 3 && $0.reorderPictures == 2 && $0.latencyIncreasePlus1 == 0})
            #expect(!r.completeSPSConformanceVerified && !r.activePictureParameterSetSelectionVerified && !r.independentSourceROIProvenanceVerified && !r.independentSampleValuesVerified && !r.editedPictureSemanticsVerified)
        }}}
        for minCb in 0...3 {for diff in 0...3 where (4...6).contains(minCb+3+diff) {
            let r=try SPS.readConfigurationCodingTreePrefix(references(nil,codingNAL(width:192,height:128,minCb:minCb,diff:diff),nil))
            let side=1<<(minCb+3+diff)
            #expect(r.columns == 192/side && r.rows == 128/side && r.ctbs == (192/side)*(128/side))
        }}
        let one=try SPS.readConfigurationCodingTreePrefix(references(nil,codingNAL(width:16,height:16,cropped:false),nil))
        #expect(one.ctbs == 1 && one.addressBits == 0)
        let max=try SPS.readConfigurationCodingTreePrefix(references(nil,codingNAL(width:16384,height:16384,minCb:0,diff:1,records:[[15,15,65534]]),nil))
        #expect(max.ctbs == 1<<20 && max.addressBits == 20 && max.presentOrdering[0].latencyIncreasePlus1 == 65534)
        let noCrop=try SPS.readConfigurationCodingTreePrefix(references(nil,codingNAL(cropped:false),nil))
        #expect(noCrop.ctbs == 6 && !noCrop.completeSPSConformanceVerified)
    }
    @Test func codingTreePrefixRefusesAmbiguityTruncationOrderingAndGridBoundsWithoutWideningOldAPI() throws {
        let cases=[codingNAL(poc:13),codingNAL(minCb:4),codingNAL(diff:4),codingNAL(minCb:0,diff:0),
            codingNAL(minCb:3,diff:1),codingNAL(width:174),codingNAL(height:110),
            codingNAL(records:[[16,0,0]]),codingNAL(records:[[3,4,0]]),codingNAL(records:[[3,2,65535]]),
            codingNAL(sub:1,all:true,records:[[3,2,0],[2,1,0]]),codingNAL(sub:1,all:true,records:[[3,2,0],[3,1,0]])]
        for n in cases {#expect(throws:(any Error).self){try SPS.readConfigurationCodingTreePrefix(references(nil,n,nil))}}
        let n=codingNAL(),cfg=references(nil,n,nil)
        for bad in [configuration([n]),referenceConfiguration([(32,true,[vps()]),(33,true,[n,n]),(34,true,[pps()])]),
            referenceConfiguration([(32,true,[vps()]),(33,true,[n]),(33,false,[]),(34,true,[pps()])]),
            references(nil,n+Data([0,0,3,4]),nil),references(vps(id:1),n,nil)] {
            #expect(throws:(any Error).self){try SPS.readConfigurationCodingTreePrefix(bad)}
        }
        for tail in 0...4 {
            let partial=nal(codingTail:{w in
                w.ue(8)
                if tail>0{w.put(0,1)}
                if tail>1{w.ue(3)}
                if tail>2{w.ue(2)}
                if tail>3{w.ue(0)}
            })
            #expect(throws:(any Error).self){try SPS.readConfigurationCodingTreePrefix(references(nil,partial,nil))}
        }
        let geometry=try SPS.readConfigurationReferences(cfg).geometry
        for count in 2...Int(geometry.prefixBitCount/8) {#expect(throws:(any Error).self){try SPS.readConfigurationCodingTreePrefix(references(nil,Data(n.prefix(count)),nil))}}
        #expect(throws:CancellationError.self){try SPS.readConfigurationCodingTreePrefix(cfg,checkpoint:{throw CancellationError()})}
        let old=try SPS.readConfigurationReferences(references())
        #expect(old.geometry.codedWidth == 176 && !old.completeParameterSetConformanceVerified)
        #expect(throws:(any Error).self){try SPS.readConfigurationCodingTreePrefix(references())}
    }
    @Test func sourceCodingTreePrefixBindsFreshTrackAndRepairedConfigurationOnly() throws {
        let bytes=source(references(nil,codingNAL(),nil)),v=view(bytes),t=try CompanionOriginalTrackCheck.readSource(v)
        let r=try SPS.readSourceCodingTreePrefix(v,track:t);#expect(r.ctbs == 6)
        for field in 0..<7 {
            let bad=CompanionOriginalTrackCheck.Receipt(trackNumber:t.trackNumber+(field == 0 ? 1:0),originalPayloadOffset:t.originalPayloadOffset+(field == 1 ? 1:0),payloadBytes:t.payloadBytes+(field == 2 ? 1:0),configurationBytes:t.configurationBytes+(field == 3 ? 1:0),nalLengthBytes:field == 4 ? 1:t.nalLengthBytes,payloadSHA256:field == 5 ? String(repeating:"a",count:64):t.payloadSHA256,configurationSHA256:field == 6 ? String(repeating:"b",count:64):t.configurationSHA256,originalTrackAndConfigurationMatch:true)
            #expect(throws:(any Error).self){try SPS.readSourceCodingTreePrefix(v,track:bad)}
        }
        let changed=source(references(nil,codingNAL(diff:2),nil)),cv=view(changed)
        #expect(throws:(any Error).self){try SPS.readSourceCodingTreePrefix(cv,track:t)}
        let fresh=try CompanionOriginalTrackCheck.readSource(cv),actual=try SPS.readSourceCodingTreePrefix(cv,track:fresh)
        #expect(actual.ctbLog2Size == 5 && actual.ctbs == 24 && !actual.activePictureParameterSetSelectionVerified)
    }
    @Test func sourceCodingTreeWorkerKeepsSignedDuplicatesInBandRefusalAndStorageCancellation() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("source-ctb-bounds-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);defer{print("GENERATED_CTB_BOUNDS_REVIEW "+root.path)}
        func folder(_ name:String)throws->URL{let f=root.appendingPathComponent(name);try FileManager.default.createDirectory(at:f,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);return f}
        let cfg=references(nil,codingNAL(),nil),signed=source(cfg,times:[2,-1,2,0],rpuCopies:2),input=root.appendingPathComponent("source.mkv")
        try signed.write(to:input)
        let r=try await CompanionDiskCheck.spoolOriginalSourceCodingTreePrefix(source:input,in:folder("signed"))
        #expect(r.source.packets.packets == 4 && r.source.packets.records == 8 && r.codingTree.ctbs == 6)
        #expect(r.originalCodingTreePrefixBoundToSource && r.selectedPacketParameterSetNALsAbsent && !r.independentSourceFrameAssociationVerified && !r.completeSPSConformanceVerified && !r.activePictureParameterSetSelectionVerified && !r.independentSourceROIProvenanceVerified && !r.independentSampleValuesVerified && !r.editedPictureSemanticsVerified)
        for type in [UInt8(32),33,34] {
            let bytes=source(cfg,inBand:type);try bytes.write(to:input)
            _ = try await CompanionDiskCheck.spoolOriginalSource(source:input,in:folder("old-"+String(type)))
            await #expect(throws:(any Error).self){try await CompanionDiskCheck.spoolOriginalSourceCodingTreePrefix(source:input,in:folder("new-"+String(type)))}
            #expect(try Data(contentsOf:input) == bytes)
        }
        let bytes=source(cfg,repeats:2000);try bytes.write(to:input)
        for kind in ["records","pages","read-cancel","final-cancel"] {
            let stage=try folder(kind),gate=DolbySampleProcessTests.Gate(),cancel=kind.hasSuffix("cancel")
            let limits=DolbyAssociationSpool.Limits(pages:kind == "pages" ? 8:131072,records:kind == "records" ? 1:2_000_000)
            let task=Task{defer{gate.signal.finish()};return try await CompanionDiskCheck.$testBoundary.withValue(.init(beforeFinal:{if kind == "final-cancel"{gate.hold()}},originalTrackRead:{_,_ in if kind == "read-cancel"{gate.hold()}})){
                try await CompanionDiskCheck.spoolOriginalSourceCodingTreePrefix(source:input,in:stage,limits:limits)
            }}
            if cancel{for await _ in gate.stream{break};task.cancel();gate.release.signal()}
            do{_ = try await task.value;Issue.record("CTB bounded source refusal admitted")}catch is CancellationError{#expect(cancel)}catch{#expect(!cancel)}
            if kind == "pages"{let size=(try FileManager.default.attributesOfItem(atPath:stage.appendingPathComponent(DolbyAssociationSpool.name).path)[.size] as? NSNumber)?.intValue;#expect(size == 8*4096)}
            #expect(try Data(contentsOf:input) == bytes)
        }
    }
    @Test func actualGeneratedHEVCCodingTreeSourceReadbackAndFinalIdentity() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("source-ctb-native-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);defer{print("GENERATED_CTB_NATIVE_REVIEW "+root.path)}
        _ = try await RustFixtureBuild.generate(.reference,at:root,copiesIn:root)
        func folder(_ name:String)throws->URL{let f=root.appendingPathComponent(name);try FileManager.default.createDirectory(at:f,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);return f}
        for name in ["single","group","wide-vint","conformance","whole-gop"] {
            let input=root.appendingPathComponent(name+".mkv"),bytes=try Data(contentsOf:input)
            let r=try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched:{_ in Issue.record("CTB source-only path launched decoder")})){
                try await CompanionDiskCheck.spoolOriginalSourceCodingTreePrefix(source:input,in:folder("spool-"+name))
            }
            let g=r.codingTree,geometry=g.parameters.geometry
            #expect(geometry.codedWidth == (name == "conformance" ? 176:160) && geometry.codedHeight == (name == "conformance" ? 112:96))
            #expect(g.minCbLog2Size == 4 && g.ctbLog2Size == 5 && g.columns == (name == "conformance" ? 6:5) && g.rows == (name == "conformance" ? 4:3) && g.ctbs == (name == "conformance" ? 24:15) && g.addressBits == (name == "conformance" ? 5:4))
            #expect(r.source.packets.packets == (name == "whole-gop" ? 24:4) && r.source.packets.records == r.source.packets.packets)
            #expect(geometry.configurationSHA256 == r.source.track.configurationSHA256 && r.source.sourceSHA256 == DolbyInspection.hex(SHA256.hash(data:bytes)))
            #expect(!r.completeSPSConformanceVerified && !r.activePictureParameterSetSelectionVerified && !r.independentSourceFrameAssociationVerified && !r.independentSourceROIProvenanceVerified && !r.independentSampleValuesVerified && !r.editedPictureSemanticsVerified)
            #expect(try Data(contentsOf:input) == bytes)
            print("Generated CTB "+name+" min="+String(g.minCbLog2Size)+" ctb="+String(g.ctbLog2Size)+" grid="+String(g.columns)+"x"+String(g.rows))
        }
        for extra in [false,true] {
            let input=root.appendingPathComponent("final-"+String(extra)),bytes=try Data(contentsOf:root.appendingPathComponent("single.mkv")),stage=try folder("final-spool-"+String(extra));try bytes.write(to:input)
            await CompanionDiskCheck.$testBoundary.withValue(.init(beforeFinal:{do{if extra{try Data([1]).write(to:stage.appendingPathComponent("extra"))}else{try FileManager.default.moveItem(at:input,to:input.appendingPathExtension("original"));try bytes.write(to:input)}}catch{Issue.record("CTB final substitution failed")}})){
                await #expect(throws:(any Error).self){try await CompanionDiskCheck.spoolOriginalSourceCodingTreePrefix(source:input,in:stage)}
            }
            #expect(try Data(contentsOf:input) == bytes)
        }
    }

    private func segment(type: UInt8 = 1, pps: Int = 0, first: Bool = true, prior: Bool = false,
        dependent: Bool? = nil, address: Int = 0, addressBits: Int = 0) -> Data {
        var w=Writer();w.put(first ? 1:0,1)
        if (16...23).contains(type){w.put(prior ? 1:0,1)}
        w.ue(pps)
        if !first {if let dependent{w.put(dependent ? 1:0,1)};w.put(address,addressBits)}
        w.put(0xaa,8) // Opaque suffix, not a complete slice.
        return escaped(w.bytes(),type:type)
    }
    private func segmentGrid(ppsID: Int = 0, dependent: Bool = true, large: Bool = false) throws -> SPS.CodingTreePrefix {
        try SPS.readConfigurationCodingTreePrefix(references(nil,
            codingNAL(width:large ? 16384:176,height:large ? 16384:112,diff:large ? 1:3),
            pps(id:ppsID,dependent:dependent ? 1:0)))
    }
    private func segmentPrefix(_ n:Data,_ grid:SPS.CodingTreePrefix,payloadBytes:Int64? = nil) throws -> SPS.SliceSegmentPrefix {
        let payload=Data(n.dropFirst(2))
        return try SPS.readSliceSegmentPrefix(header:Data(n.prefix(2)),payloadBytes:payloadBytes ?? Int64(payload.count),grid:grid,readByte:{offset in
            #expect(offset<7 && offset<payload.count);return payload[offset]
        })
    }
    @Test func segmentPrefixesReadRawPresenceTypesPPSIDsAndGridAddressBounds() throws {
        let types:[UInt8]=[0,1,6,7,8,9,16,17,18,19,20,21]
        for type in types {for id in 0...63 {for first in [false,true] {
            let grid=try segmentGrid(ppsID:id)
            let n=segment(type:type,pps:id,first:first,prior:true,dependent:first ? nil:true,address:5,addressBits:3)
            let r=try segmentPrefix(n,grid)
            #expect(r.ppsID == id && r.nalType == Int(type) && r.firstSliceSegmentInPicture == first)
            #expect(r.address == (first ? nil:5) && r.dependentSliceSegment == (first ? nil:true))
            #expect(r.noOutputOfPriorPics == ((16...21).contains(type) ? true:nil))
            #expect(r.encodedPrefixBytes<=7 && r.prefixBits<=36 && !r.completeSliceConformanceVerified && !r.activePictureParameterSetSelectionVerified)
        }}}
        let disabled=try segmentGrid(dependent:false),r=try segmentPrefix(segment(first:false,address:0,addressBits:3),disabled)
        #expect(r.address == 0 && r.dependentSliceSegment == nil)
        // Zero is individual syntax range-valid; same-picture uniqueness is not inferred.
        let one=try SPS.readConfigurationCodingTreePrefix(references(nil,codingNAL(width:16,height:16,cropped:false),nil))
        let single=try segmentPrefix(segment(first:false),one);#expect(single.address == 0 && !single.firstSliceSegmentInPicture)
    }
    @Test func segmentIncrementalEscapeSevenByteBoundTruncationAndOpaqueSuffix() throws {
        let grid=try segmentGrid(ppsID:63,large:true),n=segment(pps:63,first:false,dependent:false,address:0,addressBits:20)
        #expect(n.range(of:Data([0,0,3,0])) != nil)
        let r=try segmentPrefix(n,grid,payloadBytes:1<<30)
        #expect(r.address == 0 && r.encodedPrefixBytes<=7 && r.prefixBits == 35)
        for size in 0..<r.encodedPrefixBytes {
            let truncated=Data(n.prefix(size+2));#expect(throws:(any Error).self){try segmentPrefix(truncated,grid)}
        }
        var bad=n;let at=try #require(bad.range(of:Data([0,0,3,0])));bad[at.lowerBound+3]=4
        #expect(throws:(any Error).self){try segmentPrefix(bad,grid)}
        var absent=n;absent.remove(at:at.lowerBound+2)
        #expect(throws:(any Error).self){try segmentPrefix(absent,grid)}
        let changed=n+Data([0,0,3,4]) // Unread suffix remains deliberately opaque.
        let accepted=try segmentPrefix(changed,grid);#expect(!accepted.completeSliceConformanceVerified)
        #expect(throws:CancellationError.self){try SPS.readSliceSegmentPrefix(header:Data(n.prefix(2)),payloadBytes:100,grid:grid,readByte:{_ in throw CancellationError()})}
    }
    @Test func segmentPrefixRefusesUnsupportedHeadersReferencesAndOutOfGridAddresses() throws {
        let grid=try segmentGrid(),n=segment(first:false,dependent:false,address:6,addressBits:3)
        #expect(throws:(any Error).self){try segmentPrefix(n,grid)}
        for type in [UInt8(2),3,4,5,10,11,15,22,23,24,31] {#expect(throws:(any Error).self){try segmentPrefix(segment(type:type),grid)}}
        for bad in [Data([0x82,1,255]),Data([2,9,255]),Data([2,2,255]),Data([2,0,255]),segment(pps:1),segment(pps:64),Data([2,1,0,0,0])] {
            #expect(throws:(any Error).self){try segmentPrefix(bad,grid)}
        }
        let changed=SPS.CodingTreePrefix(parameters:grid.parameters,pocLSBBits:grid.pocLSBBits,prefixBitCount:grid.prefixBitCount,
            orderingInfoPresentForAllSubLayers:grid.orderingInfoPresentForAllSubLayers,presentOrdering:grid.presentOrdering,
            minCbLog2Size:grid.minCbLog2Size,ctbLog2Size:grid.ctbLog2Size,columns:grid.columns,rows:grid.rows,ctbs:6,addressBits:2)
        #expect(throws:(any Error).self){try segmentPrefix(segment(),changed)}
    }
    @Test func sourceSegmentPrefixesStreamSignedDuplicateRawReferencesAndKeepFirstOnlyAPINarrow() throws {
        let cfg=references(nil,codingNAL(),pps(dependent:1)),nonfirst=segment(first:false,dependent:true,address:5,addressBits:3)
        let bytes=source(cfg,vcl:[nonfirst],times:[2,-1,2],rpuCopies:2),v=view(bytes),track=try CompanionOriginalTrackCheck.readSource(v)
        var refs:[CompanionOriginalPacketCheck.SegmentReference]=[]
        let r=try CompanionOriginalPacketCheck.readSourceSegmentPrefixes(v,track:track,observeSegment:{refs.append($0)})
        #expect(r.packets.packets == 3 && r.packets.records == 6 && r.summary.prefixes == 3 && r.summary.firstPrefixes == 0 && r.summary.dependentPrefixes == 3)
        #expect(refs.map(\.ptsNS) == [2,-1,2] && refs.map(\.packetIndex) == [0,1,2] && refs.allSatisfy{$0.prefix.address == 5})
        #expect(!r.summary.pictureGroupingVerified && !r.summary.completeSliceConformanceVerified && !r.summary.activePictureParameterSetSelectionVerified)
        #expect(throws:(any Error).self){try CompanionOriginalPacketCheck.readSourceVCLReferences(v,track:track)}
        for b in [source(cfg),source(cfg,vcl:[nonfirst,nonfirst]),source(cfg,vcl:[nonfirst],invisible:true),source(cfg,inBand:33,vcl:[nonfirst]),source(cfg,vcl:[segment(pps:1)])] {
            let actual=try CompanionOriginalTrackCheck.readSource(view(b))
            #expect(throws:(any Error).self){try CompanionOriginalPacketCheck.readSourceSegmentPrefixes(view(b),track:actual)}
        }
        let changed=source(references(nil,codingNAL(diff:2),pps(dependent:1)),vcl:[segment(first:false,dependent:true,address:5,addressBits:5)])
        #expect(throws:(any Error).self){try CompanionOriginalPacketCheck.readSourceSegmentPrefixes(view(changed),track:track)}
        let actual=try CompanionOriginalTrackCheck.readSource(view(changed)),fresh=try CompanionOriginalPacketCheck.readSourceSegmentPrefixes(view(changed),track:actual)
        #expect(fresh.codingTree.ctbs == 24 && fresh.summary.dependentPrefixes == 1 && !fresh.summary.activePictureParameterSetSelectionVerified)
        // Large picture suffix is hashed in chunks; incremental prefix reads remain seven bytes.
        let large=segment()+Data(repeating:255,count:2<<20),big=source(cfg,vcl:[large]);var requests:[(Int64,Int)]=[]
        let bv=CompanionDiskCheck.ReadView(sourceBytes:Int64(big.count),source:{o,n in requests.append((o,n));return big.subdata(in:Int(o)..<Int(o)+n)},component:{_ in throw CancellationError()},checkpoint:{})
        let bt=try CompanionOriginalTrackCheck.readSource(bv);var seen:CompanionOriginalPacketCheck.SegmentReference?
        _ = try CompanionOriginalPacketCheck.readSourceSegmentPrefixes(bv,track:bt,observeSegment:{seen=$0})
        let ref=try #require(seen),prefixReads=requests.filter{$0.1 == 1 && $0.0>=ref.nalOffset+2 && $0.0<ref.nalOffset+9}
        #expect(prefixReads.count == ref.prefix.encodedPrefixBytes && prefixReads.count<=7 && requests.allSatisfy{$0.1<=1<<20})
    }
    @Test func sourceSegmentWorkerGeneratedConfigurationsStorageCancellationAndFinalRefusals() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("source-segment-native-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);defer{print("GENERATED_SEGMENT_NATIVE_REVIEW "+root.path)}
        _ = try await RustFixtureBuild.generate(.reference,at:root,copiesIn:root)
        func folder(_ name:String)throws->URL{let f=root.appendingPathComponent(name);try FileManager.default.createDirectory(at:f,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);return f}
        for name in ["single","group","wide-vint","conformance","whole-gop"] {
            let input=root.appendingPathComponent(name+".mkv"),bytes=try Data(contentsOf:input)
            let r=try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched:{_ in Issue.record("Segment source-only path launched decoder")})){
                try await CompanionDiskCheck.spoolOriginalSourceSegmentPrefixes(source:input,in:folder("spool-"+name))
            }
            let count:Int64=name == "whole-gop" ? 24:4
            #expect(r.source.packets.packets == count && r.segments.summary.prefixes == count && r.segments.summary.firstPrefixes == count && r.segments.summary.dependentPrefixes == 0)
            #expect(r.segments.summary.peakPrefixBytes<=7 && r.segments.codingTree.ctbs == (name == "conformance" ? 24:15))
            #expect(r.originalVCLSegmentPrefixesBoundToSource && r.selectedPacketParameterSetNALsAbsent && !r.pictureGroupingVerified && !r.completeSliceAndParameterConformanceVerified && !r.activePictureParameterSetSelectionVerified && !r.independentSourceFrameAssociationVerified && !r.independentSourceROIProvenanceVerified && !r.independentSampleValuesVerified && !r.editedPictureSemanticsVerified)
            #expect(try Data(contentsOf:input) == bytes)
        }
        let input=root.appendingPathComponent("fault-source.mkv"),bytes=source(references(nil,codingNAL(),pps(dependent:1)),repeats:2000,vcl:[segment(first:false,dependent:true,address:5,addressBits:3)]);try bytes.write(to:input)
        for kind in ["records","pages","read-cancel","final-cancel","extra","source-substitute"] {
            let stage=try folder(kind),gate=DolbySampleProcessTests.Gate(),cancel=kind.hasSuffix("cancel")
            let limits=DolbyAssociationSpool.Limits(pages:kind == "pages" ? 8:131072,records:kind == "records" ? 1:2_000_000)
            let task=Task{defer{gate.signal.finish()};return try await CompanionDiskCheck.$testBoundary.withValue(.init(beforeFinal:{if kind == "final-cancel"{gate.hold()};do{if kind == "extra"{try Data([1]).write(to:stage.appendingPathComponent("extra"))};if kind == "source-substitute"{try FileManager.default.moveItem(at:input,to:input.appendingPathExtension("original"));try bytes.write(to:input)}}catch{Issue.record("Segment final substitution failed")}},originalTrackRead:{_,_ in if kind == "read-cancel"{gate.hold()}})){
                try await CompanionDiskCheck.spoolOriginalSourceSegmentPrefixes(source:input,in:stage,limits:limits)
            }}
            if cancel{for await _ in gate.stream{break};task.cancel();gate.release.signal()}
            do{_ = try await task.value;Issue.record("Segment source refusal admitted")}catch is CancellationError{#expect(cancel)}catch{#expect(!cancel)}
            if kind == "pages"{let size=(try FileManager.default.attributesOfItem(atPath:stage.appendingPathComponent(DolbyAssociationSpool.name).path)[.size] as? NSNumber)?.intValue;#expect(size == 8*4096)}
            #expect(try Data(contentsOf:input) == bytes)
        }
    }

}
