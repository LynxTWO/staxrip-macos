import Foundation
import Darwin
import Testing
@testable import StaxRipMac

@MainActor
struct HDR10Tests {
    private func stream(_ overrides: [String: Any] = [:]) throws -> MediaProbe.Stream {
        var data: [String: Any] = ["index": 0, "codec_type": "video", "codec_name": "hevc", "profile": "Main 10", "width": 160, "height": 90,
            "pix_fmt": "yuv420p10le", "color_range": "tv", "color_space": "bt2020nc", "color_primaries": "bt2020", "color_transfer": "smpte2084", "chroma_location": "left", "sample_aspect_ratio": "1:1", "field_order": "progressive", "start_pts": 0, "avg_frame_rate": "24000/1001", "r_frame_rate": "24000/1001", "time_base": "1/1000"]
        data.merge(overrides) { _, new in new }
        return try JSONDecoder().decode(MediaProbe.Stream.self, from: JSONSerialization.data(withJSONObject: data))
    }
    private var mastering: [String: Any] { ["side_data_type": "Mastering display metadata", "red_x": "34000/50000", "red_y": "16000/50000", "green_x": "13250/50000", "green_y": "34500/50000", "blue_x": "7500/50000", "blue_y": "3000/50000", "white_point_x": "15635/50000", "white_point_y": "16450/50000", "min_luminance": "50/10000", "max_luminance": "10000000/10000"] }
    private var light: [String: Any] { ["side_data_type": "Content light level metadata", "max_content": 1000, "max_average": 400] }
    private func frame(_ pts: Int64, side: [[String: Any]]? = nil) -> [String: Any] {
        ["pts": pts, "width": 160, "height": 90, "pix_fmt": "yuv420p10le", "sample_aspect_ratio": "1:1", "interlaced_frame": 0,
         "color_range": "tv", "color_space": "bt2020nc", "color_primaries": "bt2020", "color_transfer": "smpte2084", "chroma_location": "left",
         "side_data_list": side ?? [mastering, light]]
    }
    private func contract(side: [[String: Any]]? = nil, pts: [Int64] = [0,42,83]) throws -> HDR10Contract {
        let a = try HDRFrameAccumulator(stream: stream())
        for p in pts { try a.consume(frame(p, side: side)) }
        return try a.finish()
    }
    private func folder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hdr10-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        return dir
    }
    private func config() -> EncodeConfiguration {
        var c = EncodeConfiguration(); c.codec = "HEVC"; c.encoder = "x265"; c.colorMode = "Preserve static HDR10"; c.audio = "No audio"; c.speed = "Fast"
        return c
    }
    private let baseParams = "pools=1:frame-threads=1:log-level=error:lossless=1:repeat-headers=1:hdr10=1:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:range=limited:master-display=G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,50)"
    private func fixture(_ path: URL, tools: FFmpegTools, cll: Bool = true, duration: String = "2") async throws {
        let r = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-n", "-f", "lavfi", "-i", "nullsrc=size=160x90:rate=24000/1001:duration=\(duration)", "-vf", "format=yuv420p10le,geq=lum='mod(X+Y*3+N*7,877)+64':cb='mod(X*5+N,897)+64':cr='mod(Y*7+N,897)+64',setparams=range=limited:color_primaries=bt2020:color_trc=smpte2084:colorspace=bt2020nc", "-c:v", "libx265", "-preset", "ultrafast", "-x265-params", baseParams + (cll ? ":max-cll=1000,400" : ":cll=0"), path.path])
        try #require(r.status == 0, Comment(rawValue: String(decoding: r.stderr, as: UTF8.self)))
    }

    @Test func chunkedJSONRequiresCompleteFramingAndBounds() throws {
        let data = try JSONSerialization.data(withJSONObject: ["frames": [frame(0), frame(42), frame(83)]], options: .prettyPrinted)
        for size in [1, 7, 4096] {
            let a = try HDRFrameAccumulator(stream: stream())
            let parser = HDRFrameJSON { try a.consume($0) }
            for start in stride(from: 0, to: data.count, by: size) { parser.accept(data.subdata(in: start..<min(start+size, data.count))) }
            try parser.finish(); #expect(try a.finish().frames == 3)
            #expect(parser.peakRecordBytes < 4096)
        }
        for text in ["", "{\"frames\":[", "{\"frames\":[{}]", "{\"frames\":[],}", "{\"frames\":[{\"pts\":0,\"pts\":0}]}", "{\"fra mes\":[]}", "{\"frames\":[{},]}", "{\"frames\":[]}garbage", "{\"frames\":[],\"streams\":[]}"] {
            let parser = HDRFrameJSON { _ in }
            parser.accept(Data(text.utf8)); #expect(throws: (any Error).self) { try parser.finish() }
        }
        let oversized = HDRFrameJSON { _ in }
        oversized.accept(Data("{\"frames\":[{\"padding\":\"".utf8))
        for _ in 0..<1025 { oversized.accept(Data(repeating: 97, count: 1024)) }
        #expect(throws: (any Error).self) { try oversized.finish() }
        #expect(oversized.peakRecordBytes <= HDRFrameJSON.recordLimit)
    }

    @Test func lateChangesUnknownDynamicAndMissingMetadataFailClosed() throws {
        var changed = mastering; changed["max_luminance"] = "9000000/10000"
        for badSide in [[changed, light], [mastering], [light], [mastering, light, light], [mastering, ["side_data_type": "HDR Dynamic Metadata SMPTE2094-40 (HDR10+)"]], [mastering, ["side_data_type": "DOVI RPU Data"]], [mastering, ["side_data_type": "future payload"]]] {
            let a = try HDRFrameAccumulator(stream: stream()); try a.consume(frame(0))
            #expect(throws: (any Error).self) { try a.consume(frame(42, side: badSide)) }
        }
        var changing = frame(42); changing["color_range"] = "pc"
        let a = try HDRFrameAccumulator(stream: stream()); try a.consume(frame(0))
        #expect(throws: (any Error).self) { try a.consume(changing) }
        #expect(throws: (any Error).self) { try HDRFrameAccumulator(stream: stream(["side_data_list": [["side_data_type": "DOVI configuration record"]]])) }
        #expect(throws: (any Error).self) { try HDRFrameAccumulator(stream: stream(["start_pts": 1])) }
        #expect(throws: (any Error).self) { try HDRFrameAccumulator(stream: stream(["time_base": "1/24"])) }
        for value in ["1/0", "-1/50000", "NaN/1", "1/3", "50001/50000", "9223372036854775807/1"] {
            var md = mastering; md["red_x"] = value
            #expect(throws: (any Error).self) { try HDRMasteringDisplay(md) }
        }
        #expect(throws: (any Error).self) { try HDRContentLight(["max_content": true, "max_average": 0]) }
        #expect(throws: (any Error).self) { try HDRContentLight(["max_content": 10, "max_average": 11]) }
        #expect(throws: (any Error).self) { try HDRContentLight(["max_content": 65536, "max_average": 1]) }
    }

    @Test func cadenceUsesFrameIndexAndOutputPresenceIsExact() throws {
        let source = try contract()
        try source.verify(contract())
        #expect(throws: (any Error).self) { try source.verify(contract(side: [mastering])) }
        #expect(throws: (any Error).self) { try contract(side: [mastering]).verify(source) }
        #expect(throws: (any Error).self) { try source.verify(contract(pts: [0,42])) }
        for pts: [Int64] in [[1,42,83], [0,42,42], [0,42,87], [0,43,86]] {
            #expect(throws: (any Error).self) { try contract(pts: pts) }
        }
        // Equivalent exact fractions normalize to identical encoder units.
        var md = mastering; md["red_x"] = "17/25"
        #expect(try HDRMasteringDisplay(md) == HDRMasteringDisplay(mastering))
        #expect(try contract(side: [mastering]).x265Parameters.hasSuffix("cll=0"))
    }

    @Test func intentRoundTripsAndIncompatiblePlansRefuse() throws {
        let oldData = try JSONEncoder().encode(EncodeConfiguration())
        #expect(!String(decoding: oldData, as: UTF8.self).contains("colorIntent"))
        #expect(try JSONDecoder().decode(EncodeConfiguration.self, from: oldData).colorMode == "SDR")
        let c = config()
        #expect(try JSONDecoder().decode(EncodeConfiguration.self, from: JSONEncoder().encode(c)) == c)
        var unknown = c; unknown.colorMode = "future-color"
        #expect(throws: (any Error).self) { try SessionDocument.validate(unknown) }
        for change: (inout EncodeConfiguration) -> Void in [
            { $0.codec = "AV1" }, { $0.rate.backend = "Apple hardware" }, { $0.container = "MP4" },
            { $0.cropTop = 2 }, { $0.picture.cropLeft = 2 }, { $0.resolution = "1920 × 1080" },
            { $0.picture.start = 1 }, { $0.picture.deinterlace = "Flagged frames" }
        ] {
            var invalid = c; change(&invalid)
            #expect(throws: (any Error).self) { try EncodePlan.validateHDRSettings(invalid) }
        }
        let job = QueueJob(id: UUID(), source: "/synthetic/source.mkv", isDemo: false, destination: "/synthetic/output.mkv", configuration: c, created: Date())
        let session = SessionDocument(configuration: c, outputFolder: "/synthetic", outputStem: "output", jobs: [job])
        #expect(try JSONDecoder().decode(SessionDocument.self, from: JSONEncoder().encode(session)).validated().jobs[0].configuration.colorMode == c.colorMode)
        let journal = BatchJournal(jobs: [job], statuses: [:])
        #expect(try JSONDecoder().decode(BatchJournal.self, from: JSONEncoder().encode(journal)).validated().jobs[0].configuration.colorMode == c.colorMode)
        let p = MediaProbe(streams: [try stream()], format: nil)
        #expect(throws: (any Error).self) { try EncodePlan.make(job: job, probe: p, encoders: ["libx265"], staged: URL(fileURLWithPath: job.destination)) }
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), arguments: [true, false])
    func generatedTenBitRampLosslessAndProductionQueue(cll: Bool) async throws {
        let tools = try #require(FFmpegTools.discover()); try await HDR10Audit.checkTools(tools)
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("source.mkv"), output = dir.appendingPathComponent("lossless.mkv")
        try await fixture(source, tools: tools, cll: cll)
        let fingerprint = try await SourceFingerprint.read(source)
        let probe = try await MediaProbe.read(source, tools: tools)
        let hdr = try await HDR10Audit.read(source, tools: tools, probe: probe)
        #expect(hdr.frames == 48); #expect((hdr.light != nil) == cll)
        let job = QueueJob(id: UUID(), source: source.path, isDemo: false, destination: output.path, configuration: config(), created: Date())
        let plan = try EncodePlan.make(job: job, probe: probe, encoders: ["libx265"], staged: output, hdr: hdr)
        var args = plan.arguments
        // Test-only lossless switch; production UI never claims pixel identity.
        let index = try #require(args.firstIndex(of: "-x265-params")); args[index + 1] += ":lossless=1"
        let encode = try await ToolRunner().run(executable: tools.ffmpeg, arguments: args)
        try #require(encode.status == 0, Comment(rawValue: String(decoding: encode.stderr, as: UTF8.self)))
        let actual = try await MediaProbe.read(output, tools: tools)
        try hdr.verify(await HDR10Audit.read(output, tools: tools, probe: actual, expectedRate: hdr.rate))
        var hashes: [[String]] = []
        for file in [source, output] {
            let result = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-i", file.path, "-map", "0:v:0", "-f", "framemd5", "-"])
            try #require(result.status == 0 && !result.truncated)
            hashes.append(String(decoding: result.stdout, as: UTF8.self).split(separator: "\n").filter { !$0.hasPrefix("#") }.map { String($0.split(separator: ",").last!) })
        }
        #expect(hashes[0].count == 48); #expect(hashes[0] == hashes[1])
        let pixels = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-i", source.path, "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "yuv420p10le", "-"])
        try #require(pixels.status == 0 && !pixels.truncated)
        #expect(Set(stride(from: 0, to: pixels.stdout.count, by: 2).map { pixels.stdout[$0] & 3 }) == [0,1,2,3])
        var production = job; production.destination = dir.appendingPathComponent("production.mkv").path
        let batch = BatchController(); await batch.discover(); batch.start([production])
        while batch.running { try await Task.sleep(for: .milliseconds(10)) }
        let state = try #require(batch.statuses[job.id]); #expect(state.phase == "Completed", Comment(rawValue: state.detail))
        #expect(state.detail.contains("Verified 48 frames"))
        #expect(try await SourceFingerprint.read(source) == fingerprint)
        // Retry a completed destination under a fresh controller: exclusive publication.
        let collision = BatchController(); await collision.discover(); collision.start([production])
        while collision.running { try await Task.sleep(for: .milliseconds(10)) }
        #expect(collision.statuses[job.id]?.phase == "Failed")
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).allSatisfy { !$0.hasPrefix(".staxrip-batch-") })
    }
    @Test(.enabled(if: FFmpegTools.discover() != nil))
    func cancellationMutationAndFailedVerificationDoNotPublish() async throws {
        let tools = try #require(FFmpegTools.discover())
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("source.mkv")
        try await fixture(source, tools: tools, duration: "30")
        let before = try await SourceFingerprint.read(source)
        var c = config(); c.speed = "Thorough"
        let job = QueueJob(id: UUID(), source: source.path, isDemo: false, destination: dir.appendingPathComponent("result.mkv").path, configuration: c, created: Date())
        let batch = BatchController(); await batch.discover(); batch.start([job])
        let deadline = Date().addingTimeInterval(20)
        while batch.running && batch.statuses[job.id]?.detail.contains("source audit ·") != true && Date() < deadline { try await Task.sleep(for: .milliseconds(1)) }
        try #require(batch.running && batch.statuses[job.id]?.phase == "Inspecting")
        let cancelled = Date(); batch.cancel()
        while batch.running { try await Task.sleep(for: .milliseconds(10)) }
        #expect(batch.statuses[job.id]?.phase == "Cancelled")
        #expect(Date().timeIntervalSince(cancelled) < 5)
        #expect(!FileManager.default.fileExists(atPath: job.destination))
        #expect(try await SourceFingerprint.read(source) == before)
        print("HDR cancellation seconds=\(Date().timeIntervalSince(cancelled))")
        // Modify the actual source after its audit and while the encoder owns an
        // open file. Container still decodes, but its byte identity has changed.
        batch.start([job])
        let encodeDeadline = Date().addingTimeInterval(20)
        while batch.running && batch.statuses[job.id]?.phase != "Encoding" && Date() < encodeDeadline { try await Task.sleep(for: .milliseconds(1)) }
        try #require(batch.running && batch.statuses[job.id]?.phase == "Encoding")
        let handle = try FileHandle(forWritingTo: source); try handle.seekToEnd(); try handle.write(contentsOf: Data([0])); try handle.close()
        while batch.running { try await Task.sleep(for: .milliseconds(10)) }
        #expect(batch.statuses[job.id]?.phase == "Failed")
        #expect(batch.statuses[job.id]?.detail.contains("Source changed") == true)
        #expect(!FileManager.default.fileExists(atPath: job.destination))
        // A local probe wrapper injects a wrong output declaration, after a real
        // encode. Production never uses this fixture executable.
        let wrapper = dir.appendingPathComponent("probe-fixture")
        let script = """
        #!/bin/zsh
        if [[ "$*" == *encoded.mkv* && "$*" == *-show_streams* ]]; then
            "\(tools.ffprobe.path)" "$@" | /usr/bin/sed 's/"color_transfer": "smpte2084"/"color_transfer": "bt709"/g'
        else
            exec "\(tools.ffprobe.path)" "$@"
        fi
        """
        try script.write(to: wrapper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapper.path)
        // Restore a valid short source through a new file; never overwrite media.
        let fresh = dir.appendingPathComponent("fresh.mkv"); try await fixture(fresh, tools: tools)
        let failedJob = QueueJob(id: UUID(), source: fresh.path, isDemo: false, destination: job.destination, configuration: config(), created: Date())
        let failed = BatchController(); await failed.discover()
        failed.tools = FFmpegTools(ffmpeg: tools.ffmpeg, ffprobe: wrapper)
        failed.start([failedJob])
        while failed.running { try await Task.sleep(for: .milliseconds(10)) }
        #expect(failed.statuses[failedJob.id]?.phase == "Failed")
        #expect(failed.statuses[failedJob.id]?.detail.contains("Requires HEVC Main 10") == true)
        #expect(!FileManager.default.fileExists(atPath: job.destination))
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).allSatisfy { !$0.hasPrefix(".staxrip-batch-") })
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), arguments: ["exit", "truncated"])
    func unsuccessfulOrIncompleteToolOutputCannotPass(mode: String) async throws {
        let tools = try #require(FFmpegTools.discover())
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("source.mkv"); try await fixture(source, tools: tools)
        let probe = try await MediaProbe.read(source, tools: tools)
        let wrapper = dir.appendingPathComponent("probe-failure")
        let command = mode == "exit" ? "\"\(tools.ffprobe.path)\" \"$@\"; exit 7" : "\"\(tools.ffprobe.path)\" \"$@\" | /usr/bin/sed '$d'"
        try ("#!/bin/zsh\n" + command + "\n").write(to: wrapper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapper.path)
        do {
            _ = try await HDR10Audit.read(source, tools: FFmpegTools(ffmpeg: tools.ffmpeg, ffprobe: wrapper), probe: probe)
            Issue.record("Failed or incomplete probe output passed")
        } catch {
            #expect(error.localizedDescription.contains(mode == "exit" ? "Full decode failed" : "Incomplete frame audit"))
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["STAXRIP_HDR_RESOURCE"] == "1"))
    func tenMinuteBoundedAudit() async throws {
        let tools = try #require(FFmpegTools.discover())
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("ten-minutes.mkv")
        try await fixture(source, tools: tools, duration: "600")
        let probe = try await MediaProbe.read(source, tools: tools)
        let start = Date()
        var baseline = rusage(); getrusage(RUSAGE_SELF, &baseline)
        print("HDR RESOURCE scan begins")
        let hdr = try await HDR10Audit.read(source, tools: tools, probe: probe, metrics: { bytes in
            print("HDR RESOURCE peak_frame_metadata_bytes=\(bytes)")
        })
        #expect(hdr.frames == 14386)
        var peak = rusage(); getrusage(RUSAGE_SELF, &peak)
        #expect(peak.ru_maxrss - baseline.ru_maxrss < 16 * 1024 * 1024)
        print("HDR RESOURCE helper_peak_bytes=\(peak.ru_maxrss) scan_peak_increase_bytes=\(peak.ru_maxrss - baseline.ru_maxrss)")
        print("HDR RESOURCE scan seconds=\(Date().timeIntervalSince(start)) frames=\(hdr.frames)")
    }

}
