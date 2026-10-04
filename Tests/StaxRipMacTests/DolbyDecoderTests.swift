import Foundation
import Darwin
import CryptoKit
import Testing
@testable import StaxRipMac

@Suite(.serialized)
struct DolbyDecoderTests {
    typealias Owner = DolbyDecoderProcess
    private static let hash = String(repeating:"a",count:64)
    private static let names = ["libavcodec.63.dylib","libavformat.63.dylib","libavutil.61.dylib"]
    private static func digest(_ url: URL) throws -> String { DolbyInspection.hex(SHA256.hash(data:try Data(contentsOf:url))) }
    private static func wire(_ rows: [[String:Any]]) throws -> Data {
        try rows.reduce(into:Data()) { d,r in d.append(try JSONSerialization.data(withJSONObject:r,options:[.sortedKeys]));d.append(10) }
    }
    private static func rows() -> [[String:Any]] {
        let begin: [String:Any] = ["kind":"begin","version":1,"input_bytes":100000,"time_base":[1,1000],"configuration_bytes":23,"configuration_sha256":hash,"decoder":"hevc","codec_version":1,"format_version":1,"util_version":1,"automatic_codec_crop":false,"threads":4]
        func packet(_ i: Int) -> [String:Any] { ["kind":"packet","index":i,"pts":i*40,"block_input_byte_offset":20+i*100,"encoded_bytes":40,"sha256":hash] }
        func frame(_ i: Int) -> [String:Any] { ["kind":"frame","index":i,"packet_index":i,"packet_pts":i*40,"pts":i*40,"best_effort_pts":i*40,"block_input_byte_offset":20+i*100,"packet_size":40,"width":160,"height":96,"pixel_format":"yuv420p10le","interlaced":false,"codec_crop_left_right_top_bottom":[0,0,0,0],"sample_aspect_ratio":[1,1],"rpu_bytes":25,"rpu_sha256":hash] }
        return [begin,packet(0),frame(0),packet(1),frame(1),["kind":"complete","version":1,"packets":2,"frames":2,"decoder_drained":true,"descriptor_unchanged":true]]
    }
    private static func stream(observe: @escaping (Data) throws -> Void = { _ in }) throws -> DolbyDecoderStream {
        try .init(source:.init(sha256:hash,byteCount:100000),threads:4,versions:[1,1,1],observe:observe)
    }
    @Test func strictChunksSignedTimesAndExplicitPartialProof() throws {
        let bytes = try Self.wire(Self.rows()), parser = try Self.stream()
        for b in bytes { try parser.accept(Data([b])) }
        let receipt = try parser.finish(status:0)
        #expect(receipt.packets == 2 && receipt.frames == 2 && receipt.geometry.crop == [0,0,0,0])
        #expect(!receipt.independentSourceFrameAssociationVerified && !receipt.editedPictureSemanticsVerified)
        // Shape alone cannot detect a plausible duplicate/misbound packet claim.
        var plausible = Self.rows();plausible[4]["packet_index"]=0;plausible[4]["block_input_byte_offset"]=20
        let partial = try Self.stream();try partial.accept(Self.wire(plausible))
        #expect(!(try partial.finish(status:0)).independentSourceFrameAssociationVerified)
        var signed = Self.rows()
        for i in [1,2] { signed[i]["pts"] = Int64.min+1 }
        signed[2]["packet_pts"] = Int64.min+1;signed[2]["best_effort_pts"] = Int64.min+1
        for i in [3,4] { signed[i]["pts"] = Int64.max }
        signed[4]["packet_pts"] = Int64.max;signed[4]["best_effort_pts"] = Int64.max
        let extremes = try Self.stream();try extremes.accept(Self.wire(signed));#expect(try extremes.finish(status:0).frames == 2)
    }
    @Test func repairedProtocolForgeriesAndFramingRefuse() throws {
        let faults: [(Int,String,Any)] = [
            (0,"input_bytes",99999),(0,"threads",1),(0,"codec_version",2),(0,"automatic_codec_crop",true),
            (0,"configuration_sha256","bad"),(0,"time_base",[0,1000]),(0,"extra",1),
            (1,"index",1),(1,"pts",true),(1,"pts",Int64.min),(1,"block_input_byte_offset",100000),
            (1,"encoded_bytes",16777217),(1,"sha256","bad"),(3,"block_input_byte_offset",20),
            (2,"packet_index",1),(2,"pts",1),(2,"interlaced",true),(2,"width",8193),
            (2,"width",8192),(2,"pixel_format","yuv420p"),(2,"rpu_bytes",65537),
            (2,"codec_crop_left_right_top_bottom",[160,0,0,0]),(2,"sample_aspect_ratio",[0,1]),
            (4,"pts",0),(4,"packet_pts",0),(4,"width",162),(5,"frames",1),
            (5,"decoder_drained",false),(5,"descriptor_unchanged",false)]
        for (index,key,value) in faults {
            var rows=Self.rows();rows[index][key]=value;let p=try Self.stream()
            #expect(throws:(any Error).self) { try p.accept(Self.wire(rows));_ = try p.finish(status:0) }
        }
        let valid=try Self.wire(Self.rows())
        let invalid = [valid.dropLast(),valid+Data([32]),Data("{\"kind\":\"begin\",\"kind\":\"complete\"}\n".utf8),Data(repeating:32,count:65536),Data("{\"kind\":\"begin\",\"version\":1e0}\n".utf8),Data("{\"kind\":\"frame\",\"pts\":-0}\n".utf8),Data("[]\n".utf8),Data("\n".utf8),try Self.wire(Array(Self.rows().dropLast())),try Self.wire(Self.rows()+[Self.rows().last!])]
        for bytes in invalid { let p=try Self.stream();#expect(throws:(any Error).self) { try p.accept(Data(bytes));_ = try p.finish(status:0) } }
        let p=try Self.stream();try p.accept(valid);#expect(throws:(any Error).self) { try p.finish(status:7) }
    }
    private final class State: @unchecked Sendable {
        let lock=NSLock();private var child:pid_t=0,joined:pid_t=0
        func launch(_ p:pid_t) { lock.withLock { child=p } };func settle(_ p:pid_t) { lock.withLock { joined=p } }
        var pid:pid_t { lock.withLock { child } }
        func assertJoined() { let pair=lock.withLock { (child,joined) };#expect(pair.0 > 0 && pair.0 == pair.1);var s:Int32=0;#expect(waitpid(pair.0,&s,WNOHANG) == -1 && errno == ECHILD) }
    }
    private final class Gate: @unchecked Sendable {
        let stream:AsyncStream<Void>, signal:AsyncStream<Void>.Continuation,release=DispatchSemaphore(value:0)
        init() { let p=AsyncStream<Void>.makeStream();stream=p.stream;signal=p.continuation }
        func hold() { signal.yield(());signal.finish();if release.wait(timeout:.now()+10) != .success { Issue.record("Generated decoder gate expired") } }
    }
    private struct Fixture {
        let root,source,executable:URL
        var framework:URL { root.appendingPathComponent("Frameworks",isDirectory:true) }
        var tool:Owner.Tool { get throws { var hashes=[String:String]();for n in DolbyDecoderTests.names { hashes[n]=try DolbyDecoderTests.digest(framework.appendingPathComponent(n)) };return try .development(executable,expectedSHA256:DolbyDecoderTests.digest(executable),libraries:hashes,versions:[1,1,1]) } }
        
    }
    private func fixture(body:String) async throws -> Fixture {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("native-decoder-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false)
        let source=root.appendingPathComponent("generated.mkv"), exe=root.appendingPathComponent("Helpers/reference")
        try FileManager.default.createDirectory(at:exe.deletingLastPathComponent(),withIntermediateDirectories:false)
        let framework=root.appendingPathComponent("Frameworks");try FileManager.default.createDirectory(at:framework,withIntermediateDirectories:false)
        for n in Self.names { let p=framework.appendingPathComponent(n);try Data(n.utf8).write(to:p);try FileManager.default.setAttributes([.posixPermissions:0o644],ofItemAtPath:p.path) }
        try Data(repeating:0x5a,count:100000).write(to:source)
        let protocolFile=root.appendingPathComponent("rows");try Self.wire(Self.rows()).write(to:protocolFile)
        let c=root.appendingPathComponent("fixture.c")
        let read="FILE*f=fopen(\""+protocolFile.path+"\",\"r\");int c;while((c=fgetc(f))!=EOF)fputc(c,stdout);fclose(f);fflush(stdout);"
        try ("#include <stdio.h>\n#include <unistd.h>\nint main(int argc,char**argv){"+body.replacingOccurrences(of:"EMIT",with:read)+"return 0;}\n").write(to:c,atomically:false,encoding:.utf8)
        let r=try await ToolRunner().run(executable:URL(fileURLWithPath:"/usr/bin/xcrun"),arguments:["clang",c.path,"-o",exe.path]);try #require(r.status == 0)
        return .init(root:root,source:source,executable:exe)
    }
    @Test func nativeSurrogatesJoinEOFDeadlineErrorsAndPipeHolder() async throws {
        let cases=["EMIT","sleep(60);","close(1);close(2);sleep(60);","return 7;","puts(\"{}\");fflush(stdout);sleep(60);","for(int i=0;i<70000;i++)fputc('x',stderr);fflush(stderr);sleep(60);","for(int i=0;i<65536;i++)fputc(' ',stdout);fflush(stdout);sleep(60);","EMIT sleep(60);","EMIT return 7;","pid_t p=fork();if(p==0){sleep(60);_exit(0);}char path[4096];snprintf(path,sizeof(path),\"%s-holder\",argv[1]);FILE*f=fopen(path,\"w\");fprintf(f,\"%d\",p);fclose(f);return 0;"]
        for (i,body) in cases.enumerated() {
            let f=try await fixture(body:body),state=State(),tool=try f.tool;var cleanup=true
            defer { if cleanup { try? FileManager.default.removeItem(at:f.root) } }
            do {
                let r=try await Owner.$testBoundary.withValue(.init(launched:{state.launch($0)},settled:{state.settle($0)})) { try await Owner.run(tool:tool,source:f.source,timeout: i == 0 ? 10:0.25) }
                #expect(i == 0 && r.frames == 2 && !r.independentSourceFrameAssociationVerified)
            } catch let e as Owner.OwnershipFailure { cleanup=false;#expect(i != 0 && e.reason == "group-1-joined-true") }
            catch { #expect(i != 0) }
            state.assertJoined();#expect(try Data(contentsOf:f.source) == Data(repeating:0x5a,count:100000))
            if i == cases.count-1 {
                let text=try String(contentsOf:URL(fileURLWithPath:f.source.path+"-holder"),encoding:.utf8),pid=try #require(Int32(text))
                let ps=try await ToolRunner().run(executable:URL(fileURLWithPath:"/bin/ps"),arguments:["-p",String(pid),"-o","stat="])
                #expect(ps.status != 0 || String(decoding:ps.stdout,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines).hasPrefix("Z")) // No portable orphan wait/join claim.
            }
        }
    }
    @Test(arguments:["launch","frame","late","source","library","executable","source-path","library-path","executable-path"])
    func cancellationAndFinalMutationsRefuseAfterOwnedJoin(at:String) async throws {
        let f=try await fixture(body:"EMIT"),state=State(),gate=Gate(),tool=try f.tool;var cleanup=true
        defer { if cleanup { try? FileManager.default.removeItem(at:f.root) } }
        let cancel=["launch","frame","late"].contains(at)
        let task=Task {
            try await Owner.$testBoundary.withValue(.init(launched:{state.launch($0);if at == "launch" { gate.hold() }},row:{d in if at == "frame",String(decoding:d,as:UTF8.self).contains("\"index\":0"),String(decoding:d,as:UTF8.self).contains("\"kind\":\"frame\"") {gate.hold()}},settled:{state.settle($0)},beforeReceipt:{
                if at == "late" {gate.hold()} else if !cancel {
                    let p=at.hasPrefix("source") ? f.source:at.hasPrefix("library") ? f.framework.appendingPathComponent(Self.names[0]):f.executable
                    do {
                        if at.hasSuffix("-path") {let moved=f.root.appendingPathComponent("moved");try FileManager.default.moveItem(at:p,to:moved);try FileManager.default.copyItem(at:moved,to:p)}
                        else {let h=try FileHandle(forWritingTo:p);try h.write(contentsOf:Data([0]));try h.close()}
                    } catch {Issue.record("Generated decoder mutation failed")}
                }
            })) { try await Owner.run(tool:tool,source:f.source,timeout:10) }
        }
        if cancel {for await _ in gate.stream {break};task.cancel();gate.release.signal()}
        do {_ = try await task.value;Issue.record("Partial/late/mutated decoder result accepted")}
        catch let e as Owner.OwnershipFailure {cleanup=false;#expect(cancel && e.reason == "group-1-joined-true")}
        catch is CancellationError {#expect(cancel)}
        catch {#expect(!cancel)}
        state.assertJoined()
    }
    @Test func unsafeInputsWrongDigestAndPrecancelNeverLaunch() async throws {
        let f=try await fixture(body:"EMIT"),state=State(),tool=try f.tool;defer {try? FileManager.default.removeItem(at:f.root)}
        try await Owner.$testBoundary.withValue(.init(launched:{state.launch($0)})) {
            let link=f.root.appendingPathComponent("link");try FileManager.default.createSymbolicLink(at:link,withDestinationURL:f.source)
            await #expect(throws:(any Error).self) {try await Owner.run(tool:tool,source:link)}
            await #expect(throws:(any Error).self) {try await Owner.run(tool:tool,source:f.source,threads:2)}
            let original=try Self.digest(f.executable)
            let wrong=try Owner.Tool.development(f.executable,expectedSHA256:original,libraries:Dictionary(uniqueKeysWithValues:Self.names.map {($0,Self.hash)}),versions:[1,1,1])
            await #expect(throws:(any Error).self) {try await Owner.run(tool:wrong,source:f.source)}
            let p=AsyncStream<Void>.makeStream();let t=Task {for await _ in p.stream {break};return try await Owner.run(tool:tool,source:f.source)};t.cancel();p.continuation.finish()
            await #expect(throws:CancellationError.self) {try await t.value}
        };#expect(state.pid == 0)
    }
}

@Suite(.serialized)
struct FrozenNativeDolbyDecoderTests {
    private static var directory: String? { ProcessInfo.processInfo.environment["STAXRIP_TEST_FROZEN_DECODER_DIRECTORY"] }
    private static var repo:URL {URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()}
    private static func digest(_ p:URL) throws -> String { DolbyInspection.hex(SHA256.hash(data:try Data(contentsOf:p))) }
    private final class State: @unchecked Sendable {
        let lock=NSLock();private var child:pid_t=0,joined:pid_t=0
        func launch(_ p:pid_t){lock.withLock{child=p}};func settle(_ p:pid_t){lock.withLock{joined=p}}
        var pid:pid_t {lock.withLock{child}}
        func assertJoined(){let p=lock.withLock{(child,joined)};#expect(p.0 > 0 && p.0 == p.1);var s:Int32=0;#expect(waitpid(p.0,&s,WNOHANG) == -1 && errno == ECHILD)}
    }
    private final class Gate: @unchecked Sendable {
        let stream:AsyncStream<Void>,signal:AsyncStream<Void>.Continuation,release=DispatchSemaphore(value:0)
        private let lock=NSLock();private var held=false
        init(){let p=AsyncStream<Void>.makeStream();stream=p.stream;signal=p.continuation}
        func first(_ d:Data){guard String(decoding:d,as:UTF8.self).contains("\"kind\":\"frame\""),lock.withLock({if held{return false};held=true;return true}) else{return};signal.yield(());signal.finish();if release.wait(timeout:.now()+15) != .success{Issue.record("Generated actual decoder gate expired")}}
    }
    @Test(.enabled(if: directory != nil), .timeLimit(.minutes(2)))
    func actualFrozenCompatibleDecoderStreamsBothThreadsAndCancelsLiveChild() async throws {
        typealias Owner=DolbyDecoderProcess
        let runtime=URL(fileURLWithPath:try #require(Self.directory),isDirectory:true),exe=runtime.appendingPathComponent("Helpers/reference")
        let names=["libavcodec.63.dylib","libavformat.63.dylib","libavutil.61.dylib"]
        var libraryHashes=[String:String]();for n in names{libraryHashes[n]=try Self.digest(runtime.appendingPathComponent("Frameworks/"+n))}
        let initialExe=try Self.digest(exe)
        let tool=try Owner.Tool.development(exe,expectedSHA256:initialExe,libraries:libraryHashes,versions:[4129126,4129126,3998054])
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("native-frozen-decoder-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false);var cleanup=false, unsettled=false
        defer{if cleanup{try? FileManager.default.removeItem(at:root)}}
        let target=Self.repo.appendingPathComponent("Tools/DolbyMetadataAudit/target/native-decoder-fixtures")
        let fixture=try await ToolRunner().run(executable:URL(fileURLWithPath:"/usr/bin/env"),arguments:["STAXRIP_GENERATED_DOLBY_REFERENCE_DIRECTORY="+root.path,"cargo","test","--locked","--target-dir",target.path,"--manifest-path",Self.repo.appendingPathComponent("Tools/DolbyMetadataAudit/Cargo.toml").path,"actual_hevc_packets_and_rpu_association_match_independent_ffprobe"])
        try #require(fixture.status == 0)
        for name in ["single","group","wide-vint","conformance","whole-gop"] {
            let source=root.appendingPathComponent(name+".mkv"),original=try Self.digest(source)
            for threads in [1,4] {
                let state=State()
                do {
                    let receipt=try await Owner.$testBoundary.withValue(.init(launched:{state.launch($0)},settled:{state.settle($0)})) {try await Owner.run(tool:tool,source:source,threads:threads)}
                    #expect(receipt.packets == (name == "whole-gop" ? 24:4) && receipt.frames == receipt.packets)
                    #expect(receipt.source.sha256 == original && !receipt.independentSourceFrameAssociationVerified)
                    if name == "conformance" {#expect(receipt.geometry.width == 176 && receipt.geometry.height == 112 && receipt.geometry.crop == [0,14,0,14])}
                    else {#expect(receipt.geometry.width == 160 && receipt.geometry.height == 96)}
                } catch let error as CompanionUnsettledOwnership {cleanup=false;throw error}
                state.assertJoined();#expect(try Self.digest(source) == original)
            }
        }
        // Native source walker selects actual generated clusters; no owner media.
        let source=root.appendingPathComponent("single.mkv"),original=try Data(contentsOf:source)
        let view=CompanionDiskCheck.ReadView(sourceBytes:Int64(original.count),source:{o,n in original.subdata(in:Int(o)..<(Int(o)+n))},component:{_ in Data()},checkpoint:{})
        let walker=CompanionOriginalTrackCheck.Walker(view),header=try walker.element(0,end:view.sourceBytes),segment=try walker.element(header.end,end:view.sourceBytes)
        var prefix=Data(),clusters=Data(),offset=segment.payload
        while offset < segment.end {let e=try walker.element(offset,end:segment.end),bytes=original.subdata(in:Int(offset)..<Int(e.end));if e.id == 0x1f43b675{clusters.append(bytes)}else{prefix.append(bytes)};offset=e.end}
        try #require(!clusters.isEmpty)
        var repeated=original.prefix(Int(header.end))+Data([0x18,0x53,0x80,0x67,0xff])+prefix
        for _ in 0..<2000{repeated.append(clusters)}
        let longSource=root.appendingPathComponent("generated-cancellation.mkv");try repeated.write(to:longSource)
        let originalHash=try Self.digest(longSource),state=State(),gate=Gate()
        let task=Task {try await Owner.$testBoundary.withValue(.init(launched:{state.launch($0)},row:{gate.first($0)},settled:{state.settle($0)})){try await Owner.run(tool:tool,source:longSource)}}
        for await _ in gate.stream{break}
        let live=try await ToolRunner().run(executable:URL(fileURLWithPath:"/bin/ps"),arguments:["-p",String(state.pid),"-o","stat="])
        #expect(live.status == 0 && !String(decoding:live.stdout,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines).hasPrefix("Z"))
        task.cancel();gate.release.signal()
        do{_ = try await task.value;Issue.record("Cancelled actual decoder receipt admitted")}
        catch is CancellationError { print("Frozen development decoder: ten accepted generated cases; live child cancellation ordinary; direct child joined") }
        catch let e as Owner.OwnershipFailure{print("Frozen development decoder: cancellation has retained unresolved group ownership");unsettled=true;#expect(e.reason == "group-1-joined-true")}
        state.assertJoined();#expect(try Self.digest(longSource) == originalHash)
        #expect(try Self.digest(exe) == initialExe)
        for n in names{#expect(try Self.digest(runtime.appendingPathComponent("Frameworks/"+n)) == libraryHashes[n])}
        #expect(task.isCancelled)
        // An unsettled ownership branch intentionally keeps its generated files.
        cleanup = !unsettled
    }
}
