import Foundation
import Darwin
import CryptoKit
import Testing
@testable import StaxRipMac

/// Actual close callbacks, never post-return FD-number probes. One fixture operation
/// owns each ledger; injected refusal follows real close and is not an OS fault claim.
final class DecoderCloseObservations: @unchecked Sendable {
    typealias Role = DolbyDecoderProcess.DescriptorRole
    private let lock=NSLock()
    private var counts:[Role:Int]=[:], child:pid_t=0, joined:pid_t=0
    let refused:Role?
    init(refused:Role?=nil){self.refused=refused}
    func launch(_ pid:pid_t){lock.withLock{child=pid}}
    func settle(_ pid:pid_t){lock.withLock{joined=pid}}
    func close(_ role:Role,_ fd:Int32,_ status:Int32){lock.withLock{
        #expect(fd >= 0 && status == 0)
        counts[role,default:0] += 1;#expect(counts[role] == 1)
        if child > 0 && [.source,.executable,.avcodec,.avformat,.avutil,.nullInput].contains(role){#expect(joined == child)}
    }}
    func inject(_ role:Role)->Bool{role == refused}
    func expect(_ roles:Set<Role>,launched:Bool){let facts=lock.withLock{(counts,child,joined)}
        #expect(Set(facts.0.keys) == roles && facts.0.values.allSatisfy{$0 == 1})
        if launched {
            #expect(facts.1 > 0 && facts.2 == facts.1)
            guard facts.1 > 0 && facts.2 == facts.1 else{return}
            var status:Int32=0;#expect(waitpid(facts.1,&status,WNOHANG) == -1 && errno == ECHILD)
        }else{#expect(facts.1 == 0 && facts.2 == 0)}
    }
    var pid:pid_t{lock.withLock{child}}
    var observations:(pid_t,pid_t){lock.withLock{(child,joined)}}
}

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
        var observations:(pid_t,pid_t) { lock.withLock { (child,joined) } }
        func assertJoined() {
            let pair=lock.withLock { (child,joined) }
            #expect(pair.0 > 0 && pair.0 == pair.1)
            // Refused pre-launch work owns no child. Keep the failed assertion,
            // but never waitpid(0), which can reap another fixture's child.
            guard pair.0 > 0, pair.0 == pair.1 else { return }
            var status:Int32=0
            #expect(waitpid(pair.0,&status,WNOHANG) == -1 && errno == ECHILD)
        }
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
    final class Diagnosis: @unchecked Sendable {
        private let lock = NSLock()
        private var stage = Owner.DiagnosticStage.notEntered, role: Owner.DescriptorRole?
        private var refusal: Owner.CheckRefusal?, spawn: Int32?
        private var closes: [(Owner.DescriptorRole, Int32)] = []
        func enter(_ stage: Owner.DiagnosticStage, _ role: Owner.DescriptorRole?) { lock.withLock { self.stage = stage; self.role = role } }
        func check(_ stage: Owner.DiagnosticStage, _ role: Owner.DescriptorRole?, _ refusal: Owner.CheckRefusal) { lock.withLock { self.stage = stage; self.role = role; self.refusal = refusal } }
        func spawned(_ status: Int32) { lock.withLock { spawn = status } }
        func closed(_ role: Owner.DescriptorRole, _ fd: Int32, _ status: Int32) { lock.withLock { #expect(fd >= 0); closes.append((role,status)) } }
        var snapshot:(stage:Owner.DiagnosticStage, role:Owner.DescriptorRole?, refusal:Owner.CheckRefusal?, spawn:Int32?, closes:[(Owner.DescriptorRole,Int32)]) { lock.withLock { (stage,role,refusal,spawn,closes) } }
        static func category(_ error: any Error) -> String {
            if error is CancellationError { return "cancelled" }
            if let error = error as? Owner.OwnershipFailure { return "ownership:" + error.reason }
            if error is NativeExportError { return "native-invalid" }
            return "other" // Never print arbitrary descriptions, paths or payloads.
        }
        func report(_ id: String, outcome: String, observations: (pid_t,pid_t)) {
            let s = snapshot, pair = observations
            let closeText = s.closes.map { $0.0.rawValue + ":" + String($0.1) }.joined(separator: ",")
            print("DECODER_CASE id=\(id) outcome=\(outcome) stage=\(s.stage.rawValue) role=\(s.role?.rawValue ?? "none") check=\(s.refusal?.rawValue ?? "none") spawn=\(s.spawn.map(String.init) ?? "none") launched=\(pair.0 > 0) settledEvent=\(pair.0 > 0 && pair.0 == pair.1) closes=\(closeText)")
        }
    }
    private func diagnosedBoundary(_ diagnosis: Diagnosis, _ state: State) -> Owner.Boundary {
        .init(launched: { state.launch($0) }, settled: { state.settle($0) },
              admission: { diagnosis.enter($0,$1) }, checkRefused: { diagnosis.check($0,$1,$2) },
              spawnStatus: { diagnosis.spawned($0) }, closed: { diagnosis.closed($0,$1,$2) })
    }
    private func caughtCategory(_ error: any Error) -> String { Diagnosis.category(error) }
    @Test func categoricalDiagnosticsDistinguishPrelaunchHashPinSpawnAndDeadlineRefusals() async throws {
        for fault in ["executable-hash", "library-hash", "library-missing", "spawn", "deadline"] {
            let f = try await fixture(body: "EMIT"), state = State(), diagnosis = Diagnosis()
            defer { try? FileManager.default.removeItem(at: f.root) }
            let sourceBefore = try Data(contentsOf: f.source)
            if fault == "spawn" { try Data(repeating: 0,count:128).write(to: f.executable); try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:f.executable.path) }
            var hashes = [String:String]()
            for name in Self.names { hashes[name] = try Self.digest(f.framework.appendingPathComponent(name)) }
            if fault == "library-hash" { hashes[Self.names[1]] = String(repeating:"0",count:64) }
            let executableHash = fault == "executable-hash" ? String(repeating:"0",count:64) : try Self.digest(f.executable)
            let tool = try Owner.Tool.development(f.executable,expectedSHA256:executableHash,libraries:hashes,versions:[1,1,1])
            if fault == "library-missing" { try FileManager.default.removeItem(at:f.framework.appendingPathComponent(Self.names[2])) }
            var outcome = "success"
            do { _ = try await Owner.$testBoundary.withValue(diagnosedBoundary(diagnosis,state)) { try await Owner.run(tool:tool,source:f.source,timeout:fault == "deadline" ? Double.leastNonzeroMagnitude : 10) }; Issue.record("Generated diagnostic refusal returned success") }
            catch { outcome = caughtCategory(error); #expect(error is NativeExportError) }
            diagnosis.report("qualification-" + fault,outcome:outcome,observations:state.observations)
            let observed = diagnosis.snapshot
            #expect(state.observations.0 == 0 && state.observations.1 == 0)
            #expect(observed.closes.allSatisfy { $0.1 == 0 })
            #expect(Set(observed.closes.map { $0.0 }).count == observed.closes.count)
            switch fault {
            case "executable-hash": #expect(observed.stage == .executableHash && observed.role == .executable && observed.closes.count == 2)
            case "library-hash": #expect(observed.stage == .libraryHash && observed.role == .avformat && observed.closes.count == 4)
            case "library-missing": #expect(observed.stage == .libraryPin && observed.role == .avutil && observed.closes.count == 4)
            case "spawn": #expect(observed.stage == .spawn && observed.spawn != nil && observed.spawn != 0 && observed.closes.count == 10)
            default: #expect(observed.stage == .options && observed.refusal == .deadline && observed.closes.isEmpty)
            }
            if fault != "deadline" { #expect(observed.refusal == nil) }
            #expect(try Data(contentsOf:f.source) == sourceBefore)
        }
    }
    @Test func nativeSurrogatesJoinEOFDeadlineErrorsAndPipeHolder() async throws {
        let cases=["EMIT","sleep(60);","close(1);close(2);sleep(60);","return 7;","puts(\"{}\");fflush(stdout);sleep(60);","for(int i=0;i<70000;i++)fputc('x',stderr);fflush(stderr);sleep(60);","for(int i=0;i<65536;i++)fputc(' ',stdout);fflush(stdout);sleep(60);","EMIT sleep(60);","EMIT return 7;","pid_t p=fork();if(p==0){sleep(60);_exit(0);}char path[4096];snprintf(path,sizeof(path),\"%s-holder\",argv[1]);FILE*f=fopen(path,\"w\");fprintf(f,\"%d\",p);fclose(f);return 0;"]
        let labels = ["valid","silence","EOF-live-child","nonzero","malformed","stderr-bound","stdout-line-bound","complete-live-child","complete-nonzero","pipe-holder"]
        for (i,body) in cases.enumerated() {
            let f=try await fixture(body:body),state=State(),tool=try f.tool;var cleanup=true
            let diagnosis = Diagnosis(); var outcome = "success"
            defer { if cleanup { try? FileManager.default.removeItem(at:f.root) } }
            do {
                let r=try await Owner.$testBoundary.withValue(diagnosedBoundary(diagnosis,state)) { try await Owner.run(tool:tool,source:f.source,timeout: i == 0 ? 10:0.25) }
                #expect(i == 0 && r.frames == 2 && !r.independentSourceFrameAssociationVerified)
            } catch let e as Owner.OwnershipFailure { outcome = caughtCategory(e); cleanup=false;#expect(i != 0 && e.reason == "group-1-joined-true") }
            catch { outcome = caughtCategory(error); #expect(i != 0) }
            diagnosis.report(String(i) + "-" + labels[i],outcome:outcome,observations:state.observations)
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
    @Test func actualMetadataClosesEveryFixedRoleOnceAndInjectedRefusalCannotReturnReceipt() async throws {
        let f=try await fixture(body:"EMIT"),tool=try f.tool
        // Every injected report follows actual successful close; no simulated OS
        // descriptor corruption or arbitrary FD/PID operation occurs.
        var retained=false;defer{if !retained{try? FileManager.default.removeItem(at:f.root)}}
        for role in [Owner.DescriptorRole?](arrayLiteral:nil)+Owner.DescriptorRole.allCases.map(Optional.some) {
            let ledger=DecoderCloseObservations(refused:role)
            do{
                let r=try await Owner.$testBoundary.withValue(.init(launched:{ledger.launch($0)},settled:{ledger.settle($0)},closed:{ledger.close($0,$1,$2)},refuseClose:{r,_,_ in ledger.inject(r)})){
                    try await Owner.run(tool:tool,source:f.source)
                }
                #expect(role == nil && r.frames == 2)
            }catch let e as Owner.OwnershipFailure{retained=true;#expect(role != nil && e.reason == "descriptor-close")}
            ledger.expect(Set(Owner.DescriptorRole.allCases),launched:true)
        }
        #expect(try Data(contentsOf:f.source) == Data(repeating:0x5a,count:100000))
        print("GENERATED_DECODER_CLOSE_METADATA normal=1 reported_refusals=10 actual_close_roles=10 no_retry=true retained=\(retained) root=\(f.root.path)")
    }
    @Test func actualConstructorAndPrelaunchClosesSupersedeOrdinaryRefusalWithoutLaunching() async throws {
        for kind in ["empty-source","bad-executable","bad-library","missing-source"] {
            let f=try await fixture(body:"EMIT"),tool=try f.tool;var retained=false
            defer{if !retained{try? FileManager.default.removeItem(at:f.root)}}
            switch kind {
            case "empty-source":try Data().write(to:f.source)
            case "bad-executable":try Data("invalid".utf8).write(to:f.executable)
            case "bad-library":try Data("changed".utf8).write(to:f.framework.appendingPathComponent(Self.names[0]))
            default:try FileManager.default.removeItem(at:f.source)
            }
            let ledger=DecoderCloseObservations(refused:.source)
            do{_ = try await Owner.$testBoundary.withValue(.init(launched:{ledger.launch($0)},settled:{ledger.settle($0)},closed:{ledger.close($0,$1,$2)},refuseClose:{r,_,_ in ledger.inject(r)})){
                try await Owner.run(tool:tool,source:f.source)
            };Issue.record("Prelaunch refusal returned receipt")}
            catch let e as Owner.OwnershipFailure{retained=true;#expect(kind != "missing-source" && e.reason == "descriptor-close")}
            catch is NativeExportError{#expect(kind == "missing-source")}
            let expected:Set<Owner.DescriptorRole>
            switch kind {case "empty-source":expected=[.source];case "bad-executable":expected=[.source,.executable];case "bad-library":expected=[.source,.executable,.avcodec];default:expected=[]}
            ledger.expect(expected,launched:false)
        }
    }
    @Test func abortClosesJoinBeforeReportedCloseFailureOverridesCancellationOrError() async throws {
        for kind in ["deadline","nonzero","malformed","active","late"] {
            let f=try await fixture(body:kind == "deadline" ? "sleep(60);":kind == "malformed" ? "puts(\"{}\");fflush(stdout);sleep(60);":kind == "nonzero" ? "EMIT return 7;":"EMIT"),tool=try f.tool
            let ledger=DecoderCloseObservations(refused:.stdoutWrite),gate=Gate();var retained=false
            defer{if !retained{try? FileManager.default.removeItem(at:f.root)}}
            let task=Task {
                defer{gate.signal.finish()}
                return try await Owner.$testBoundary.withValue(.init(launched:{ledger.launch($0);if kind == "active"{gate.hold()}},settled:{ledger.settle($0)},beforeReceipt:{if kind == "late"{gate.hold()}},closed:{ledger.close($0,$1,$2)},refuseClose:{r,_,_ in ledger.inject(r)})){
                    try await Owner.run(tool:tool,source:f.source,timeout:kind == "deadline" || kind == "malformed" ? 0.5:10)
                }
            }
            if kind == "active" || kind == "late"{for await _ in gate.stream{break};task.cancel();gate.release.signal()}
            do{_ = try await task.value;Issue.record("Reported abort close failure returned receipt")}
            catch let e as Owner.OwnershipFailure{retained=true;#expect(e.reason == "descriptor-close" || e.reason == "group-1-joined-true")}
            ledger.expect(Set(Owner.DescriptorRole.allCases),launched:true)
            #expect(try Data(contentsOf:f.source) == Data(repeating:0x5a,count:100000))
        }
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
        _ = try await RustFixtureBuild.generate(.reference, at: root, copiesIn: root)
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
    @Test(.enabled(if: directory != nil), .timeLimit(.minutes(2)))
    func actualSourceSpoolDecoderAssociationAndOwnedCancellation() async throws {
        typealias Check=CompanionDiskCheck
        let runtime=URL(fileURLWithPath:try #require(Self.directory),isDirectory:true),exe=runtime.appendingPathComponent("Helpers/reference")
        let names=["libavcodec.63.dylib","libavformat.63.dylib","libavutil.61.dylib"]
        var hashes=[String:String]();for n in names{hashes[n]=try Self.digest(runtime.appendingPathComponent("Frameworks/"+n))}
        let originalExe=try Self.digest(exe)
        let tool=try DolbyDecoderProcess.Tool.development(exe,expectedSHA256:originalExe,libraries:hashes,versions:[4129126,4129126,3998054])
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("native-source-frame-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        var cleanup=false;defer{if cleanup{try? FileManager.default.removeItem(at:root)}}
        _ = try await RustFixtureBuild.generate(.reference, at: root, copiesIn: root)
        let prior=root.appendingPathComponent("prior-output");try Data("prior".utf8).write(to:prior)
        var joins=0
        for name in ["single","group","wide-vint","conformance","whole-gop"] {
            let source=root.appendingPathComponent(name+".mkv"), original=try Self.digest(source)
            for threads in [1,4] {
                let stage=root.appendingPathComponent("spool-"+UUID().uuidString),state=State()
                try FileManager.default.createDirectory(at:stage,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
                let result=try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched:{state.launch($0)},settled:{state.settle($0)})) {
                    try await Check.associateOriginalFrames(source:source,in:stage,tool:tool,threads:threads)
                }
                #expect(result.independentSourceFrameAssociationVerified && !result.editedPictureSemanticsVerified)
                #expect(!result.source.independentSourceFrameAssociationVerified && !result.decoder.independentSourceFrameAssociationVerified)
                #expect(result.decoder.packets == (name == "whole-gop" ? 24:4) && result.source.packets.records == result.decoder.frames)
                #expect(result.source.sourceSHA256 == original && result.decoder.source.sha256 == original)
                #expect(result.source.track.configurationSHA256 == result.decoder.configurationSHA256)
                state.assertJoined();joins += 1
                #expect(try Self.digest(source) == original)
                if name == "conformance" {#expect(result.decoder.geometry.width == 176 && result.decoder.geometry.height == 112 && result.decoder.geometry.crop == [0,14,0,14])}
            }
        }
        // Actual decoder joins before these final source/spool refusals and
        // late cancellation. Previous/source fixture outputs remain caller-owned.
        for variant in 0..<4 {
            let input=root.appendingPathComponent("final-source-"+UUID().uuidString)
            try FileManager.default.copyItem(at:root.appendingPathComponent("single.mkv"),to:input)
            let initial=try Self.digest(input),stage=root.appendingPathComponent("final-spool-"+UUID().uuidString)
            try FileManager.default.createDirectory(at:stage,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
            let state=State(),gate=Gate()
            let task=Task {
                try await Check.$testBoundary.withValue(.init(beforeFinal:{
                    do {
                        switch variant {
                        case 0: let file=try FileHandle(forWritingTo:input);try file.write(contentsOf:Data([0]));try file.close()
                        case 1: try Data("prior".utf8).write(to:stage.appendingPathComponent("extra"))
                        case 2:
                            let moved=root.appendingPathComponent("retained-source-"+UUID().uuidString)
                            try FileManager.default.moveItem(at:input,to:moved);try FileManager.default.copyItem(at:moved,to:input)
                        default: break
                        }
                    } catch { Issue.record("Generated association final mutation failed") }
                })) {
                    try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched:{state.launch($0)},settled:{state.settle($0)},beforeReceipt:{
                        if variant == 3 {gate.first(Data("{\"kind\":\"frame\"}".utf8))}
                    })) { try await Check.associateOriginalFrames(source:input,in:stage,tool:tool) }
                }
            }
            if variant == 3 {for await _ in gate.stream{break};state.assertJoined();task.cancel();gate.release.signal()}
            do {_=try await task.value;Issue.record("Final mutated/cancelled association admitted")}
            catch is CancellationError {#expect(variant == 3)}
            catch let error as CompanionUnsettledOwnership {throw error}
            catch {#expect(variant != 3)}
            state.assertJoined();joins += 1
            if variant != 0 {#expect(try Self.digest(input) == initial)}
            if variant == 1 {#expect(try Data(contentsOf:stage.appendingPathComponent("extra")) == Data("prior".utf8))}
        }
        // Observe an actual live decoder after source facts are sealed. Keep the
        // original private fixture if group ownership cannot be settled.
        let source=root.appendingPathComponent("single.mkv"),data=try Data(contentsOf:source)
        let view=Check.ReadView(sourceBytes:Int64(data.count),source:{o,n in data.subdata(in:Int(o)..<(Int(o)+n))},component:{_ in Data()},checkpoint:{})
        let walker=CompanionOriginalTrackCheck.Walker(view),header=try walker.element(0,end:view.sourceBytes),segment=try walker.element(header.end,end:view.sourceBytes)
        var prefix=Data(),clusters=Data(),offset=segment.payload
        while offset < segment.end {let e=try walker.element(offset,end:segment.end);let bytes=data.subdata(in:Int(offset)..<Int(e.end));if e.id == 0x1f43b675{clusters.append(bytes)}else{prefix.append(bytes)};offset=e.end}
        var repeated=data.prefix(Int(header.end))+Data([0x18,0x53,0x80,0x67,0xff])+prefix
        for _ in 0..<2000{repeated.append(clusters)}
        let input=root.appendingPathComponent("generated-cancel.mkv"),stage=root.appendingPathComponent("cancel-spool")
        try repeated.write(to:input);let initial=try Self.digest(input)
        try FileManager.default.createDirectory(at:stage,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        let gate=Gate(),state=State()
        let task=Task {try await DolbyDecoderProcess.$testBoundary.withValue(.init(launched:{state.launch($0)},row:{gate.first($0)},settled:{state.settle($0)})) {
            try await Check.associateOriginalFrames(source:input,in:stage,tool:tool)
        }}
        for await _ in gate.stream{break}
        try #require(state.pid > 0)
        let live=try await ToolRunner().run(executable:URL(fileURLWithPath:"/bin/ps"),arguments:["-p",String(state.pid),"-o","stat="])
        #expect(live.status == 0 && !String(decoding:live.stdout,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines).hasPrefix("Z"))
        task.cancel();gate.release.signal();var unsettled=false
        do {_=try await task.value;Issue.record("Cancelled native association admitted")}
        catch is CancellationError {}
        catch let e as DolbyDecoderProcess.OwnershipFailure {unsettled=true;#expect(e.reason == "group-1-joined-true")}
        state.assertJoined();joins += 1
        #expect(try Self.digest(input) == initial && Self.digest(exe) == originalExe)
        for n in names {#expect(try Self.digest(runtime.appendingPathComponent("Frameworks/"+n)) == hashes[n])}
        #expect(try Data(contentsOf:prior) == Data("prior".utf8))
        print("GENERATED_NATIVE_ASSOCIATION accepted=10 helpers_joined=\(joins) cancellation=\(unsettled ? "retained-group" : "ordinary")")
        cleanup = !unsettled
    }

}
