import Foundation
import CryptoKit
import Testing
@testable import StaxRipMac

private enum DolbyFixture {
    static func probe() throws -> MediaProbe {
        try JSONDecoder().decode(MediaProbe.self, from: Data(#"{"streams":[{"index":0,"codec_type":"video","codec_name":"hevc","time_base":"1/1000"}],"format":{"format_name":"matroska,webm"}}"#.utf8))
    }
    static func rows() -> [[String: Any]] {
        let hash = String(repeating: "a", count: 64)
        var sequence = SHA256()
        var rows: [[String: Any]] = [["kind":"begin", "version":3, "input_type":"matroska-hevc-summary", "parser":"libdovi 3.3.2", "track_number":1,
            "declared_pixel_width":160, "declared_pixel_height":96, "declared_crop_left_right_top_bottom":[0,0,1,0],
            "declared_display_width_height":[16,9], "declared_display_unit":3, "timestamp_scale_ns":1_000_000,
            "configuration_sha256":hash, "configuration_bytes":23]]
        var ordinal = 0
        for (index, pts) in [20_000_000, -10_000_000, 40_000_000].enumerated() {
            sequence.update(data: DolbyInspection.proofRecord(pts: Int64(pts), bytes: 3, digest: try! DolbyInspection.hash(hash)))
            rows.append(["kind":"packet", "index":index, "pts_ns":pts, "encoded_bytes":3, "sha256":hash, "input_byte_offset":100 + index * 30])
            for nal in 0..<(index == 0 ? 0 : index) {
                rows.append(["kind":"rpu-summary", "index":ordinal, "packet_index":index, "nal_index":nal, "pts_ns":pts, "encoded_bytes":25, "sha256":hash,
                    "summary":["mapping_profile":7,"enhancement_type":"MEL", "scene_refresh":true,
                        "active_areas_left_right_top_bottom":[[1,3,5,7]], "cmv29_present":true, "cmv40_present":false]])
                ordinal += 1
            }
        }
        rows.append(["kind":"resources", "heap_limit":67_108_864, "peak_heap_bytes":1234])
        rows.append(["kind":"complete", "version":3, "packets":3, "records":3, "enhancement_nals":4, "input_bytes":1000,
            "input_sha256":hash, "packet_sequence_sha256":DolbyInspection.hex(sequence.finalize()), "peak_record_bytes":25, "source_recheck":true])
        return rows
    }
    static func data(_ rows: [[String: Any]]) throws -> Data {
        var bytes = Data()
        for row in rows { bytes.append(try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])); bytes.append(10) }
        return bytes
    }
    static func report() throws -> DolbySourceReport { let s = DolbyInspectionStream(); s.accept(try data(rows())); return try s.finish(status: 0) }
}

