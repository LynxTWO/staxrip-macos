import Foundation
import Darwin
import Testing
@testable import StaxRipMac

@Suite(.serialized)
struct CompatibleNativeSourceCropTests {
    typealias Owner=DolbyDecoderProcess
    typealias Stream=DolbyDecoderStream
    typealias Support=DolbySampleProcessTests
    private nonisolated static var directory:String?{ProcessInfo.processInfo.environment["STAXRIP_TEST_CROP_DECODER_DIRECTORY"]}
    @Test(.enabled(if:directory != nil), .timeLimit(.minutes(2)))
    func actualOriginalSourceOpenSpoolCallerCropBindingAndSettledRefusals() async throws {
        let runtime=URL(fileURLWithPath:try #require(Self.directory),isDirectory:true),exe=runtime.appendingPathComponent("Helpers/crop-probe")
        let hashes=Dictionary(uniqueKeysWithValues:try Support.names.map{($0,try Support.digest(runtime.appendingPathComponent("Frameworks/"+$0)))})
        let exeHash=try Support.digest(exe)
        let tool=try Owner.Tool.developmentCrops(exe,expectedSHA256:exeHash,libraries:hashes,versions:[4129126,4129126,3998054])
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("native-source-crops-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        var cleanup=false;defer{if cleanup{try? FileManager.default.removeItem(at:root)}}
        _ = try await RustFixtureBuild.generate(.reference, at: root, copiesIn: root)
        let prior=root.appendingPathComponent("prior");try Data("prior".utf8).write(to:prior)
        func spool(_ name:String) throws -> URL {
            let u=root.appendingPathComponent(name);try FileManager.default.createDirectory(at:u,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);return u
        }
        let request=try DolbyCropProcessTests.request(.coded)
        var joins=0,retained=false,liveRetained=false
        for name in ["single","group","wide-vint","conformance","whole-gop"] {
            let source=root.appendingPathComponent(name+".mkv"),hash=try Support.digest(source)
            for space in [Stream.CropRequest.Space.coded,.codecVisible] {
            let request=try Stream.CropRequest(space:space,x:2,y:2,width:16,height:10)
            for threads in [1,4] {
                let stage=try spool(name+space.rawValue+String(threads)),state=Support.State(),ledger=DecoderCloseObservations()
                let r=try await Owner.$testBoundary.withValue(.init(launched:{state.launch($0);ledger.launch($0)},settled:{state.settle($0);ledger.settle($0)},closed:{ledger.close($0,$1,$2)})){
                    try await CompanionDiskCheck.associateOriginalCrops(source:source,in:stage,tool:tool,request:request,threads:threads)
                }
                state.assertJoined();ledger.expect(Set(Owner.DescriptorRole.allCases),launched:true);joins += 1
                #expect(r.independentSourceFrameAssociationVerified && r.originalSourceAndCallerCropAgreementVerified)
                #expect(!r.independentSourceROIProvenanceVerified && !r.independentSampleValuesVerified && !r.editedPictureSemanticsVerified && !r.decoder.independentSourceFrameAssociationVerified)
                #expect(r.source.sourceSHA256 == hash && r.decoder.source.sha256 == hash && r.source.track.configurationSHA256 == r.decoder.configurationSHA256)
                #expect(r.source.packets.packets == r.decoder.packets && r.source.packets.records == r.decoder.frames && r.decoder.cropFrameSummaryCount == r.decoder.frames)
                #expect(r.decoder.frames == (name == "whole-gop" ? 24:4))
                #expect(try FileManager.default.contentsOfDirectory(atPath:stage.path) == [DolbyAssociationSpool.name])
                if name == "conformance"{#expect(r.decoder.geometry.crop == [0,14,0,14])}
                #expect(try Support.digest(source) == hash)
            }
        }
        }
        for space in [Stream.CropRequest.Space.coded,.codecVisible] {
            let source=root.appendingPathComponent("conformance.mkv"),stage=try spool("full-"+space.rawValue),state=Support.State()
            let request=try Stream.CropRequest(space:space,x:0,y:0,width:space == .coded ? 176:162,height:space == .coded ? 112:98)
            let r=try await Owner.$testBoundary.withValue(.init(launched:{state.launch($0)},settled:{state.settle($0)})){
                try await CompanionDiskCheck.associateOriginalCrops(source:source,in:stage,tool:tool,request:request)
            };state.assertJoined();joins += 1
            #expect(r.originalSourceAndCallerCropAgreementVerified && r.decoder.cropRequest == request && r.decoder.frames == 4)
            #expect(r.decoder.geometry.crop == [0,14,0,14] && r.decoder.geometry.sampleAspectRatio == nil)
        }
        let original=root.appendingPathComponent("single.mkv"),hash=try Support.digest(original)
        // Actual fixed crop helper's reported-close uncertainty prevents the
        // enclosing source/spool receipt even after complete source coverage.
        for role in [Owner.DescriptorRole.stdoutWrite,.nullInput,.source] {
            let ledger=DecoderCloseObservations(refused:role),stage=try spool("close-refusal-"+role.rawValue)
            do{_ = try await Owner.$testBoundary.withValue(.init(launched:{ledger.launch($0)},settled:{ledger.settle($0)},closed:{ledger.close($0,$1,$2)},refuseClose:{r,_,_ in ledger.inject(r)})){
                try await CompanionDiskCheck.associateOriginalCrops(source:original,in:stage,tool:tool,request:request)
            };Issue.record("Actual source/crop close refusal admitted")}
            catch let e as Owner.OwnershipFailure{retained=true;#expect(e.reason == "descriptor-close");print("GENERATED_SOURCE_CROP_CLOSE_RETAINED role=\(role.rawValue) root=\(root.path)")}
            ledger.expect(Set(Owner.DescriptorRole.allCases),launched:true);joins += 1
            #expect(try Support.digest(original) == hash)
        }
        // Distinct metadata entry refuses crop role; no crop helper launch.
        let wrong=Support.State(),wrongStage=try spool("wrong-role")
        await Owner.$testBoundary.withValue(.init(launched:{wrong.launch($0)})){
            await #expect(throws:(any Error).self){try await CompanionDiskCheck.associateOriginalFrames(source:original,in:wrongStage,tool:tool)}
        }
        #expect(wrong.pid == 0)
        for fault in 0..<5 {
            let input=root.appendingPathComponent("fault-"+String(fault)+".mkv");try FileManager.default.copyItem(at:original,to:input)
            if fault == 4 {
                let data=try Data(contentsOf:original)
                let view=CompanionDiskCheck.ReadView(sourceBytes:Int64(data.count),source:{o,n in data.subdata(in:Int(o)..<(Int(o)+n))},component:{_ in throw CancellationError()},checkpoint:{})
                let walker=CompanionOriginalTrackCheck.Walker(view),header=try walker.element(0,end:view.sourceBytes),segment=try walker.element(header.end,end:view.sourceBytes)
                var prefix=Data(),clusters=Data(),offset=segment.payload
                while offset < segment.end{let e=try walker.element(offset,end:segment.end),bytes=data.subdata(in:Int(offset)..<Int(e.end));if e.id == 0x1f43b675{clusters.append(bytes)}else{prefix.append(bytes)};offset=e.end}
                try #require(!clusters.isEmpty)
                var repeated=data.prefix(Int(header.end))+Data([0x18,0x53,0x80,0x67,0xff])+prefix
                for _ in 0..<2000{repeated.append(clusters)}
                try repeated.write(to:input)
            }
            let inputHash=try Support.digest(input)
            let stage=try spool("fault-stage-"+String(fault)),state=Support.State(),gate=Support.Gate()
            let task=Task {
                defer{gate.signal.finish()}
                return try await CompanionDiskCheck.$testBoundary.withValue(.init(beforeFinal:{
                    if fault == 0 {try! Data("extra".utf8).write(to:stage.appendingPathComponent("extra"))}
                    if fault == 1 {let bytes=try! Data(contentsOf:input);try! FileManager.default.removeItem(at:input);try! bytes.write(to:input)}
                })){
                    try await Owner.$testBoundary.withValue(.init(launched:{state.launch($0)},row:{data in
                        if fault >= 3 && String(decoding:data,as:UTF8.self).contains("crop-frame"){gate.hold()}
                    },settled:{state.settle($0)},beforeReceipt:{if fault == 2{gate.hold()}})){
                        try await CompanionDiskCheck.associateOriginalCrops(source:input,in:stage,tool:tool,request:request)
                    }
                }
            }
            if fault >= 2 {
                for await _ in gate.stream{break}
                if fault == 4 {
                    try #require(state.pid > 0)
                    let ps=try await ToolRunner().run(executable:URL(fileURLWithPath:"/bin/ps"),arguments:["-p",String(state.pid),"-o","stat="])
                    #expect(ps.status == 0 && !String(decoding:ps.stdout,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines).hasPrefix("Z"))
                }
                task.cancel();gate.release.signal()
            }
            do{_ = try await task.value;Issue.record("Source crop fault admitted")}
            catch let e as Owner.OwnershipFailure{retained=true;if fault == 4 {liveRetained=true};#expect(e.reason == "group-1-joined-true");print("GENERATED_SOURCE_CROP_RETAINED fault=\(fault) reason=\(e.reason) root=\(root.path)")}
            catch{}
            state.assertJoined();joins += 1
            #expect(try Support.digest(input) == inputHash)
        }
        // Source-pass cancellation and SQLite limits are applied before decoder use.
        for cancelled in [true,false] {
            let stage=try spool(cancelled ? "source-cancel":"full"),state=Support.State(),gate=Support.Gate()
            let task=Task {
                defer{gate.signal.finish()}
                return try await CompanionDiskCheck.$testBoundary.withValue(.init(originalTrackRead:{_,_ in if cancelled{gate.hold()}})){
                    try await Owner.$testBoundary.withValue(.init(launched:{state.launch($0)})){
                        try await CompanionDiskCheck.associateOriginalCrops(source:original,in:stage,tool:tool,request:request,limits:.init(pages:8,records:1))
                    }
                }
            }
            if cancelled{for await _ in gate.stream{break};task.cancel();gate.release.signal()}
            do{_ = try await task.value;Issue.record("Source crop bound/cancel admitted")}catch{}
            #expect(state.pid == 0)
        }
        #expect(try Support.digest(original) == hash && Data(contentsOf:prior) == Data("prior".utf8))
        #expect(try Support.digest(exe) == exeHash)
        for n in Support.names{#expect(try Support.digest(runtime.appendingPathComponent("Frameworks/"+n)) == hashes[n])}
        print("GENERATED_SOURCE_CROPS accepted=22 helpers_joined=\(joins) retained=\(retained) live_cancel=\(liveRetained ? "retained-ownership":"ordinary")")
        cleanup = !retained
    }

}
