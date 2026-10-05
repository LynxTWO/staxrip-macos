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

    @Test(.enabled(if:directory != nil), .timeLimit(.minutes(2)))
    func actualJointSourceVideoAndFixedCropGeometryRemainSeparateFacts() async throws {
        let runtime=URL(fileURLWithPath:try #require(Self.directory),isDirectory:true),exe=runtime.appendingPathComponent("Helpers/crop-probe")
        let exeHash=try Support.digest(exe),hashes=Dictionary(uniqueKeysWithValues:try Support.names.map{($0,try Support.digest(runtime.appendingPathComponent("Frameworks/"+$0)))})
        let tool=try Owner.Tool.developmentCrops(exe,expectedSHA256:exeHash,libraries:hashes,versions:[4129126,4129126,3998054])
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("native-video-crops-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        var cleanup=false,retained=false;defer{if cleanup{try? FileManager.default.removeItem(at:root)}}
        _ = try await RustFixtureBuild.generate(.reference,at:root,copiesIn:root)
        let prior=root.appendingPathComponent("prior");try Data("prior".utf8).write(to:prior)
        func spool(_ name:String)throws->URL{let u=root.appendingPathComponent(name);try FileManager.default.createDirectory(at:u,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);return u}
        var joins=0
        for name in ["single","group","wide-vint","conformance","whole-gop"] {
            let source=root.appendingPathComponent(name+".mkv"),hash=try Support.digest(source)
            for space in [Stream.CropRequest.Space.coded,.codecVisible] {for threads in [1,4] {
                let stage=try spool(name+space.rawValue+String(threads)),ledger=DecoderCloseObservations()
                let request=try Stream.CropRequest(space:space,x:2,y:2,width:16,height:10)
                let r=try await Owner.$testBoundary.withValue(.init(launched:{ledger.launch($0)},settled:{ledger.settle($0)},closed:{ledger.close($0,$1,$2)})){
                    try await CompanionDiskCheck.associateOriginalVideoCrops(source:source,in:stage,tool:tool,request:request,threads:threads)
                }
                ledger.expect(Set(Owner.DescriptorRole.allCases),launched:true);joins += 1
                #expect(r.originalVideoDeclarationsBoundToSource && r.independentSourceFrameAssociationVerified && r.originalSourceAndCallerCropAgreementVerified)
                #expect(!r.independentSourceROIProvenanceVerified && !r.independentSampleValuesVerified && !r.editedPictureSemanticsVerified && !r.decoder.independentSourceFrameAssociationVerified)
                #expect(r.source.sourceSHA256 == hash && r.decoder.source.sha256 == hash && r.source.track.configurationSHA256 == r.decoder.configurationSHA256)
                #expect(r.source.packets.packets == r.decoder.packets && r.source.packets.records == r.decoder.frames && r.decoder.cropFrameSummaryCount == r.decoder.frames)
                #expect(r.decoder.frames == (name == "whole-gop" ? 24:4) && r.decoder.cropRequest == request && r.decoder.geometry.sampleAspectRatio == nil)
                #expect(r.declarations.crop == [0,0,1,0] && r.declarations.unit == 3 && r.declarations.display == [16,9] && r.effectiveDisplayDeclarations == [16,9])
                #expect(r.declarations.presentFields == [0xb0,0xba,0x54bb,0x54b2,0x54b0,0x54ba])
                #expect(r.declaredPixelsEqualDecoderCodecVisiblePixels)
                #expect(r.declaredPixelsEqualDecoderCodedPixels == (name != "conformance"))
                if name == "conformance"{#expect(r.declarations.width == 162 && r.declarations.height == 98 && r.decoder.geometry.width == 176 && r.decoder.geometry.height == 112 && r.decoder.geometry.crop == [0,14,0,14])}
                #expect(try Support.digest(source) == hash)
            }}
        }
        // Actual geometry may differ from a plausible selected source declaration.
        // This entry reports both and never invents an origin or equality policy.
        let input=root.appendingPathComponent("changed-video.mkv"),original=root.appendingPathComponent("single.mkv")
        var data=try Data(contentsOf:original)
        let view=CompanionDiskCheck.ReadView(sourceBytes:Int64(data.count),source:{o,n in data.subdata(in:Int(o)..<(Int(o)+n))},component:{_ in throw CancellationError()},checkpoint:{})
        let track=try CompanionOriginalTrackCheck.readSource(view),walker=CompanionOriginalTrackCheck.Walker(view)
        var offset=track.originalPayloadOffset,changed=false
        while offset < track.originalPayloadOffset+Int64(track.payloadBytes) {
            let e=try walker.element(offset,end:track.originalPayloadOffset+Int64(track.payloadBytes))
            if e.id == 0xe0 {var field=e.payload;while field < e.end {let v=try walker.element(field,end:e.end);if v.id == 0xb0{let value=try walker.unsigned(v);try #require(v.end-v.payload == 8 && value == 160);data[Int(v.end)-1]=158;changed=true};field=v.end}}
            offset=e.end
        }
        try #require(changed);try data.write(to:input)
        let request=try DolbyCropProcessTests.request(.coded),state=Support.State()
        let changedResult=try await Owner.$testBoundary.withValue(.init(launched:{state.launch($0)},settled:{state.settle($0)})){
            try await CompanionDiskCheck.associateOriginalVideoCrops(source:input,in:spool("changed-video"),tool:tool,request:request)
        };state.assertJoined();joins += 1
        #expect(changedResult.declarations.width == 158 && changedResult.decoder.geometry.width == 160)
        #expect(!changedResult.declaredPixelsEqualDecoderCodedPixels && !changedResult.declaredPixelsEqualDecoderCodecVisiblePixels && !changedResult.independentSourceROIProvenanceVerified)
        #expect(changedResult.originalVideoDeclarationsBoundToSource && changedResult.originalSourceAndCallerCropAgreementVerified)
        #expect(try Data(contentsOf:input) == data)
        for fault in ["late","source-path","spool-extra","close","active"] {
            let input=root.appendingPathComponent("fault-"+fault+".mkv");try FileManager.default.copyItem(at:original,to:input)
            if fault == "active" {
                let bytes=try Data(contentsOf:input),v=CompanionDiskCheck.ReadView(sourceBytes:Int64(bytes.count),source:{o,n in bytes.subdata(in:Int(o)..<(Int(o)+n))},component:{_ in throw CancellationError()},checkpoint:{})
                let w=CompanionOriginalTrackCheck.Walker(v),h=try w.element(0,end:v.sourceBytes),segment=try w.element(h.end,end:v.sourceBytes)
                var prefix=Data(),clusters=Data(),o=segment.payload
                while o < segment.end{let e=try w.element(o,end:segment.end),b=bytes.subdata(in:Int(o)..<Int(e.end));if e.id == 0x1f43b675{clusters.append(b)}else{prefix.append(b)};o=e.end}
                try #require(!clusters.isEmpty);var repeated=bytes.prefix(Int(h.end))+Data([0x18,0x53,0x80,0x67,0xff])+prefix
                for _ in 0..<2000{repeated.append(clusters)};try repeated.write(to:input)
            }
            let hash=try Support.digest(input),stage=try spool(fault),state=Support.State(),gate=Support.Gate(),ledger=DecoderCloseObservations(refused:fault == "close" ? .source:nil)
            let task=Task {
                defer{gate.signal.finish()}
                return try await CompanionDiskCheck.$testBoundary.withValue(.init(beforeFinal:{
                    if fault == "source-path"{do{try FileManager.default.moveItem(at:input,to:root.appendingPathComponent("held"));try FileManager.default.copyItem(at:root.appendingPathComponent("held"),to:input)}catch{Issue.record("Generated joint source substitution failed")}}
                    if fault == "spool-extra"{do{try Data("extra".utf8).write(to:stage.appendingPathComponent("extra"))}catch{Issue.record("Generated joint spool mutation failed")}}
                })){
                    try await Owner.$testBoundary.withValue(.init(launched:{state.launch($0);ledger.launch($0)},row:{row in if fault == "active" && String(decoding:row,as:UTF8.self).contains("crop-frame"){gate.hold()}},settled:{state.settle($0);ledger.settle($0)},beforeReceipt:{if fault == "late"{gate.hold()}},closed:{ledger.close($0,$1,$2)},refuseClose:{r,_,_ in ledger.inject(r)})){
                        try await CompanionDiskCheck.associateOriginalVideoCrops(source:input,in:stage,tool:tool,request:request)
                    }
                }
            }
            if ["late","active"].contains(fault) {
                for await _ in gate.stream{break}
                if fault == "active"{try #require(state.pid > 0);let ps=try await ToolRunner().run(executable:URL(fileURLWithPath:"/bin/ps"),arguments:["-p",String(state.pid),"-o","stat="]);#expect(ps.status == 0 && !String(decoding:ps.stdout,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines).hasPrefix("Z"))}
                task.cancel();gate.release.signal()
            }
            do{_ = try await task.value;Issue.record("Joint source Video/crop refusal admitted")}
            catch let e as Owner.OwnershipFailure{retained=true;#expect(fault == "close" || fault == "active");if fault == "close"{#expect(e.reason == "descriptor-close")};print("GENERATED_VIDEO_CROP_RETAINED fault=\(fault) reason=\(e.reason) root=\(root.path)")}
            catch is CancellationError{#expect(fault == "late" || fault == "active")}
            catch{#expect(fault == "source-path" || fault == "spool-extra")}
            state.assertJoined();ledger.expect(Set(Owner.DescriptorRole.allCases),launched:true);joins += 1
            #expect(try Support.digest(input) == hash)
        }
        // Record limits/source cancellation still refuse before the helper owner.
        for cancel in [false,true] {
            let stage=try spool(cancel ? "source-cancel":"source-cap"),state=Support.State(),gate=Support.Gate()
            let t=Task {defer{gate.signal.finish()};return try await CompanionDiskCheck.$testBoundary.withValue(.init(originalTrackRead:{_,_ in if cancel{gate.hold()}})){
                try await Owner.$testBoundary.withValue(.init(launched:{state.launch($0)})){
                    try await CompanionDiskCheck.associateOriginalVideoCrops(source:original,in:stage,tool:tool,request:request,limits:.init(records:1))
                }
            }}
            if cancel{for await _ in gate.stream{break};t.cancel();gate.release.signal()}
            do{_ = try await t.value;Issue.record("Joint source bound/cancellation admitted")}catch{}
            #expect(state.pid == 0)
        }
        #expect(try Data(contentsOf:prior) == Data("prior".utf8) && Support.digest(exe) == exeHash)
        for n in Support.names{#expect(try Support.digest(runtime.appendingPathComponent("Frameworks/"+n)) == hashes[n])}
        print("GENERATED_VIDEO_CROPS accepted=21 helpers_joined=\(joins) retained=\(retained)")
        cleanup = !retained
    }

    @Test(.enabled(if:directory != nil), .timeLimit(.minutes(2)))
    func actualJointParameterVCLSourceAndFixedCropReadbackKeepsActivationFalse() async throws {
        let runtime=URL(fileURLWithPath:try #require(Self.directory),isDirectory:true),exe=runtime.appendingPathComponent("Helpers/crop-probe")
        let exeHash=try Support.digest(exe),hashes=Dictionary(uniqueKeysWithValues:try Support.names.map{($0,try Support.digest(runtime.appendingPathComponent("Frameworks/"+$0)))})
        let tool=try Owner.Tool.developmentCrops(exe,expectedSHA256:exeHash,libraries:hashes,versions:[4129126,4129126,3998054])
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("native-parameter-crops-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        var cleanup=false,retained=false;defer{if cleanup{try? FileManager.default.removeItem(at:root)}}
        _ = try await RustFixtureBuild.generate(.reference,at:root,copiesIn:root)
        let prior=root.appendingPathComponent("prior");try Data("prior".utf8).write(to:prior)
        func spool(_ name:String)throws->URL{let u=root.appendingPathComponent(name);try FileManager.default.createDirectory(at:u,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);return u}
        var joins=0
        for name in ["single","group","wide-vint","conformance","whole-gop"] {
            let source=root.appendingPathComponent(name+".mkv"),hash=try Support.digest(source)
            for space in [Stream.CropRequest.Space.coded,.codecVisible] {for threads in [1,4] {
                let stage=try spool(name+space.rawValue+String(threads)),ledger=DecoderCloseObservations()
                let request=try Stream.CropRequest(space:space,x:2,y:2,width:16,height:10)
                let r=try await Owner.$testBoundary.withValue(.init(launched:{ledger.launch($0)},settled:{ledger.settle($0)},closed:{ledger.close($0,$1,$2)})){
                    try await CompanionDiskCheck.associateOriginalParameterCrops(source:source,in:stage,tool:tool,request:request,threads:threads)
                }
                ledger.expect(Set(Owner.DescriptorRole.allCases),launched:true);joins += 1
                #expect(r.originalVideoDeclarationsBoundToSource && r.independentSourceFrameAssociationVerified && r.originalSourceAndCallerCropAgreementVerified)
                #expect(!r.independentSourceROIProvenanceVerified && !r.independentSampleValuesVerified && !r.editedPictureSemanticsVerified && !r.decoder.independentSourceFrameAssociationVerified)
                #expect(r.source.sourceSHA256 == hash && r.decoder.source.sha256 == hash && r.source.track.configurationSHA256 == r.decoder.configurationSHA256)
                #expect(r.source.packets.packets == r.decoder.packets && r.source.packets.records == r.decoder.frames && r.decoder.cropFrameSummaryCount == r.decoder.frames)
                #expect(r.decoder.frames == (name == "whole-gop" ? 24:4) && r.decoder.cropRequest == request && r.decoder.geometry.sampleAspectRatio == nil)
                #expect(r.declarations.crop == [0,0,1,0] && r.declarations.unit == 3 && r.declarations.display == [16,9] && r.effectiveDisplayDeclarations == [16,9])
                #expect(r.declarations.presentFields == [0xb0,0xba,0x54bb,0x54b2,0x54b0,0x54ba])
                #expect(r.originalFirstSlicePPSPrefixesBoundToSource && r.selectedPacketParameterSetNALsAbsent)
                #expect(r.vcl.prefixes == r.decoder.frames && r.vcl.peakPrefixBytes <= 2 && r.parameters.ppsID == 0)
                #expect(r.sourceSPSPrefixEqualsDecoderCodedGeometry && r.sourceSPSPrefixEqualsDecoderConformanceWindow)
                #expect(!r.activePictureParameterSetSelectionVerified && !r.completeSliceAndParameterConformanceVerified)
                #expect(!r.parameters.completeParameterSetConformanceVerified && !r.vcl.activePictureParameterSetSelectionVerified)
                #expect(r.parameters.geometry.configurationSHA256 == r.decoder.configurationSHA256)
                if name == "conformance"{#expect(r.declarations.width == 162 && r.declarations.height == 98 && r.decoder.geometry.width == 176 && r.decoder.geometry.height == 112 && r.decoder.geometry.crop == [0,14,0,14])}
                #expect(try Support.digest(source) == hash)
            }}
        }
        // Actual geometry may differ from a plausible selected source declaration.
        // This entry reports both and never invents an origin or equality policy.
        let input=root.appendingPathComponent("changed-video.mkv"),original=root.appendingPathComponent("single.mkv")
        var data=try Data(contentsOf:original)
        let view=CompanionDiskCheck.ReadView(sourceBytes:Int64(data.count),source:{o,n in data.subdata(in:Int(o)..<(Int(o)+n))},component:{_ in throw CancellationError()},checkpoint:{})
        let track=try CompanionOriginalTrackCheck.readSource(view),walker=CompanionOriginalTrackCheck.Walker(view)
        var offset=track.originalPayloadOffset,changed=false
        while offset < track.originalPayloadOffset+Int64(track.payloadBytes) {
            let e=try walker.element(offset,end:track.originalPayloadOffset+Int64(track.payloadBytes))
            if e.id == 0xe0 {var field=e.payload;while field < e.end {let v=try walker.element(field,end:e.end);if v.id == 0xb0{let value=try walker.unsigned(v);try #require(v.end-v.payload == 8 && value == 160);data[Int(v.end)-1]=158;changed=true};field=v.end}}
            offset=e.end
        }
        try #require(changed);try data.write(to:input)
        let request=try DolbyCropProcessTests.request(.coded),state=Support.State()
        let changedResult=try await Owner.$testBoundary.withValue(.init(launched:{state.launch($0)},settled:{state.settle($0)})){
            try await CompanionDiskCheck.associateOriginalParameterCrops(source:input,in:spool("changed-video"),tool:tool,request:request)
        };state.assertJoined();joins += 1
        #expect(changedResult.declarations.width == 158 && changedResult.decoder.geometry.width == 160)
        #expect(changedResult.sourceSPSPrefixEqualsDecoderCodedGeometry && changedResult.sourceSPSPrefixEqualsDecoderConformanceWindow)
        #expect(!changedResult.independentSourceROIProvenanceVerified && !changedResult.activePictureParameterSetSelectionVerified)
        #expect(changedResult.parameters.geometry.codedWidth == 160 && changedResult.vcl.prefixes == 4)
        #expect(changedResult.originalVideoDeclarationsBoundToSource && changedResult.originalSourceAndCallerCropAgreementVerified)
        #expect(try Data(contentsOf:input) == data)
        for fault in ["late","source-path","spool-extra","close","active"] {
            let input=root.appendingPathComponent("fault-"+fault+".mkv");try FileManager.default.copyItem(at:original,to:input)
            if fault == "active" {
                let bytes=try Data(contentsOf:input),v=CompanionDiskCheck.ReadView(sourceBytes:Int64(bytes.count),source:{o,n in bytes.subdata(in:Int(o)..<(Int(o)+n))},component:{_ in throw CancellationError()},checkpoint:{})
                let w=CompanionOriginalTrackCheck.Walker(v),h=try w.element(0,end:v.sourceBytes),segment=try w.element(h.end,end:v.sourceBytes)
                var prefix=Data(),clusters=Data(),o=segment.payload
                while o < segment.end{let e=try w.element(o,end:segment.end),b=bytes.subdata(in:Int(o)..<Int(e.end));if e.id == 0x1f43b675{clusters.append(b)}else{prefix.append(b)};o=e.end}
                try #require(!clusters.isEmpty);var repeated=bytes.prefix(Int(h.end))+Data([0x18,0x53,0x80,0x67,0xff])+prefix
                for _ in 0..<2000{repeated.append(clusters)};try repeated.write(to:input)
            }
            let hash=try Support.digest(input),stage=try spool(fault),state=Support.State(),gate=Support.Gate(),ledger=DecoderCloseObservations(refused:fault == "close" ? .source:nil)
            let task=Task {
                defer{gate.signal.finish()}
                return try await CompanionDiskCheck.$testBoundary.withValue(.init(beforeFinal:{
                    if fault == "source-path"{do{try FileManager.default.moveItem(at:input,to:root.appendingPathComponent("held"));try FileManager.default.copyItem(at:root.appendingPathComponent("held"),to:input)}catch{Issue.record("Generated joint source substitution failed")}}
                    if fault == "spool-extra"{do{try Data("extra".utf8).write(to:stage.appendingPathComponent("extra"))}catch{Issue.record("Generated joint spool mutation failed")}}
                })){
                    try await Owner.$testBoundary.withValue(.init(launched:{state.launch($0);ledger.launch($0)},row:{row in if fault == "active" && String(decoding:row,as:UTF8.self).contains("crop-frame"){gate.hold()}},settled:{state.settle($0);ledger.settle($0)},beforeReceipt:{if fault == "late"{gate.hold()}},closed:{ledger.close($0,$1,$2)},refuseClose:{r,_,_ in ledger.inject(r)})){
                        try await CompanionDiskCheck.associateOriginalParameterCrops(source:input,in:stage,tool:tool,request:request)
                    }
                }
            }
            if ["late","active"].contains(fault) {
                for await _ in gate.stream{break}
                if fault == "active"{try #require(state.pid > 0);let ps=try await ToolRunner().run(executable:URL(fileURLWithPath:"/bin/ps"),arguments:["-p",String(state.pid),"-o","stat="]);#expect(ps.status == 0 && !String(decoding:ps.stdout,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines).hasPrefix("Z"))}
                task.cancel();gate.release.signal()
            }
            do{_ = try await task.value;Issue.record("Joint source Video/crop refusal admitted")}
            catch let e as Owner.OwnershipFailure{retained=true;#expect(fault == "close" || fault == "active");if fault == "close"{#expect(e.reason == "descriptor-close")};print("GENERATED_PARAMETER_CROP_RETAINED fault=\(fault) reason=\(e.reason) root=\(root.path)")}
            catch is CancellationError{#expect(fault == "late" || fault == "active")}
            catch{#expect(fault == "source-path" || fault == "spool-extra")}
            state.assertJoined();ledger.expect(Set(Owner.DescriptorRole.allCases),launched:true);joins += 1
            #expect(try Support.digest(input) == hash)
        }
        // Record limits/source cancellation still refuse before the helper owner.
        for cancel in [false,true] {
            let stage=try spool(cancel ? "source-cancel":"source-cap"),state=Support.State(),gate=Support.Gate()
            let t=Task {defer{gate.signal.finish()};return try await CompanionDiskCheck.$testBoundary.withValue(.init(originalTrackRead:{_,_ in if cancel{gate.hold()}})){
                try await Owner.$testBoundary.withValue(.init(launched:{state.launch($0)})){
                    try await CompanionDiskCheck.associateOriginalParameterCrops(source:original,in:stage,tool:tool,request:request,limits:.init(records:1))
                }
            }}
            if cancel{for await _ in gate.stream{break};t.cancel();gate.release.signal()}
            do{_ = try await t.value;Issue.record("Joint source bound/cancellation admitted")}catch{}
            #expect(state.pid == 0)
        }
        #expect(try Data(contentsOf:prior) == Data("prior".utf8) && Support.digest(exe) == exeHash)
        for n in Support.names{#expect(try Support.digest(runtime.appendingPathComponent("Frameworks/"+n)) == hashes[n])}
        print("GENERATED_PARAMETER_CROPS accepted=21 helpers_joined=\(joins) retained=\(retained)")
        cleanup = !retained
    }

}