struct DolbyInspectionTests {
    @Test(arguments: [1, 7, 4096]) func chunkedProtocolRetainsRepeatedRecordsSignedOrderAndGeometry(chunk: Int) throws {
        let stream = DolbyInspectionStream(), bytes = try DolbyFixture.data(DolbyFixture.rows())
        for offset in stride(from: 0, to: bytes.count, by: chunk) { stream.accept(bytes.subdata(in: offset..<min(bytes.count, offset+chunk))) }
        let r = try stream.finish(status: 0)
        #expect(r.packets == 3 && r.records == 3 && r.packetsWithoutRPU == 1 && r.packetsWithMultipleRPUs == 1)
        #expect(r.sceneRefreshes == 3 && r.cmv29Records == 3 && r.cmv40Records == 0)
        #expect(r.activeAreas[try DolbyActiveArea([1,3,5,7])] == 3)
        #expect(r.header.declaredDisplayUnit == 3 && r.header.declaredDisplayWidthHeight == [16,9])
    }
    @Test func partialNonzeroTrailingAndOversizedStreamsCannotComplete() throws {
        let rows = DolbyFixture.rows(), data = try DolbyFixture.data(rows)
        for count in [0, 1, data.count-1] {
            let s = DolbyInspectionStream(); s.accept(data.prefix(count)); #expect(throws: (any Error).self) { try s.finish(status: 0) }
        }
        for bytes in [data, data + Data("{}\n".utf8), Data(repeating: 65, count: 65_537)] {
            let s = DolbyInspectionStream(); s.accept(bytes); #expect(throws: (any Error).self) { try s.finish(status: 1) }
        }
        let trailing = DolbyInspectionStream(); trailing.accept(data + Data("{}\n".utf8))
        #expect(throws: (any Error).self) { try trailing.finish(status: 0) }
    }
    @Test(arguments: ["version", "crop", "packet-order", "packet-size", "association", "active-area", "receipt-count", "digest", "source-recheck"])
    func malformedProtocolNeverProducesAReport(change: String) throws {
        var rows = DolbyFixture.rows()
        switch change {
        case "version": rows[0]["version"] = 2
        case "crop": rows[0]["declared_crop_left_right_top_bottom"] = [100,100,0,0]
        case "packet-order": rows[1]["index"] = 1
        case "packet-size": rows[1]["encoded_bytes"] = 16_777_217
        case "association": rows[3]["packet_index"] = 0
        case "active-area": var summary = rows[3]["summary"] as! [String:Any]; summary["active_areas_left_right_top_bottom"] = [[8192,0,0,0]]; rows[3]["summary"] = summary
        case "receipt-count": rows[rows.count-1]["records"] = 1
        case "digest": rows[rows.count-1]["packet_sequence_sha256"] = String(repeating: "0", count: 64)
        default: rows[rows.count-1]["source_recheck"] = false
        }
        let s = DolbyInspectionStream(); s.accept(try DolbyFixture.data(rows))
        #expect(throws: (any Error).self) { try s.finish(status: 0) }
    }
    @Test func independentProofRejectsOverflowAndDetectsReordering() throws {
        func packet(_ pts: Int64) throws -> VideoCopyPacket { try VideoCopyPacket(line: Data("pts=\(pts)|duration=1|size=3|data_hash=SHA256:\(String(repeating: "a", count: 64))".utf8)) }
        let a = DolbyPacketProof(tick: 1_000_000), b = DolbyPacketProof(tick: 1_000_000)
        for p in [20, -10, 40] { try a.accept(packet(Int64(p))) }
        for p in [-10, 20, 40] { try b.accept(packet(Int64(p))) }
        #expect(a.digest != b.digest)
        #expect(a.digest == (try DolbyFixture.report()).packetSequenceSHA256)
        #expect(throws: (any Error).self) { try a.accept(packet(Int64.max)) }
    }
    @Test(.timeLimit(.minutes(2))) func realHelperFFprobeAndContentRecheckOnGeneratedReorderedHEVC() async throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("dolby-native-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("generated.mkv")
        let generated = try await ToolRunner().run(executable: URL(fileURLWithPath: "/usr/bin/env"), arguments: [
            "STAXRIP_GENERATED_DOLBY_FIXTURE=" + source.path, "cargo", "test", "--locked", "--manifest-path", repo.appendingPathComponent("Tools/DolbyMetadataAudit/Cargo.toml").path,
            "--test", "matroska", "actual_hevc_packets_and_rpu_association_match_independent_ffprobe", "--", "--exact"])
        try #require(generated.status == 0, "Generated Rust fixture test failed")
        let helper = repo.appendingPathComponent("Tools/DolbyMetadataAudit/target/release/staxrip-dolby-metadata-audit")
        try #require(FileManager.default.isExecutableFile(atPath: helper.path), "Build the locked release helper before Swift integration tests")
        let tools = try #require(FFmpegTools.discover()), probe = try await MediaProbe.read(source, tools: tools)
        let bytes = try Data(contentsOf: source)
        let result = try await DolbyInspection.read(source: source, probe: probe, helper: helper, tools: tools)
        #expect(result.packets == 4 && result.records == 5 && result.packetsWithMultipleRPUs == 1)
        #expect(result.activeAreas.count == 4 && result.header.declaredDisplayUnit == 3)
        #expect(try Data(contentsOf: source) == bytes)
        await #expect(throws: (any Error).self) {
            try await DolbyInspection.read(source: source, probe: probe, helper: helper,
                tools: FFmpegTools(ffmpeg: tools.ffmpeg, ffprobe: URL(fileURLWithPath: "/usr/bin/false")))
        }
        await #expect(throws: (any Error).self) {
            try await DolbyInspection.read(source: source, probe: probe, helper: helper, tools: tools) { stage in
                if stage == "Rechecking source content…" {
                    var changed = bytes; changed[changed.count-1] ^= 1
                    do { try changed.write(to: source) } catch { Issue.record("Could not mutate generated source") }
                }
            }
        }
        try bytes.write(to: source)
        try bytes.dropLast().write(to: source)
        await #expect(throws: (any Error).self) { try await DolbyInspection.read(source: source, probe: probe, helper: helper, tools: tools) }
    }
}

