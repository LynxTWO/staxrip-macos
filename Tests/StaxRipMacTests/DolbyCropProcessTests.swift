import Foundation
import Darwin
import Testing
@testable import StaxRipMac

@Suite(.serialized)
struct DolbyCropProcessTests {
    typealias Owner=DolbyDecoderProcess
    typealias Stream=DolbyDecoderStream
    typealias Support=DolbySampleProcessTests
    static func request(_ space:Stream.CropRequest.Space = .codecVisible) throws -> Stream.CropRequest {
        try .init(space:space,x:2,y:2,width:16,height:10)
    }
    static func rows() -> [[String:Any]] {
        var rows=Support.rows(crop:[2,2,2,2]);rows[0]["kind"]="crop-begin";rows[5]["kind"]="crop-complete"
        for i in [1,3]{rows[i]["kind"]="crop-packet"}
        for i in [2,4] {
            for k in ["best_effort_pts","sample_aspect_ratio","coded","codec_visible"] {rows[i].removeValue(forKey:k)}
            rows[i]["kind"]="crop-frame";rows[i]["request_space"]="codec-visible"
            rows[i]["requested_rect"]=[2,2,16,10];rows[i]["coded_rect"]=[4,4,16,10]
            rows[i]["source_roi_provenance_verified"]=false;rows[i]["independent_sample_values_verified"]=false
            rows[i]["roi"]=[Support.plane(16,10),Support.plane(8,5),Support.plane(8,5)]
        }
        return rows
    }
    static func parser(_ r:Stream.CropRequest? = nil, observe:@escaping (Stream.CropFrame)throws->Void = {_ in}) throws -> Stream {
        try .init(source:.init(sha256:Support.hash,byteCount:100000),threads:4,versions:[1,1,1],profile:.cropSamples,
                  cropRequest:r ?? request(),observeCrops:observe)
    }
    @Test func explicitCropRequestChunksTypedSummariesAndAbsencesStayPartial() throws {
        var n=0
        let p=try Self.parser{f in #expect(f.index == Int64(n) && f.codedRectangle == [4,4,16,10]);#expect(f.planes.count == 3 && f.planes[0].samples == 160);n += 1}
        for b in try Support.wire(Self.rows()){try p.accept(Data([b]))}
        let r=try p.finish(status:0)
        #expect(n == 2 && r.cropFrameSummaryCount == 2 && r.sampleFrameSummaryCount == 0)
        let expected=try Self.request();#expect(r.geometry.sampleAspectRatio == nil && r.cropRequest == expected)
        #expect(!r.independentSourceFrameAssociationVerified && !r.independentSampleSourceAssociationVerified && !r.independentSourceROIProvenanceVerified && !r.independentSampleValuesVerified && !r.editedPictureSemanticsVerified)
        // Plausible altered values/hash/source claims still pass shape; no truth upgrade.
        var forged=Self.rows();forged[1]["sha256"]=String(repeating:"b",count:64);forged[0]["configuration_sha256"]=String(repeating:"b",count:64);forged[4]["packet_index"]=0
        var planes=try #require(forged[2]["roi"] as? [[String:Any]]);planes[0]=Support.plane(16,10,value:513);forged[2]["roi"]=planes
        let q=try Self.parser();try q.accept(Support.wire(forged));#expect(!(try q.finish(status:0)).independentSampleValuesVerified)
        // Maximum qualified ROI exercises full-width moment products without pixels.
        let maximum=try Stream.CropRequest(space:.coded,x:0,y:0,width:4096,height:4096)
        var large=Self.rows()
        for i in [2,4]{large[i]["width"]=4096;large[i]["height"]=4096;large[i]["codec_crop_left_right_top_bottom"]=[0,0,0,0];large[i]["request_space"]="coded";large[i]["requested_rect"]=[0,0,4096,4096];large[i]["coded_rect"]=[0,0,4096,4096];large[i]["roi"]=[Support.plane(4096,4096,value:1023),Support.plane(2048,2048,value:1023),Support.plane(2048,2048,value:1023)]}
        let big=try Self.parser(maximum);try big.accept(Support.wire(large));#expect(try big.finish(status:0).cropFrameSummaryCount == 2)
        let data=try JSONSerialization.data(withJSONObject:Self.rows()[2]);#expect(throws:(any Error).self){_ = try CompanionArchiveJSON.object(data,maximum:65535)}
        #expect(try CompanionArchiveJSON.object(data,maximum:65535,decoderSampleFields:true).count == 28)
    }
    @Test func requestGeometryMomentTypesFlagsAndProfileForgeriesRefuse() throws {
        for r in [[-2,0,16,10],[1,0,16,10],[0,1,16,10],[0,0,15,10],[0,0,16,0],[Int.max,0,16,10]] {
            #expect(throws:(any Error).self){_ = try Stream.CropRequest(space:.coded,x:r[0],y:r[1],width:r[2],height:r[3])}
        }
        let mutations:[(String,Any)]=[("requested_rect",[0,0,16,10]),("coded_rect",[2,2,16,10]),("coded_rect",[4,4,8192,10]),("request_space","coded"),("request_space","container-visible"),("roi",[]),("pixel_format","yuv420p"),("interlaced",true),("codec_crop_left_right_top_bottom",[1,2,2,2]),("width",15),("height",4),("packet_pts",1),("packet_index",2),("rpu_bytes",0),("rpu_sha256","bad"),("source_roi_provenance_verified",true),("independent_sample_values_verified",true),("container_crop_applied",true),("edited_picture_semantics_verified",true),("sample_encoding","float"),("color_range",3),("color_transfer",true),("chroma_location",7),("sample_aspect_ratio",[1,1]),("best_effort_pts",0),("extra",1)]
        for (key,value) in mutations {
            var rows=Self.rows();rows[2][key]=value;let p=try Self.parser()
            #expect(throws:(any Error).self){try p.accept(Support.wire(rows));_ = try p.finish(status:0)}
        }
        for (key,value) in [("width",15 as Any),("samples",true as Any),("samples",159 as Any),("minimum",513 as Any),("maximum",1024 as Any),("sum",UInt64.max as Any),("sum_squares",UInt64.max as Any),("sha256","bad" as Any),("extra",1 as Any)] {
            var rows=Self.rows();var planes=try #require(rows[2]["roi"] as? [[String:Any]]);planes[0][key]=value;rows[2]["roi"]=planes
            let p=try Self.parser();#expect(throws:(any Error).self){try p.accept(Support.wire(rows))}
        }
        var drift=Self.rows();drift[4]["color_transfer"]=18;let p=try Self.parser();#expect(throws:(any Error).self){try p.accept(Support.wire(drift))}
        for profile in [Stream.Profile.metadata,.baseSamples] {
            let q=try Stream(source:.init(sha256:Support.hash,byteCount:100000),threads:4,versions:[1,1,1],profile:profile)
            #expect(throws:(any Error).self){try q.accept(Support.wire(Self.rows()))}
        }
        for i in 0..<6 {var mixed=Self.rows();mixed[i]["kind"]=Support.rows()[i]["kind"];let q=try Self.parser();#expect(throws:(any Error).self){try q.accept(Support.wire(mixed))}}
        for bad in [Data(),Data("{}\n".utf8),try Support.wire(Array(Self.rows().dropLast())),try Support.wire(Self.rows())+Data([10]),try Support.wire(Self.rows())+Data("{}\n".utf8),Data(repeating:32,count:65536)] {
            let q=try Self.parser();#expect(throws:(any Error).self){try q.accept(bad);_ = try q.finish(status:0)}
        }
        let q=try Self.parser();try q.accept(Support.wire(Self.rows()));#expect(throws:(any Error).self){_ = try q.finish(status:7)}
    }
    struct Fixture {
        let root,source,exe:URL
        var tool:Owner.Tool {get throws{try .developmentCrops(exe,expectedSHA256:Support.digest(exe),libraries:Dictionary(uniqueKeysWithValues:try Support.names.map{($0,try Support.digest(root.appendingPathComponent("Frameworks/"+$0)))}),versions:[1,1,1])}}
    }
    func fixture(_ body:String) async throws -> Fixture {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("native-crop-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false)
        let source=root.appendingPathComponent("generated.mkv"),exe=root.appendingPathComponent("Helpers/crop-probe")
        try FileManager.default.createDirectory(at:exe.deletingLastPathComponent(),withIntermediateDirectories:false)
        try FileManager.default.createDirectory(at:root.appendingPathComponent("Frameworks"),withIntermediateDirectories:false)
        for n in Support.names{try Data(n.utf8).write(to:root.appendingPathComponent("Frameworks/"+n))}
        try Data(repeating:0x5a,count:100000).write(to:source)
        let rows=root.appendingPathComponent("rows");try Support.wire(Self.rows()).write(to:rows)
        let c=root.appendingPathComponent("fixture.c"),emit="FILE*f=fopen(\""+rows.path+"\",\"r\");int c;while((c=fgetc(f))!=EOF)fputc(c,stdout);fclose(f);fflush(stdout);"
        let code="#include <stdio.h>\n#include <unistd.h>\n#include <string.h>\nint main(int argc,char**argv){if(argc!=9||strcmp(argv[4],\"--codec-visible-roi\")||strcmp(argv[5],\"2\")||strcmp(argv[6],\"2\")||strcmp(argv[7],\"16\")||strcmp(argv[8],\"10\"))return 9;"+body.replacingOccurrences(of:"EMIT",with:emit)+"return 0;}\n"
        try code.write(to:c,atomically:false,encoding:.utf8)
        let compiled=try await ToolRunner().run(executable:URL(fileURLWithPath:"/usr/bin/xcrun"),arguments:["clang",c.path,"-o",exe.path]);try #require(compiled.status == 0)
        return .init(root:root,source:source,exe:exe)
    }
    @Test func actualNativeCropRoleClosePriorityEOFDeadlineAndPrelaunchRefusal() async throws {
        let request=try Self.request()
        for (i,body) in ["EMIT","sleep(60);","EMIT return 7;","puts(\"{}\");fflush(stdout);","EMIT sleep(60);"].enumerated() {
            let f=try await fixture(body),tool=try f.tool,ledger=DecoderCloseObservations();var retained=false
            defer{if !retained{try? FileManager.default.removeItem(at:f.root)}}
            do{let r=try await Owner.$testBoundary.withValue(.init(launched:{ledger.launch($0)},settled:{ledger.settle($0)},closed:{ledger.close($0,$1,$2)})){
                try await Owner.runCrops(tool:tool,source:f.source,request:request,timeout:i == 0 ? 10:0.5)
            };#expect(i == 0 && r.cropFrameSummaryCount == 2)}
            catch let e as Owner.OwnershipFailure{retained=true;#expect(i != 0);print("GENERATED_CROP_RETAINED reason=\(e.reason) root=\(f.root.path)")}
            catch{#expect(i != 0)}
            ledger.expect(Set(Owner.DescriptorRole.allCases),launched:true)
        }
        let f=try await fixture("EMIT"),tool=try f.tool,state=Support.State();var retained=false
        defer{if !retained{try? FileManager.default.removeItem(at:f.root)}}
        for role in [Owner.DescriptorRole?](arrayLiteral:nil)+Owner.DescriptorRole.allCases.map(Optional.some) {
            let ledger=DecoderCloseObservations(refused:role)
            do{let r=try await Owner.$testBoundary.withValue(.init(launched:{ledger.launch($0)},settled:{ledger.settle($0)},closed:{ledger.close($0,$1,$2)},refuseClose:{r,_,_ in ledger.inject(r)})){
                try await Owner.runCrops(tool:tool,source:f.source,request:request)
            };#expect(role == nil && r.cropFrameSummaryCount == 2)}
            catch let e as Owner.OwnershipFailure{retained=true;#expect(role != nil && e.reason == "descriptor-close")}
            ledger.expect(Set(Owner.DescriptorRole.allCases),launched:true)
        }
        let bad=try Owner.Tool.developmentCrops(f.exe,expectedSHA256:String(repeating:"b",count:64),libraries:Dictionary(uniqueKeysWithValues:Support.names.map{($0,Support.hash)}),versions:[1,1,1])
        let rollback=DecoderCloseObservations()
        await Owner.$testBoundary.withValue(.init(launched:{rollback.launch($0)},closed:{rollback.close($0,$1,$2)})){
            await #expect(throws:(any Error).self){try await Owner.runCrops(tool:bad,source:f.source,request:request)}
        };rollback.expect([.source,.executable],launched:false)
        await Owner.$testBoundary.withValue(.init(launched:{state.launch($0)})){
            await #expect(throws:(any Error).self){try await Owner.run(tool:tool,source:f.source)}
            await #expect(throws:(any Error).self){try await Owner.runSamples(tool:tool,source:f.source)}
            let link=f.root.appendingPathComponent("alias");try! FileManager.default.createSymbolicLink(at:link,withDestinationURL:f.source)
            await #expect(throws:(any Error).self){try await Owner.runCrops(tool:tool,source:link,request:request)}
            let gate=Support.Gate();let t=Task{for await _ in gate.stream{break};return try await Owner.runCrops(tool:tool,source:f.source,request:request)};t.cancel();gate.signal.finish()
            await #expect(throws:CancellationError.self){try await t.value}
        };#expect(state.pid == 0)
        print("GENERATED_CROP_CLOSE_RETAINED root=\(f.root.path)")
    }
    @Test(arguments:["active","late","source-path","library","exe","library-path","exe-path","consumer"])
    func cropCancellationAndFinalMutationRefuseAfterJoin(at:String) async throws {
        let f=try await fixture("EMIT"),tool=try f.tool,state=Support.State(),gate=Support.Gate(),request=try Self.request();var retained=false
        defer{if !retained{try? FileManager.default.removeItem(at:f.root)}}
        let cancel=["active","late"].contains(at)
        let task=Task {
            defer{gate.signal.finish()}
            return try await Owner.$testBoundary.withValue(.init(launched:{state.launch($0)},settled:{state.settle($0)},beforeReceipt:{
                if at == "late"{gate.hold()}else if !cancel && at != "consumer" {
                    let path=at == "source-path" ? f.source : at.hasPrefix("library") ? f.root.appendingPathComponent("Frameworks/"+Support.names[0]):f.exe
                    do{if at.hasSuffix("-path"){try FileManager.default.moveItem(at:path,to:f.root.appendingPathComponent("held"));try FileManager.default.copyItem(at:f.root.appendingPathComponent("held"),to:path)}else{let h=try FileHandle(forWritingTo:path);try h.write(contentsOf:Data([0]));try h.close()}}catch{Issue.record("Generated crop mutation refused")}
                }
            })){
                try await Owner.runCrops(tool:tool,source:f.source,request:request,observeCrops:{_ in if at == "active"{gate.hold()};if at == "consumer"{throw CancellationError()}})
            }
        }
        if cancel{for await _ in gate.stream{break};task.cancel();gate.release.signal()}
        do{_ = try await task.value;Issue.record("Crop cancellation/mutation admitted")}
        catch let e as Owner.OwnershipFailure{retained=true;#expect(cancel || at == "consumer");print("GENERATED_CROP_RETAINED at=\(at) reason=\(e.reason) root=\(f.root.path)")}
        catch is CancellationError{#expect(cancel || at == "consumer")}
        catch{#expect(!cancel && at != "consumer")}
        state.assertJoined()
    }
}

@Suite(.serialized)
struct CompatibleNativeDolbyCropTests {
    typealias Owner=DolbyDecoderProcess
    typealias Stream=DolbyDecoderStream
    typealias Support=DolbySampleProcessTests
    private nonisolated static var directory:String?{ProcessInfo.processInfo.environment["STAXRIP_TEST_CROP_DECODER_DIRECTORY"]}
    final class State: @unchecked Sendable {
        let child=Support.State();private let lock=NSLock();private var count=0,initial:Stream.CropFrame?
        func crop(_ f:Stream.CropFrame){lock.withLock{count += 1;if initial == nil{initial=f}}}
        var first:Stream.CropFrame?{lock.withLock{initial}}
        var frames:Int{lock.withLock{count}}
    }
    @Test(.enabled(if:directory != nil), .timeLimit(.minutes(2)))
    func actualCompatibleCropProfilesBothSpacesThreadsAndOwnedFaults() async throws {
        let runtime=URL(fileURLWithPath:try #require(Self.directory),isDirectory:true),exe=runtime.appendingPathComponent("Helpers/crop-probe")
        let exeHash=try Support.digest(exe),hashes=Dictionary(uniqueKeysWithValues:try Support.names.map{($0,try Support.digest(runtime.appendingPathComponent("Frameworks/"+$0)))})
        let tool=try Owner.Tool.developmentCrops(exe,expectedSHA256:exeHash,libraries:hashes,versions:[4129126,4129126,3998054])
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("compatible-native-crops-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        var retained=false;defer{if !retained{try? FileManager.default.removeItem(at:root)}}
        _ = try await RustFixtureBuild.generate(.reference,at:root,copiesIn:root)
        let prior=root.appendingPathComponent("prior-output");try Data("prior".utf8).write(to:prior)
        var joins=0
        for name in ["single","group","wide-vint","conformance","whole-gop"] {
            let source=root.appendingPathComponent(name+".mkv"),hash=try Support.digest(source)
            for space in [Stream.CropRequest.Space.coded,.codecVisible] {
                let request=try Stream.CropRequest(space:space,x:2,y:2,width:16,height:10);var first:[Stream.PlaneSummary]?
                for threads in [1,4] {
                    let state=State(),ledger=DecoderCloseObservations()
                    let r=try await Owner.$testBoundary.withValue(.init(launched:{ledger.launch($0)},settled:{ledger.settle($0)},closed:{ledger.close($0,$1,$2)})){
                        try await Owner.runCrops(tool:tool,source:source,request:request,threads:threads,observeCrops:{state.crop($0)})
                    }
                    ledger.expect(Set(Owner.DescriptorRole.allCases),launched:true);joins += 1
                    #expect(r.frames == (name == "whole-gop" ? 24:4) && r.cropFrameSummaryCount == r.frames && state.frames == Int(r.frames))
                    #expect(r.source.sha256 == hash && r.cropRequest == request && r.geometry.sampleAspectRatio == nil && r.sampleFrameSummaryCount == 0)
                    #expect(!r.independentSourceFrameAssociationVerified && !r.independentSourceROIProvenanceVerified && !r.independentSampleValuesVerified && !r.editedPictureSemanticsVerified)
                    let frame=try #require(state.first);#expect(frame.codedRectangle == [2,2,16,10] && frame.planes.count == 3)
                    if let first{#expect(first == frame.planes)}else{first=frame.planes}
                    #expect(try Support.digest(source) == hash)
                }
            }
        }
        let source=root.appendingPathComponent("conformance.mkv"),hash=try Support.digest(source)
        var codedHash:String?,visibleHash:String?
        for space in [Stream.CropRequest.Space.coded,.codecVisible] {
            let request=try Stream.CropRequest(space:space,x:0,y:0,width:space == .coded ? 176:162,height:space == .coded ? 112:98)
            let ledger=DecoderCloseObservations(),state=State()
            let r=try await Owner.$testBoundary.withValue(.init(launched:{ledger.launch($0)},settled:{ledger.settle($0)},closed:{ledger.close($0,$1,$2)})){
                try await Owner.runCrops(tool:tool,source:source,request:request,observeCrops:{state.crop($0)})
            };ledger.expect(Set(Owner.DescriptorRole.allCases),launched:true);joins += 1
            #expect(r.geometry.crop == [0,14,0,14])
            let f=try #require(state.first);if space == .coded{codedHash=f.planes[0].sha256}else{visibleHash=f.planes[0].sha256}
        };#expect(codedHash != visibleHash)
        let request=try DolbyCropProcessTests.request(.coded)
        for role in [Owner.DescriptorRole.stdoutWrite,.nullInput,.source] {
            let ledger=DecoderCloseObservations(refused:role)
            do{_ = try await Owner.$testBoundary.withValue(.init(launched:{ledger.launch($0)},settled:{ledger.settle($0)},closed:{ledger.close($0,$1,$2)},refuseClose:{r,_,_ in ledger.inject(r)})){
                try await Owner.runCrops(tool:tool,source:source,request:request)
            };Issue.record("Actual crop close refusal admitted")}
            catch let e as Owner.OwnershipFailure{retained=true;#expect(e.reason == "descriptor-close")}
            ledger.expect(Set(Owner.DescriptorRole.allCases),launched:true);joins += 1
        }
        for fault in ["late","source-path","live","consumer"] {
            let input=root.appendingPathComponent("fault-"+fault+".mkv");try FileManager.default.copyItem(at:root.appendingPathComponent("single.mkv"),to:input)
            if fault == "live" {
                let data=try Data(contentsOf:input)
                let view=CompanionDiskCheck.ReadView(sourceBytes:Int64(data.count),source:{o,n in data.subdata(in:Int(o)..<(Int(o)+n))},component:{_ in throw CancellationError()},checkpoint:{})
                let walker=CompanionOriginalTrackCheck.Walker(view),header=try walker.element(0,end:view.sourceBytes),segment=try walker.element(header.end,end:view.sourceBytes)
                var prefix=Data(),clusters=Data(),offset=segment.payload
                while offset < segment.end{let e=try walker.element(offset,end:segment.end);let bytes=data.subdata(in:Int(offset)..<Int(e.end));if e.id == 0x1f43b675{clusters.append(bytes)}else{prefix.append(bytes)};offset=e.end}
                try #require(!clusters.isEmpty);var repeated=data.prefix(Int(header.end))+Data([0x18,0x53,0x80,0x67,0xff])+prefix
                for _ in 0..<2000{repeated.append(clusters)};try repeated.write(to:input)
            }
            let original=try Support.digest(input),state=Support.State(),gate=Support.Gate()
            let task=Task {
                defer{gate.signal.finish()}
                return try await Owner.$testBoundary.withValue(.init(launched:{state.launch($0)},settled:{state.settle($0)},beforeReceipt:{
                    if fault == "late"{gate.hold()}
                    if fault == "source-path"{do{try FileManager.default.moveItem(at:input,to:root.appendingPathComponent("held"));try FileManager.default.copyItem(at:root.appendingPathComponent("held"),to:input)}catch{Issue.record("Generated crop final substitution refused")}}
                })){
                    try await Owner.runCrops(tool:tool,source:input,request:request,observeCrops:{_ in
                        if fault == "live"{gate.hold()};if fault == "consumer"{throw CancellationError()}
                    })
                }
            }
            if ["late","live"].contains(fault) {
                for await _ in gate.stream{break}
                if fault == "live" {
                    try #require(state.pid > 0)
                    let ps=try await ToolRunner().run(executable:URL(fileURLWithPath:"/bin/ps"),arguments:["-p",String(state.pid),"-o","stat="])
                    #expect(ps.status == 0 && !String(decoding:ps.stdout,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines).hasPrefix("Z"))
                }
                task.cancel();gate.release.signal()
            }
            do{_ = try await task.value;Issue.record("Actual crop fault admitted")}
            catch let e as Owner.OwnershipFailure{retained=true;print("GENERATED_ACTUAL_CROP_RETAINED at=\(fault) reason=\(e.reason) root=\(root.path)")}
            catch is CancellationError{#expect(fault != "source-path")}
            catch{#expect(fault == "source-path")}
            state.assertJoined();joins += 1;#expect(try Support.digest(input) == original)
        }
        #expect(try Support.digest(source) == hash)
        #expect(try Support.digest(exe) == exeHash)
        for n in Support.names{#expect(try Support.digest(runtime.appendingPathComponent("Frameworks/"+n)) == hashes[n])}
        #expect(try Data(contentsOf:prior) == Data("prior".utf8))
        print("GENERATED_ACTUAL_CROPS accepted=22 helpers_joined=\(joins) retained=\(retained) root=\(root.path)")
    }
}
