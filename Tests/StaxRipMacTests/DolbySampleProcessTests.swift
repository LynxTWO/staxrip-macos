import Foundation
import Darwin
import CryptoKit
import Testing
@testable import StaxRipMac

@Suite(.serialized)
struct DolbySampleProcessTests {
    typealias Owner = DolbyDecoderProcess
    static let hash = String(repeating:"a",count:64)
    static let names = ["libavcodec.63.dylib","libavformat.63.dylib","libavutil.61.dylib"]
    static func digest(_ url: URL) throws -> String { DolbyInspection.hex(SHA256.hash(data:try Data(contentsOf:url))) }
    static func wire(_ rows: [[String:Any]]) throws -> Data {
        try rows.reduce(into:Data()) { d,r in d.append(try JSONSerialization.data(withJSONObject:r,options:[.sortedKeys]));d.append(10) }
    }
    static func plane(_ w:Int,_ h:Int, value:Int=512) -> [String:Any] {
        ["width":w,"height":h,"samples":w*h,"minimum":value,"maximum":value,
         "sum":w*h*value,"sum_squares":w*h*value*value,"sha256":hash]
    }
    static func rows(width:Int=160,height:Int=96,crop:[Int]=[0,0,0,0]) -> [[String:Any]] {
        let begin:[String:Any] = ["kind":"sample-begin","version":1,"input_bytes":100000,"time_base":[1,1000],"configuration_bytes":23,"configuration_sha256":hash,"decoder":"hevc","codec_version":1,"format_version":1,"util_version":1,"automatic_codec_crop":false,"threads":4]
        func packet(_ i:Int)->[String:Any] { ["kind":"packet","index":i,"pts":i*40,"block_input_byte_offset":20+i*100,"encoded_bytes":40,"sha256":hash] }
        func frame(_ i:Int)->[String:Any] {
            let w=width-crop[0]-crop[1],h=height-crop[2]-crop[3]
            return ["kind":"sample-frame","index":i,"packet_index":i,"packet_pts":i*40,"pts":i*40,"best_effort_pts":i*40,"block_input_byte_offset":20+i*100,"packet_size":40,"width":width,"height":height,"pixel_format":"yuv420p10le","interlaced":false,"codec_crop_left_right_top_bottom":crop,"sample_aspect_ratio":[1,1],"rpu_bytes":25,"rpu_sha256":hash,
                "sample_encoding":"little-endian-uint16-code-values","color_range":1,"color_primaries":9,"color_transfer":16,"color_matrix":9,"chroma_location":1,"container_crop_applied":false,"edited_picture_semantics_verified":false,
                "coded":[plane(width,height),plane(width/2,height/2),plane(width/2,height/2)],
                "codec_visible":[plane(w,h),plane(w/2,h/2),plane(w/2,h/2)]]
        }
        return [begin,packet(0),frame(0),packet(1),frame(1),["kind":"sample-complete","version":1,"packets":2,"frames":2,"decoder_drained":true,"descriptor_unchanged":true]]
    }
    static func stream(observe: @escaping (DolbyDecoderStream.BaseSampleFrame) throws -> Void = { _ in }) throws -> DolbyDecoderStream {
        try .init(source:.init(sha256:hash,byteCount:100000),threads:4,versions:[1,1,1],profile:.baseSamples,observeSamples:observe)
    }
    @Test func explicitProfileTypedPlaneChunksAndMaximumMomentsStayPartial() throws {
        var observed=0
        let parser=try Self.stream { f in
            #expect(f.index == Int64(observed) && f.coded.count == 3 && f.codecVisible == f.coded)
            #expect(f.coded[0].sum == 160*96*512 && f.color.transfer == 16); observed += 1
        }
        for b in try Self.wire(Self.rows()) { try parser.accept(Data([b])) }
        let receipt=try parser.finish(status:0)
        #expect(observed == 2 && receipt.sampleFrameSummaryCount == 2 && receipt.sampleColorDeclarations?.primaries == 9)
        #expect(!receipt.independentSourceFrameAssociationVerified && !receipt.independentSampleSourceAssociationVerified && !receipt.editedPictureSemanticsVerified)
        for rows in [Self.rows(width:4096,height:4096), Self.rows(crop:[0,14,0,14])] {
            let p=try Self.stream();try p.accept(Self.wire(rows));#expect(try p.finish(status:0).sampleFrameSummaryCount == 2)
        }
        // Plausible changed producer hashes/statistics are shape claims, not pixel truth.
        var forged=Self.rows(crop:[0,14,0,14])
        var planes=try #require(forged[2]["codec_visible"] as? [[String:Any]])
        planes[0]["sha256"]=String(repeating:"b",count:64);forged[2]["codec_visible"]=planes
        let partial=try Self.stream();try partial.accept(Self.wire(forged));#expect(!(try partial.finish(status:0)).independentSampleSourceAssociationVerified)
        let bytes=try JSONSerialization.data(withJSONObject:Self.rows()[2])
        #expect(throws:(any Error).self){_ = try CompanionArchiveJSON.object(bytes,maximum:65535)}
        #expect(try CompanionArchiveJSON.object(bytes,maximum:65535,decoderSampleFields:true).count == 26)
    }
    @Test func repairedPlaneMomentsDimensionsTypesAndCropForgeriesRefuse() throws {
        let mutations:[(String,Any)] = [("width",159),("height",0),("samples",true),("samples",15359),
            ("minimum",513),("maximum",511),("maximum",1024),("sum",UInt64.max),("sum",7864321),
            ("sum_squares",UInt64.max),("sum_squares",4026531839),("sha256","bad"),("extra",1)]
        for (key,value) in mutations {
            var rows=Self.rows();var planes=try #require(rows[2]["coded"] as? [[String:Any]])
            planes[0][key]=value;rows[2]["coded"]=planes
            let p=try Self.stream();#expect(throws:(any Error).self){try p.accept(Self.wire(rows));_ = try p.finish(status:0)}
        }
        // Impossible second moment with broad extrema, while the usual bounds fit.
        var rows=Self.rows();var planes=try #require(rows[2]["coded"] as? [[String:Any]])
        planes[0]["minimum"]=0;planes[0]["maximum"]=1023;planes[0]["sum_squares"]=160*96*512*512-1
        rows[2]["coded"]=planes
        let p=try Self.stream();#expect(throws:(any Error).self){try p.accept(Self.wire(rows))}
        for (key,value) in [("coded",[] as Any),("codec_visible",[Self.plane(160,96)] as Any),
            ("sample_encoding","float" as Any),("container_crop_applied",true as Any),
            ("edited_picture_semantics_verified",true as Any),("color_range",3 as Any),
            ("color_transfer",256 as Any),("color_matrix",true as Any),("chroma_location",7 as Any),
            ("codec_crop_left_right_top_bottom",[0,1,0,0] as Any),("extra",1 as Any)] {
            var changed=Self.rows();changed[2][key]=value
            let q=try Self.stream();#expect(throws:(any Error).self){try q.accept(Self.wire(changed));_ = try q.finish(status:0)}
        }
        var changed=Self.rows();changed[4]["color_transfer"]=18
        let q=try Self.stream();#expect(throws:(any Error).self){try q.accept(Self.wire(changed))}
    }
    @Test func metadataSchemaDoesNotAdmitSamplesOrMixedFraming() throws {
        let samples=try Self.wire(Self.rows())
        let metadata=try DolbyDecoderStream(source:.init(sha256:Self.hash,byteCount:100000),threads:4,versions:[1,1,1])
        #expect(throws:(any Error).self){try metadata.accept(samples)}
        for (i,k) in [(0,"begin"),(2,"frame"),(5,"complete")] {
            var rows=Self.rows();rows[i]["kind"]=k
            let p=try Self.stream();#expect(throws:(any Error).self){try p.accept(Self.wire(rows));_ = try p.finish(status:0)}
        }
        for bytes in [samples.dropLast(),samples+Data([32]),Data("{\"kind\":\"sample-begin\",\"kind\":\"sample-complete\"}\n".utf8),Data(repeating:32,count:65536),try Self.wire(Array(Self.rows().dropLast())),try Self.wire(Self.rows()+[Self.rows().last!])] {
            let p=try Self.stream();#expect(throws:(any Error).self){try p.accept(Data(bytes));_ = try p.finish(status:0)}
        }
        let p=try Self.stream();try p.accept(samples);#expect(throws:(any Error).self){_ = try p.finish(status:7)}
        let throwing=try Self.stream{_ in throw CancellationError()}
        #expect(throws:CancellationError.self){try throwing.accept(samples)}
        #expect(throws:(any Error).self){_ = try throwing.finish(status:0)}
    }
    final class State: @unchecked Sendable {
        private let lock=NSLock();private var child:pid_t=0,joined:pid_t=0,frames=0
        private var initial:DolbyDecoderStream.BaseSampleFrame?
        func launch(_ p:pid_t){lock.withLock{child=p}};func settle(_ p:pid_t){lock.withLock{joined=p}}
        func sample(_ f:DolbyDecoderStream.BaseSampleFrame){lock.withLock{frames += 1;if initial == nil{initial=f}}}
        var pid:pid_t{lock.withLock{child}};var count:Int{lock.withLock{frames}}
        var first:DolbyDecoderStream.BaseSampleFrame?{lock.withLock{initial}}
        func assertJoined(){let p=lock.withLock{(child,joined)};#expect(p.0 > 0 && p.0 == p.1);guard p.0 > 0 && p.0 == p.1 else{return};var s:Int32=0;#expect(waitpid(p.0,&s,WNOHANG) == -1 && errno == ECHILD)}
    }
    final class Gate: @unchecked Sendable {
        let stream:AsyncStream<Void>,signal:AsyncStream<Void>.Continuation,release=DispatchSemaphore(value:0)
        private let lock=NSLock();private var held=false
        init(){let p=AsyncStream<Void>.makeStream();stream=p.stream;signal=p.continuation}
        func hold(){guard lock.withLock({if held{return false};held=true;return true}) else{return};signal.yield(());signal.finish();if release.wait(timeout:.now()+10) != .success{Issue.record("Generated sample gate expired")}}
    }
    struct Fixture {
        let root,source,executable:URL
        var framework:URL{root.appendingPathComponent("Frameworks")}
        var tool:Owner.Tool{get throws{try .developmentSamples(executable,expectedSHA256:DolbySampleProcessTests.digest(executable),libraries:Dictionary(uniqueKeysWithValues:try DolbySampleProcessTests.names.map{($0,try DolbySampleProcessTests.digest(framework.appendingPathComponent($0)))}),versions:[1,1,1])}}
    }
    private func fixture(_ body:String) async throws -> Fixture {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("native-sample-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false)
        let source=root.appendingPathComponent("generated.mkv"),exe=root.appendingPathComponent("Helpers/sample-probe")
        try FileManager.default.createDirectory(at:exe.deletingLastPathComponent(),withIntermediateDirectories:false)
        let framework=root.appendingPathComponent("Frameworks");try FileManager.default.createDirectory(at:framework,withIntermediateDirectories:false)
        for n in Self.names{let u=framework.appendingPathComponent(n);try Data(n.utf8).write(to:u);try FileManager.default.setAttributes([.posixPermissions:0o644],ofItemAtPath:u.path)}
        try Data(repeating:0x5a,count:100000).write(to:source)
        let rows=root.appendingPathComponent("rows");try Self.wire(Self.rows()).write(to:rows)
        let c=root.appendingPathComponent("fixture.c"),read="FILE*f=fopen(\""+rows.path+"\",\"r\");int c;while((c=fgetc(f))!=EOF)fputc(c,stdout);fclose(f);fflush(stdout);"
        try ("#include <stdio.h>\n#include <unistd.h>\nint main(){"+body.replacingOccurrences(of:"EMIT",with:read)+"return 0;}\n").write(to:c,atomically:false,encoding:.utf8)
        let compiled=try await ToolRunner().run(executable:URL(fileURLWithPath:"/usr/bin/xcrun"),arguments:["clang",c.path,"-o",exe.path]);try #require(compiled.status == 0)
        return .init(root:root,source:source,executable:exe)
    }
    @Test func actualNativeProfileRoleSurrogatesJoinAndRefuseIncompleteOutput() async throws {
        for (i,body) in ["EMIT","sleep(60);","close(1);close(2);sleep(60);","EMIT return 7;","puts(\"{}\");fflush(stdout);sleep(60);","EMIT sleep(60);"].enumerated() {
            let f=try await fixture(body),tool=try f.tool,state=State();var cleanup=true
            defer{if cleanup{try? FileManager.default.removeItem(at:f.root)}}
            do {
                let r=try await Owner.$testBoundary.withValue(.init(launched:{state.launch($0)},settled:{state.settle($0)})){
                    try await Owner.runSamples(tool:tool,source:f.source,timeout:i == 0 ? 10:0.5,observeSamples:{state.sample($0)})
                }
                #expect(i == 0 && r.sampleFrameSummaryCount == 2 && state.count == 2 && !r.independentSampleSourceAssociationVerified)
            } catch let e as Owner.OwnershipFailure {cleanup=false;#expect(i != 0 && e.reason == "group-1-joined-true")}
            catch{#expect(i != 0)}
            state.assertJoined();#expect(try Data(contentsOf:f.source) == Data(repeating:0x5a,count:100000))
        }
    }
    @Test func sampleRoleWrongEntrySymlinksBadDigestAndPrecancelNeverLaunch() async throws {
        let f=try await fixture("EMIT"),tool=try f.tool,state=State();defer{try? FileManager.default.removeItem(at:f.root)}
        try await Owner.$testBoundary.withValue(.init(launched:{state.launch($0)})){
            await #expect(throws:(any Error).self){try await Owner.run(tool:tool,source:f.source)}
            #expect(throws:(any Error).self){_ = try Owner.Tool.development(f.executable,expectedSHA256:Self.digest(f.executable),libraries:Dictionary(uniqueKeysWithValues:Self.names.map{($0,Self.hash)}),versions:[1,1,1])}
            let link=f.root.appendingPathComponent("source-alias");try FileManager.default.createSymbolicLink(at:link,withDestinationURL:f.source)
            await #expect(throws:(any Error).self){try await Owner.runSamples(tool:tool,source:link)}
            let wrong=try Owner.Tool.developmentSamples(f.executable,expectedSHA256:Self.hash,libraries:Dictionary(uniqueKeysWithValues:Self.names.map{($0,Self.hash)}),versions:[1,1,1])
            await #expect(throws:(any Error).self){try await Owner.runSamples(tool:wrong,source:f.source)}
            let p=AsyncStream<Void>.makeStream();let task=Task{for await _ in p.stream{break};return try await Owner.runSamples(tool:tool,source:f.source)};task.cancel();p.continuation.finish()
            await #expect(throws:CancellationError.self){try await task.value}
        };#expect(state.pid == 0)
    }
    @Test(arguments:["active","late","source","library","executable","source-path","library-path","executable-path","consumer"])
    func sampleCancellationConsumerAndFinalMutationsRefuseAfterNativeJoin(at:String) async throws {
        let f=try await fixture("EMIT"),state=State(),gate=Gate(),tool=try f.tool;var cleanup=true
        defer{if cleanup{try? FileManager.default.removeItem(at:f.root)}}
        let cancel=["active","late"].contains(at)
        let task=Task {
            defer{gate.signal.finish()}
            return try await Owner.$testBoundary.withValue(.init(launched:{state.launch($0)},settled:{state.settle($0)},beforeReceipt:{
                if at == "late"{gate.hold()}else if !cancel && at != "consumer"{
                    let path=at.hasPrefix("source") ? f.source:at.hasPrefix("library") ? f.framework.appendingPathComponent(Self.names[0]):f.executable
                    do{if at.hasSuffix("-path"){let moved=f.root.appendingPathComponent("moved");try FileManager.default.moveItem(at:path,to:moved);try FileManager.default.copyItem(at:moved,to:path)}else{let h=try FileHandle(forWritingTo:path);try h.write(contentsOf:Data([0]));try h.close()}}
                    catch{Issue.record("Generated sample final mutation failed")}
                }
            })) {
                try await Owner.runSamples(tool:tool,source:f.source,timeout:10,observeSamples:{frame in
                    state.sample(frame);if at == "active"{gate.hold()};if at == "consumer"{throw CancellationError()}
                })
            }
        }
        if cancel{for await _ in gate.stream{break};if at == "active"{#expect(state.count > 0)};task.cancel();gate.release.signal()}
        do{_ = try await task.value;Issue.record("Cancelled/mutated sample result admitted")}
        catch let e as Owner.OwnershipFailure{cleanup=false;#expect((cancel || at == "consumer") && e.reason == "group-1-joined-true")}
        catch is CancellationError{#expect(cancel || at == "consumer")}
        catch{#expect(!cancel && at != "consumer")}
        state.assertJoined()
    }
}

@Suite(.serialized)
struct CompatibleNativeDolbySampleTests {
    typealias Owner=DolbyDecoderProcess
    typealias Support=DolbySampleProcessTests
    private nonisolated static var directory:String?{ProcessInfo.processInfo.environment["STAXRIP_TEST_SAMPLE_DECODER_DIRECTORY"]}
    private static var repo:URL{URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()}
    @Test(.enabled(if:directory != nil), .timeLimit(.minutes(2)))
    func actualCompatibleSampleProcessBothThreadsLiveLateAndConsumerRefusal() async throws {
        let runtime=URL(fileURLWithPath:try #require(Self.directory),isDirectory:true)
        let exe=runtime.appendingPathComponent("Helpers/sample-probe")
        let hashes=Dictionary(uniqueKeysWithValues:try Support.names.map{($0,try Support.digest(runtime.appendingPathComponent("Frameworks/"+$0)))})
        let originalExe=try Support.digest(exe)
        let tool=try Owner.Tool.developmentSamples(exe,expectedSHA256:originalExe,libraries:hashes,versions:[4129126,4129126,3998054])
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("compatible-native-samples-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        var cleanup=false;defer{if cleanup{try? FileManager.default.removeItem(at:root)}}
        let target=Self.repo.appendingPathComponent("Tools/DolbyMetadataAudit/target/owned-NativeSampleDecoderTests")
        let generated=try await ToolRunner().run(executable:URL(fileURLWithPath:"/usr/bin/env"),arguments:["STAXRIP_GENERATED_DOLBY_REFERENCE_DIRECTORY="+root.path,"cargo","test","--locked","--target-dir",target.path,"--manifest-path",Self.repo.appendingPathComponent("Tools/DolbyMetadataAudit/Cargo.toml").path,"actual_hevc_packets_and_rpu_association_match_independent_ffprobe"])
        try #require(generated.status == 0)
        let prior=root.appendingPathComponent("prior-output");try Data("prior".utf8).write(to:prior)
        var joins=0
        for name in ["single","group","wide-vint","conformance","whole-gop"] {
            let source=root.appendingPathComponent(name+".mkv"),original=try Support.digest(source)
            var firstPlanes:[DolbyDecoderStream.PlaneSummary]?
            for threads in [1,4] {
                let state=Support.State()
                let r=try await Owner.$testBoundary.withValue(.init(launched:{state.launch($0)},settled:{state.settle($0)})){
                    try await Owner.runSamples(tool:tool,source:source,threads:threads,observeSamples:{state.sample($0)})
                }
                state.assertJoined();joins += 1
                #expect(r.sampleFrameSummaryCount == (name == "whole-gop" ? 24:4) && state.count == Int(r.sampleFrameSummaryCount))
                #expect(r.frames == r.packets && r.frames == r.sampleFrameSummaryCount && r.source.sha256 == original)
                #expect(!r.independentSampleSourceAssociationVerified && !r.independentSourceFrameAssociationVerified && !r.editedPictureSemanticsVerified)
                let first=try #require(state.first)
                if let firstPlanes{#expect(first.coded == firstPlanes)}else{firstPlanes=first.coded}
                #expect(first.coded.count == 3 && first.codecVisible.count == 3 && r.sampleColorDeclarations == first.color)
                if name == "conformance" {
                    #expect(r.geometry.width == 176 && r.geometry.height == 112 && r.geometry.crop == [0,14,0,14])
                    #expect(first.codecVisible[0].width == 162 && first.codecVisible[0].height == 98)
                    #expect(first.coded[0].sha256 != first.codecVisible[0].sha256)
                }else{#expect(first.coded == first.codecVisible)}
                #expect(try Support.digest(source) == original)
            }
        }
        // Callback mismatch aborts while the actual sample process is still owned.
        let source=root.appendingPathComponent("single.mkv"),original=try Support.digest(source)
        var unsettled=false
        let rejected=Support.State()
        do {
            _ = try await Owner.$testBoundary.withValue(.init(launched:{rejected.launch($0)},settled:{rejected.settle($0)})){
                try await Owner.runSamples(tool:tool,source:source,observeSamples:{_ in throw NativeExportError.invalid("Generated sample consumer refusal")})
            }
            Issue.record("Actual sample consumer refusal admitted")
        }catch let e as Owner.OwnershipFailure{unsettled=true;print("GENERATED_NATIVE_SAMPLE_RETAINED phase=consumer reason=\(e.reason) root=\(root.path)");#expect(e.reason == "group-1-joined-true")}
        catch is NativeExportError{}
        rejected.assertJoined();joins += 1
        // Late cancellation happens only after acknowledged actual native direct join.
        let late=Support.State(),lateGate=Support.Gate()
        let lateTask=Task {
            defer{lateGate.signal.finish()}
            return try await Owner.$testBoundary.withValue(.init(launched:{late.launch($0)},settled:{late.settle($0)},beforeReceipt:{lateGate.hold()})){
                try await Owner.runSamples(tool:tool,source:source)
            }
        }
        for await _ in lateGate.stream{break};late.assertJoined();lateTask.cancel();lateGate.release.signal()
        do{_ = try await lateTask.value;Issue.record("Late sample cancellation admitted")}
        catch is CancellationError{}
        late.assertJoined();joins += 1
        // Independent source walker constructs only generated unknown-size Segment input.
        let data=try Data(contentsOf:source)
        let view=CompanionDiskCheck.ReadView(sourceBytes:Int64(data.count),source:{o,n in data.subdata(in:Int(o)..<(Int(o)+n))},component:{_ in throw CancellationError()},checkpoint:{})
        let walker=CompanionOriginalTrackCheck.Walker(view),header=try walker.element(0,end:view.sourceBytes),segment=try walker.element(header.end,end:view.sourceBytes)
        var prefix=Data(),clusters=Data(),offset=segment.payload
        while offset < segment.end{let e=try walker.element(offset,end:segment.end),bytes=data.subdata(in:Int(offset)..<Int(e.end));if e.id == 0x1f43b675{clusters.append(bytes)}else{prefix.append(bytes)};offset=e.end}
        try #require(!clusters.isEmpty)
        var repeated=data.prefix(Int(header.end))+Data([0x18,0x53,0x80,0x67,0xff])+prefix
        for _ in 0..<2000{repeated.append(clusters)}
        let input=root.appendingPathComponent("generated-live.mkv");try repeated.write(to:input);let fingerprint=try Support.digest(input)
        let live=Support.State(),gate=Support.Gate()
        let task=Task {
            defer{gate.signal.finish()}
            return try await Owner.$testBoundary.withValue(.init(launched:{live.launch($0)},settled:{live.settle($0)})){
                try await Owner.runSamples(tool:tool,source:input,observeSamples:{frame in live.sample(frame);gate.hold()})
            }
        }
        for await _ in gate.stream{break};try #require(live.pid > 0 && live.count > 0)
        let ps=try await ToolRunner().run(executable:URL(fileURLWithPath:"/bin/ps"),arguments:["-p",String(live.pid),"-o","stat="])
        #expect(ps.status == 0 && !String(decoding:ps.stdout,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines).hasPrefix("Z"))
        task.cancel();gate.release.signal();var liveRetained=false
        do{_ = try await task.value;Issue.record("Actual live sample cancellation admitted")}
        catch is CancellationError{}
        catch let e as Owner.OwnershipFailure{unsettled=true;liveRetained=true;print("GENERATED_NATIVE_SAMPLE_RETAINED phase=live reason=\(e.reason) root=\(root.path)");#expect(e.reason == "group-1-joined-true")}
        live.assertJoined();joins += 1
        #expect(try Support.digest(input) == fingerprint && Support.digest(source) == original && Support.digest(exe) == originalExe)
        for n in Support.names{#expect(try Support.digest(runtime.appendingPathComponent("Frameworks/"+n)) == hashes[n])}
        #expect(try Data(contentsOf:prior) == Data("prior".utf8))
        print("GENERATED_NATIVE_SAMPLES accepted=10 helpers_joined=\(joins) live_cancel=\(liveRetained ? "retained-ownership" : "ordinary") retained_any=\(unsettled)")
        cleanup = !unsettled
    }
}
