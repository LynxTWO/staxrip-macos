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
                     reserved: Int = 0, vpsID: Int = 0) -> Data {
        var w = Writer(); w.put(vpsID,4); w.put(sub,3); w.put(1,1)
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
}
