import Foundation
import CryptoKit
import Darwin
import Testing
@testable import StaxRipMac

@Suite(.serialized)
struct CompanionMetadataProcessTests {
    typealias Reader = CompanionMetadataProcess
    typealias Transaction = OriginalCompanionTransaction
    private struct Fixture {
        let root, source, executable: URL
        var tool: Reader.Tool { get throws { try .development(executable, expectedSHA256: DolbyInspection.hex(SHA256.hash(data: Data(contentsOf: executable)))) } }
        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }
    private static var repo: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    private static func fixture() async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-companion-process-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        do {
            let generated = root.appendingPathComponent("generated")
            try FileManager.default.createDirectory(at: generated, withIntermediateDirectories: false)
            let helpers = try await RustFixtureBuild.generate(.original, at: generated, copiesIn: root)
            let executable = helpers.reader
            return .init(root:root,source:generated.appendingPathComponent("generated-source.mkv"),executable:executable)
        } catch { try? FileManager.default.removeItem(at: root); throw error }
    }

    private final class State: @unchecked Sendable {
        private let lock = NSLock(); private var child: pid_t = 0, joined: pid_t = 0, held = false
        func firstRow() -> Bool { lock.withLock { if held { return false };held=true;return true } }
        func launch(_ p: pid_t) { lock.withLock { child = p } }
        func settle(_ p: pid_t) { lock.withLock { joined = p } }
        var pid: pid_t { lock.withLock { child } }
        func assertJoined() {
            let pair = lock.withLock { (child,joined) }; #expect(pair.0 > 0 && pair.0 == pair.1)
            var status: Int32 = 0; #expect(waitpid(pair.0,&status,WNOHANG) == -1 && errno == ECHILD)
        }
    }
    private final class Gate: @unchecked Sendable {
        let entered: AsyncStream<Void>, signal: AsyncStream<Void>.Continuation
        let release = DispatchSemaphore(value:0)
        init() { let p = AsyncStream<Void>.makeStream(); entered=p.stream;signal=p.continuation }
        func hold() { signal.yield(());signal.finish();if release.wait(timeout:.now()+30) != .success { Issue.record("Generated metadata reader gate expired") } }
    }
    private final class Rows: @unchecked Sendable {
        private let lock = NSLock(); private var rows: [Data] = []
        func add(_ d: Data) { lock.withLock { rows.append(d) } }
        var data: Data { lock.withLock { rows.reduce(into:Data()) { $0.append($1);$0.append(10) } } }
    }
    private func captured(_ f: Fixture) async throws -> (CompanionMetadataStream.Receipt,Data) {
        let state = State(), rows = Rows(), tool = try f.tool
        let r = try await Reader.$testBoundary.withValue(.init(launched:{ state.launch($0) },settled:{ state.settle($0) })) {
            try await Reader.run(tool:tool,source:f.source,observe:{ rows.add($0) })
        }
        state.assertJoined(); return (r,rows.data)
    }
    @Test func actualReadOnlyHelperReturnsSettledSourceBoundCompactMetadata() async throws {
        let f = try await Self.fixture();defer { f.cleanup() }; let original = try Data(contentsOf:f.source)
        let (r,data) = try await captured(f)
        #expect(r.packets == 4 && r.records == 5 && r.enhancementNALs == 1 && !r.originalMetadataSemanticsVerified)
        #expect(r.source.byteCount == original.count && r.source.sha256 == DolbyInspection.hex(SHA256.hash(data:original)))
        #expect(r.peakTrackedHeap > 0 && r.peakTrackedHeap <= 67_108_864)
        let originalAudit = try String(contentsOf:f.root.appendingPathComponent("generated/metadata/source-audit.jsonl"),encoding:.utf8)
        let fresh = String(decoding:data,as:UTF8.self).split(separator:"\n").filter { !$0.contains("\"kind\":\"resources\"") }.joined(separator:"\n")+"\n"
        #expect(fresh == originalAudit) // Exact actual reader stdout vs generated producer fixture; not a package-admission bridge.
        #expect(try Data(contentsOf:f.source) == original)
    }
    @Test(arguments:["launch","begin","complete","late"])
    func actualCancellationSettlesOwnedChildAndRefusesPartialOrLateResult(at: String) async throws {
        let f = try await Self.fixture();defer { f.cleanup() };let original = try Data(contentsOf:f.source)
        let state=State(),gate=Gate(),tool=try f.tool
        let task = Task {
            try await Reader.$testBoundary.withValue(.init(launched:{ state.launch($0);if at == "launch" { gate.hold() } },row:{ d in
                let text=String(decoding:d,as:UTF8.self)
                if (at == "begin" && text.contains("\"kind\":\"begin\"")) || (at == "complete" && text.contains("\"kind\":\"complete\"")) { gate.hold() }
            },settled:{ state.settle($0) },beforeReceipt:{ if at == "late" { gate.hold() } })) {
                try await Reader.run(tool:tool,source:f.source)
            }
        }
        for await _ in gate.entered { break };task.cancel();gate.release.signal()
        do { _ = try await task.value;Issue.record("Cancelled native metadata result was admitted") }
        catch is CancellationError {}
        catch let e as Reader.OwnershipFailure {
            #expect(["launch","begin","complete"].contains(at) && e.reason == "group-1-joined-true") // Observed macOS EPERM after leader exit; retain stage, never admit success.
        }
        catch { Issue.record("Unexpected native metadata cancellation refusal") }
        state.assertJoined()
        #expect(try Data(contentsOf:f.source) == original)
    }
    @Test func wrongDigestUnsafeSourceAndPrecancelNeverLaunch() async throws {
        let f=try await Self.fixture();defer { f.cleanup() };let state=State(),tool=try f.tool
        try await Reader.$testBoundary.withValue(.init(launched:{ state.launch($0) })) {
            let wrong=try Reader.Tool.development(f.executable,expectedSHA256:String(repeating:"0",count:64))
            await #expect(throws:(any Error).self) { try await Reader.run(tool:wrong,source:f.source) }
            let link=f.root.appendingPathComponent("link");try FileManager.default.createSymbolicLink(at:link,withDestinationURL:f.source)
            await #expect(throws:(any Error).self) { try await Reader.run(tool:tool,source:link) }
            let p=AsyncStream<Void>.makeStream();let task=Task { for await _ in p.stream { break };return try await Reader.run(tool:tool,source:f.source) }
            task.cancel();p.continuation.finish();await #expect(throws:CancellationError.self) { try await task.value }
        }
        #expect(state.pid == 0)
    }
    @Test(arguments:["source-content","source-path","executable"])
    func finalObservationsRefuseSourceOrExecutableChangeAfterActualReaderExit(change: String) async throws {
        let f=try await Self.fixture();defer { f.cleanup() };let state=State(),tool=try f.tool
        await Reader.$testBoundary.withValue(.init(launched:{ state.launch($0) },settled:{ state.settle($0) },beforeReceipt:{
            do {
                if change == "source-content" { let h=try FileHandle(forWritingTo:f.source);try h.write(contentsOf:Data([0xfe]));try h.close() }
                else {
                    let target=change == "executable" ? f.executable:f.source,moved=f.root.appendingPathComponent("moved")
                    try FileManager.default.moveItem(at:target,to:moved);try FileManager.default.copyItem(at:moved,to:target)
                }
            } catch { Issue.record("Generated final metadata reader mutation failed") }
        })) {
            await #expect(throws:(any Error).self) { try await Reader.run(tool:tool,source:f.source) }
        }
        state.assertJoined()
    }
    @Test func cancellationDuringActualStreamingOfRepeatedGeneratedClustersJoinsLiveReader() async throws {
        let f=try await Self.fixture();defer { f.cleanup() }
        let original=try Data(contentsOf:f.source)
        let view=CompanionDiskCheck.ReadView(sourceBytes:Int64(original.count),source:{ o,n in original.subdata(in:Int(o)..<(Int(o)+n)) },component:{ _ in Data() },checkpoint:{})
        let walk=CompanionOriginalTrackCheck.Walker(view),header=try walk.element(0,end:view.sourceBytes),segment=try walk.element(header.end,end:view.sourceBytes)
        var prefix=Data(),clusters=Data(),offset=segment.payload
        while offset < segment.end {
            let e=try walk.element(offset,end:segment.end)
            let bytes=original.subdata(in:Int(offset)..<Int(e.end))
            if e.id == 0x1f43b675 { clusters.append(bytes) } else { prefix.append(bytes) };offset=e.end
        }
        try #require(!clusters.isEmpty)
        var source=original.prefix(Int(header.end))+Data([0x18,0x53,0x80,0x67,0xff])+prefix
        for _ in 0..<2000 { source.append(clusters) }
        try source.write(to:f.source)
        let state=State(),gate=Gate(),tool=try f.tool
        let task=Task {
            return try await Reader.$testBoundary.withValue(.init(launched:{ state.launch($0) },settled:{ state.settle($0) })) {
                try await Reader.run(tool:tool,source:f.source,observe:{ d in
                    if String(decoding:d,as:UTF8.self).contains("\"kind\":\"packet\"") && state.firstRow() { gate.hold() }
                })
            }
        }
        for await _ in gate.entered { break }
        let ps=try await ToolRunner().run(executable:URL(fileURLWithPath:"/bin/ps"),arguments:["-p",String(state.pid),"-o","stat="])
        #expect(ps.status == 0 && !String(decoding:ps.stdout,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines).hasPrefix("Z"))
        task.cancel();gate.release.signal()
        await #expect(throws:CancellationError.self) { try await task.value };state.assertJoined()
        #expect(try Data(contentsOf:f.source) == source)
    }
    private func element(_ id: UInt64, _ payload: Data) -> Data {
        var value = id, ids: [UInt8] = []
        repeat { ids.insert(UInt8(value & 255), at: 0); value >>= 8 } while value != 0
        var width = 1; while UInt64(payload.count) >= (UInt64(1) << (7 * width)) - 1 { width += 1 }
        let length = UInt64(payload.count) | UInt64(1) << (7 * width)
        return Data(ids + (0..<width).reversed().map { UInt8(truncatingIfNeeded: length >> (8 * $0)) }) + payload
    }
    private func unsigned(_ n: UInt64) -> Data {
        var n = n, b: [UInt8] = []; repeat { b.insert(UInt8(n & 255), at: 0); n >>= 8 } while n > 0; return Data(b)
    }
    @Test func actualReaderPreservesSignedExtremesUnsignedScaleAndDuration() async throws {
        let cases: [(UInt64, Int16, UInt64, Int64)] = [(0, -1, 1 << 63, Int64.min), (UInt64(Int64.max) + 10, -10, 1, Int64.max)]
        for (cluster, relative, scale, expected) in cases {
            let f = try await Self.fixture(); defer { f.cleanup() }
            let originalComponents = f.root.appendingPathComponent("generated/metadata")
            let videoFields: [Data] = [element(0xb0,unsigned(4096)), element(0xba,unsigned(2160)),
                element(0x54cc,unsigned(2)), element(0x54dd,unsigned(4)), element(0x54bb,unsigned(6)),
                element(0x54aa,unsigned(8)), element(0x54b0,unsigned(65536)), element(0x54ba,unsigned(2160)), element(0x54b2,unsigned(4))]
            let video = element(0xe0, videoFields.reduce(into:Data()) { $0.append($1) })
            let cfg = try Data(contentsOf: originalComponents.appendingPathComponent("hevc-configuration.bin"))
            try #require(Int(cfg[21] & 3) + 1 == 4)
            let track = element(0xd7,unsigned(1)) + element(0x83,unsigned(1)) + element(0x86,Data("V_MPEGH/ISO/HEVC".utf8)) + element(0x63a2,cfg) + video + element(0x23e383,unsigned(UInt64.max))
            let indexData = try Data(contentsOf: originalComponents.appendingPathComponent("rpu-index.jsonl"))
            let firstLine = try #require(String(decoding: indexData, as: UTF8.self).split(separator: "\n").first)
            let index = try #require(JSONSerialization.jsonObject(with: Data(firstLine.utf8)) as? [String: Any])
            let size = try #require(index["payload_bytes"] as? NSNumber).intValue
            let raw = try Data(contentsOf: originalComponents.appendingPathComponent("original-rpu.bin"))
            let payload = raw.subdata(in: 4..<(4 + size)), length = payload.count + 2
            let prefix = Data((0..<4).reversed().map { UInt8(truncatingIfNeeded: length >> (8 * $0)) })
            let nal = prefix + Data([0x7c,1]) + payload
            let ticks = UInt16(bitPattern: relative)
            let block = element(0xa3, Data([0x81,UInt8(ticks >> 8),UInt8(ticks & 255),0x80]) + nal)
            let header = element(0x1a45dfa3, element(0x4282, Data("matroska".utf8)))
            let info = element(0x1549a966, element(0x2ad7b1, unsigned(scale)))
            let source = header + Data([0x18,0x53,0x80,0x67,0xff]) + info + element(0x1654ae6b, element(0xae, track)) + element(0x1f43b675, element(0xe7, unsigned(cluster)) + block)
            try source.write(to: f.source)
            let (r,data) = try await captured(f)
            #expect(r.packets == 1 && r.records == 1)
            let observations = try String(decoding:data,as:UTF8.self).split(separator:"\n").map { try CompanionArchiveJSON.object(Data($0.utf8),maximum:65535,auditNullable:true) }
            let begin = try #require(observations.first)
            #expect(try CompanionArchiveJSON.unsigned(begin,"timestamp_scale_ns",1...UInt64.max) == scale)
            #expect(try CompanionArchiveJSON.unsigned(begin,"default_duration_ns",1...UInt64.max) == UInt64.max)
            let actual = try #require(observations.first { (try? CompanionArchiveJSON.string($0,"kind")) == "packet" })
            #expect(try CompanionArchiveJSON.signed(actual,"pts_ns") == expected)
            #expect(try Data(contentsOf: f.source) == source)
        }
    }
    @Test func strictFreshProtocolRejectsRepairedSchemaOrderCountsAndSourceClaims() async throws {
        let f=try await Self.fixture();defer { f.cleanup() };let (r,data)=try await captured(f)
        let original=try String(decoding:data,as:UTF8.self).split(separator:"\n").map { try #require(JSONSerialization.jsonObject(with:Data($0.utf8)) as? [String:Any]) }
        let packet=try #require(original.firstIndex { $0["kind"] as? String == "packet" }),rpu=try #require(original.firstIndex { $0["kind"] as? String == "rpu-summary" })
        let resources=try #require(original.firstIndex { $0["kind"] as? String == "resources" }),last=original.count-1
        for fault in ["extra-key","null-scale","bool-index","fraction","packet-limit","version","rpu-offset","rpu-size","rpu-ordinal","summary-type","heap-limit","heap-peak","source-bytes","source-hash","packet-sequence","peak-record","records","missing-resource","missing-complete","reorder","trailing","duplicate","partial","nonzero"] {
            var a=original
            switch fault {
            case "extra-key": a[0]["extra"]=0
            case "null-scale": a[0]["timestamp_scale_ns"]=NSNull()
            case "bool-index": a[packet]["index"]=true
            case "fraction": a[packet]["pts_ns"]=0.5
            case "packet-limit": a[0]["packet_limit"]=16777217
            case "version": a[0]["version"]=4
            case "rpu-offset": a[rpu]["input_byte_offset"]=0
            case "rpu-size": a[rpu]["encoded_bytes"]=24
            case "rpu-ordinal": a[rpu]["nal_index"]=16777217
            case "summary-type": a[rpu]["summary"]=false
            case "heap-limit": a[resources]["heap_limit"]=67108865
            case "heap-peak": a[resources]["peak_heap_bytes"]=0
            case "source-bytes": a[last]["input_bytes"]=r.source.byteCount+1
            case "source-hash": a[last]["input_sha256"]=String(repeating:"0",count:64)
            case "packet-sequence": a[last]["packet_sequence_sha256"]=String(repeating:"0",count:64)
            case "peak-record": a[last]["peak_record_bytes"]=r.peakRecordBytes+1
            case "records": a[last]["records"]=r.records+1
            case "missing-resource": a.remove(at:resources)
            case "missing-complete": a.removeLast()
            case "reorder": a.swapAt(packet,rpu)
            case "trailing": a.append(a[last])
            default: break
            }
            var bytes=Data()
            for row in a { bytes.append(try JSONSerialization.data(withJSONObject:row,options:[.sortedKeys]));bytes.append(10) }
            if fault == "partial" { bytes.removeLast() }
            if fault == "duplicate" { var text=String(decoding:bytes,as:UTF8.self);text.insert(contentsOf:"\"version\":3,",at:text.index(after:text.startIndex));bytes=Data(text.utf8) }
            let stream=try CompanionMetadataStream(source:r.source)
            #expect(throws:(any Error).self) { try stream.accept(bytes);_ = try stream.finish(status:fault == "nonzero" ? 7:0) }
        }
        let valid=try CompanionMetadataStream(source:r.source)
        for byte in data { try valid.accept(Data([byte])) }
        #expect(try valid.finish(status:0).records == 5)
        for fingerprint in [SourceFingerprint(sha256:r.source.sha256,byteCount:0),SourceFingerprint(sha256:"bad",byteCount:1)] {
            #expect(throws:(any Error).self) { try CompanionMetadataStream(source:fingerprint) }
        }
    }
    @Test func generatedNativeSurrogatesSettleDeadlinesEOFMalformedOverflowAndPipeHolder() async throws {
        let f=try await Self.fixture();defer { f.cleanup() }
        let (_,valid)=try await captured(f);let protocolPath=f.root.appendingPathComponent("protocol.jsonl");try valid.write(to:protocolPath)
        for behavior in ["sleep","earlyEOF","nonzero","malformed","stderr","holder","valid-live","valid-nonzero","oversized"] {
            try FileManager.default.removeItem(at:f.executable)
            let body: String
            switch behavior {
            case "sleep": body="sleep(60);"
            case "earlyEOF": body="close(1);close(2);sleep(60);"
            case "nonzero": body="return 7;"
            case "malformed": body="puts(\"{\\\"kind\\\":\\\"wrong\\\"}\");fflush(stdout);sleep(60);"
            case "stderr": body="for(int i=0;i<70000;i++)fputc('x',stderr);fflush(stderr);sleep(60);"
            case "oversized": body="for(int i=0;i<65536;i++)fputc(' ',stdout);fflush(stdout);sleep(60);"
            case "holder": body="pid_t p=fork();if(p==0){sleep(60);_exit(0);}char path[4096];snprintf(path,sizeof(path),\"%s-holder-pid\",argv[2]);FILE*f=fopen(path,\"w\");fprintf(f,\"%d\",p);fclose(f);return 0;"
            default: body="FILE*f=fopen(\""+protocolPath.path+"\",\"r\");int c;while((c=fgetc(f))!=EOF)fputc(c,stdout);fclose(f);fflush(stdout);"+(behavior == "valid-live" ? "sleep(60);":"return 7;")
            }
            let path=f.root.appendingPathComponent("fixture.c")
            try ("#include <stdio.h>\n#include <unistd.h>\nint main(int argc,char**argv){"+body+"return 0;}\n").write(to:path,atomically:false,encoding:.utf8)
            let build=try await ToolRunner().run(executable:URL(fileURLWithPath:"/usr/bin/xcrun"),arguments:["clang",path.path,"-o",f.executable.path]);try #require(build.status == 0)
            let state=State(),tool=try f.tool
            await Reader.$testBoundary.withValue(.init(launched:{ state.launch($0) },settled:{ state.settle($0) })) {
                await #expect(throws:(any Error).self) { try await Reader.run(tool:tool,source:f.source,timeout:0.25) }
            }
            state.assertJoined()
            if behavior == "holder" {
                let p=try String(contentsOf:URL(fileURLWithPath:f.source.path+"-holder-pid"),encoding:.utf8),pid=try #require(Int32(p))
                let ps=try await ToolRunner().run(executable:URL(fileURLWithPath:"/bin/ps"),arguments:["-p",String(pid),"-o","stat="])
                #expect(ps.status != 0 || String(decoding:ps.stdout,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines).hasPrefix("Z"))
            }
        }
    }
}