@MainActor struct DolbyInspectionLifecycleTests {
    private actor HeldReader {
        var started: [URL] = []; var active = 0, maximum = 0
        var pending: [URL: CheckedContinuation<DolbySourceReport, Error>] = [:]
        var progress: [URL: @Sendable (String) -> Void] = [:]
        func read(_ url: URL, _ callback: @escaping @Sendable (String) -> Void) async throws -> DolbySourceReport {
            started.append(url); active += 1; maximum = max(active, maximum); progress[url] = callback
            defer { active -= 1 }
            return try await withCheckedThrowingContinuation { pending[url] = $0 }
        }
        func release(_ url: URL) throws { pending.removeValue(forKey: url)?.resume(returning: try DolbyFixture.report()) }
        func releaseAll() { for p in pending.values { p.resume(throwing: CancellationError()) }; pending = [:] }
        func late(_ url: URL) { progress[url]?("Late progress") }
    }
    private func wait(_ count: Int, _ reader: HeldReader) async throws {
        while await reader.started.count < count { try await Task.sleep(for: .milliseconds(1)) }
    }
    @Test(.timeLimit(.minutes(1))) func replacementJoinsOldReadAndRejectsOldReportAndProgress() async throws {
        let reader = HeldReader(), controller = DolbyInspectionController(reader: { u, _, p in try await reader.read(u,p) })
        let a = URL(fileURLWithPath: "/generated/a.mkv"), b = URL(fileURLWithPath: "/generated/b.mkv"), c = URL(fileURLWithPath: "/generated/c.mkv")
        var tasks: [Task<Void,Never>] = []
        do {
            tasks.append(controller.start(source: a, probe: try DolbyFixture.probe())); try await wait(1, reader)
            tasks.append(controller.start(source: b, probe: try DolbyFixture.probe()))
            tasks.append(controller.start(source: c, probe: try DolbyFixture.probe()))
            #expect(await reader.started == [a])
            try await reader.release(a); try await wait(2, reader)
            #expect(await reader.started == [a,c])
            #expect(await reader.maximum == 1)
            await reader.late(a); try await Task.sleep(for: .milliseconds(5))
            #expect(controller.stage != "Late progress" && controller.report == nil)
            try await reader.release(c); for task in tasks { await task.value }
            #expect(!controller.running && controller.report?.packets == 3)
            await reader.late(c); try await Task.sleep(for: .milliseconds(5))
            #expect(controller.stage != "Late progress")
        } catch { controller.cancel(); await reader.releaseAll(); for task in tasks { await task.value }; throw error }
    }
    @Test(.timeLimit(.minutes(1))) func cancelWaitsForSettlementAndDiscardsLateSuccess() async throws {
        let reader = HeldReader(), controller = DolbyInspectionController(reader: { u, _, p in try await reader.read(u,p) })
        let url = URL(fileURLWithPath: "/generated/cancel.mkv")
        let task = controller.start(source: url, probe: try DolbyFixture.probe())
        do {
            try await wait(1,reader); controller.cancel()
            await reader.late(url); try await Task.sleep(for: .milliseconds(5))
            #expect(controller.running && controller.stage == "Stopping inspection…" && controller.report == nil)
            try await reader.release(url); await task.value
            #expect(!controller.running && controller.report == nil && controller.error == nil && controller.stage == "Inspection cancelled.")
        } catch { controller.cancel(); await reader.releaseAll(); await task.value; throw error }
    }
    @Test(.timeLimit(.minutes(1))) func sheetResetRetainsQuitGuardUntilWorkerSettles() async throws {
        let reader = HeldReader(), controller = DolbyInspectionController(reader: { u, _, p in try await reader.read(u,p) })
        let delegate = AppDelegate(); delegate.dolby = controller
        let url = URL(fileURLWithPath: "/generated/closing.mkv")
        let task = controller.start(source: url, probe: try DolbyFixture.probe())
        var reset: Task<Void,Never>?
        do {
            try await wait(1,reader); #expect(delegate.hasActiveOperation)
            reset = controller.reset()
            #expect(controller.running && delegate.hasActiveOperation && controller.report == nil)
            try await reader.release(url); await reset?.value; await task.value
            #expect(!controller.running && !delegate.hasActiveOperation && controller.report == nil && controller.stage.isEmpty)
        } catch { controller.cancel(); await reader.releaseAll(); await reset?.value; await task.value; throw error }
    }

}
