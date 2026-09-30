import Foundation
import CryptoKit
import Testing
@testable import StaxRipMac

@MainActor
struct ContainerPreservationTests {
    private func probe(chapters: [[String: Any]] = [], streams: [[String: Any]] = []) throws -> MediaProbe {
        try JSONDecoder().decode(MediaProbe.self, from: JSONSerialization.data(withJSONObject: ["streams": streams, "chapters": chapters]))
    }
    private func chapter(_ start: Int64 = 0, _ end: Int64 = 500, base: String = "1/1000", title: String = "Opening") -> [String: Any] {
        ["id": 7, "time_base": base, "start": start, "end": end, "tags": ["title": title]]
    }
    private var attachment: [String: Any] {
        ["index": 1, "codec_type": "attachment", "extradata_size": 30,
         "extradata_hash": "SHA256:" + String(repeating: "ab", count: 32), "tags": ["filename": "notes.txt", "mimetype": "text/plain"]]
    }
    private func configuration(_ container: String = "MKV") -> EncodeConfiguration {
        var c = EncodeConfiguration()
        c.codec = "H.264"; c.encoder = "x264"; c.container = container
        c.audio = "No audio"; c.subtitleMode = "Keep embedded tracks"; c.speed = "Fast"; c.picture.deinterlace = "Off"
        return c
    }
    @Test func chapterMeaningSurvivesIDsTimebasesAndQuantizationButNotEdits() throws {
        let source = try probe(chapters: [chapter(0, 500123, base: "1/1000000"), chapter(500123, 1000000, base: "1/1000000", title: "")])
        let contract = try ContainerPreservation.make(probe: source, configuration: configuration("MP4"))
        var first = chapter(0, 6146, base: "1/12288"); first["id"] = 0
        var last = chapter(6146, 12288, base: "1/12288"); last["id"] = 1; last.removeValue(forKey: "tags")
        #expect(try contract.verify(probe(chapters: [first, last])).contains("2 chapter"))
        for bad in [chapter(0, 600), chapter(0, 500, title: "Changed"), chapter(0, 1, base: "1/2")] {
            #expect(throws: (any Error).self) { try contract.verify(probe(chapters: [bad, last])) }
        }
        #expect(throws: (any Error).self) { try contract.verify(probe()) }
        for bad in [chapter(-1, 500), chapter(1, 1), chapter(0, 1, base: "0/1"), chapter(0, 1, base: "1/0"), chapter(0, 1, base: "nan/1"), chapter(0, 1000000001, base: "1/1"), chapter(0, 500, title: String(repeating: "é", count: 2049))] {
            #expect(throws: (any Error).self) { try ContainerPreservation.make(probe: probe(chapters: [bad]), configuration: configuration()) }
        }
        let gaps = try probe(chapters: [chapter(100, 400), chapter(600, 800)])
        _ = try ContainerPreservation.make(probe: gaps, configuration: configuration())
        #expect(throws: (any Error).self) { try ContainerPreservation.make(probe: gaps, configuration: configuration("MP4")) }
        #expect(throws: (any Error).self) { try ContainerPreservation.make(probe: probe(chapters: [chapter(), chapter(400, 900)]), configuration: configuration()) }
        #expect(throws: (any Error).self) { try ContainerPreservation.make(probe: probe(chapters: Array(repeating: chapter(), count: 10001)), configuration: configuration()) }
    }
    @Test func attachmentsRequireExactPayloadAndBoundedUnambiguousLabels() throws {
        let source = try probe(streams: [attachment])
        let contract = try ContainerPreservation.make(probe: source, configuration: configuration())
        #expect(try contract.verify(source).contains("1 attachment"))
        var variants: [[String: Any]] = []
        for (key, value) in [("extradata_size", -1 as Any), ("extradata_size", 31), ("extradata_hash", "SHA256:" + String(repeating: "cd", count: 32)), ("extradata_hash", "SHA256:bad"), ("tags", ["filename": "changed", "mimetype": "text/plain"]), ("tags", ["filename": "notes.txt", "mimetype": "changed"]), ("tags", ["filename": "notes.txt", "FILENAME": "other"]), ("tags", ["filename": String(repeating: "x", count: 4097)])] {
            var changed = attachment; changed[key] = value; variants.append(changed)
        }
        var missing = attachment; missing.removeValue(forKey: "extradata_hash"); variants.append(missing)
        for changed in variants { #expect(throws: (any Error).self) { try contract.verify(probe(streams: [changed])) } }
        #expect(throws: (any Error).self) { try contract.verify(probe()) }
        #expect(throws: (any Error).self) { try ContainerPreservation.make(probe: probe(streams: Array(repeating: attachment, count: 1001)), configuration: configuration()) }
        let omitted = try ContainerPreservation.make(probe: source, configuration: configuration("MP4"))
        #expect(try omitted.verify(probe()).contains("0 attachment"))
        #expect(throws: (any Error).self) { try omitted.verify(source) }
    }

    @Test func omittedMetadataDoesNotRequireSourceValidityButOutputMustBeEmpty() throws {
        let malformed = try probe(chapters: [["id": 1]], streams: [["index": 1, "codec_type": "attachment"]])
        var c = configuration(); c.picture.start = 0.1; c.subtitleMode = "Remove all subtitles"
        let contract = try ContainerPreservation.make(probe: malformed, configuration: c)
        #expect(try contract.verify(probe()).contains("Verified 0 chapter"))
        #expect(throws: (any Error).self) { try contract.verify(probe(chapters: [chapter()])) }
        #expect(throws: (any Error).self) { try contract.verify(probe(streams: [attachment])) }
        var excessive = attachment; excessive["extradata_size"] = Int64(Int32.max) + 1
        #expect(throws: (any Error).self) { try ContainerPreservation.readAttachments(probe(streams: [excessive])) }
        var empty = attachment; empty["extradata_size"] = 0
        empty["extradata_hash"] = "SHA256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        #expect(try ContainerPreservation.readAttachments(probe(streams: [empty])).first?.size == 0)
        var ambiguous = chapter(); ambiguous["tags"] = ["title": "Opening", "TITLE": "Different"]
        #expect(throws: (any Error).self) { try ContainerPreservation.readChapters(probe(chapters: [ambiguous])) }
    }

    private func fixture(_ root: URL, tools: FFmpegTools) async throws -> URL {
        let metadata = root.appendingPathComponent("chapters.ffmeta"), note = root.appendingPathComponent("notes.txt"), source = root.appendingPathComponent("source.mkv")
        try Data(";FFMETADATA1\n[CHAPTER]\nTIMEBASE=1/1000000\nSTART=0\nEND=500123\ntitle=Opening — 起点\n[CHAPTER]\nTIMEBASE=1/1000000\nSTART=500123\nEND=1000000\ntitle=Closing\n".utf8).write(to: metadata)
        try Data("Independent payload digest\n".utf8).write(to: note)
        let result = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-n", "-f", "lavfi", "-i", "testsrc2=size=160x96:rate=24:duration=1", "-f", "ffmetadata", "-i", metadata.path, "-map", "0:v", "-map_metadata", "1", "-map_chapters", "1", "-c:v", "libx264", "-preset", "ultrafast", "-attach", note.path, "-metadata:s:t:0", "mimetype=text/plain", "-metadata:s:t:0", "filename=notes.txt", source.path])
        try #require(result.status == 0)
        return source
    }
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("container-preservation-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
    private func finish(_ batch: BatchController) async throws {
        let deadline = Date().addingTimeInterval(20)
        while batch.running && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        if batch.running { batch.cancel() }
        try #require(!batch.running)
    }
    @Test(.enabled(if: FFmpegTools.discover() != nil))
    func actualExportsVerifyPayloadAndExistingMappingPolicies() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let tools = try #require(FFmpegTools.discover()), source = try await fixture(root, tools: tools)
        let before = try Data(contentsOf: source)
        let original = try await MediaProbe.read(source, tools: tools)
        let digest = SHA256.hash(data: try Data(contentsOf: root.appendingPathComponent("notes.txt"))).map { String(format: "%02x", $0) }.joined()
        #expect(original.streams.first(where: { $0.codec_type == "attachment" })?.extradata_hash == "SHA256:" + digest)
        var jobs: [QueueJob] = []
        for mode in ["mkv", "mp4", "trim", "remove"] {
            var c = configuration(mode == "mp4" ? "MP4" : "MKV")
            if mode == "trim" { c.picture.start = 0.25; c.picture.end = 0.75 }
            if mode == "trim" || mode == "remove" { c.subtitleMode = "Remove all subtitles" }
            jobs.append(QueueJob(id: UUID(), source: source.path, isDemo: false, destination: root.appendingPathComponent(mode + (mode == "mp4" ? ".mp4" : ".mkv")).path, configuration: c, created: Date()))
        }
        let batch = BatchController(journalURL: root.appendingPathComponent("journal.json"))
        batch.tools = tools; batch.encoders = ["libx264"]; batch.start(jobs); try await finish(batch)
        for (index, job) in jobs.enumerated() {
            let status = try #require(batch.statuses[job.id]); #expect(status.phase == "Completed", Comment(rawValue: status.detail))
            let output = try await MediaProbe.read(URL(fileURLWithPath: job.destination), tools: tools)
            #expect((output.chapters ?? []).count == (index == 2 ? 0 : 2))
            let attachments = output.streams.filter { $0.codec_type == "attachment" }
            #expect(attachments.count == (index == 0 ? 1 : 0))
            if index == 0 { #expect(attachments.first?.extradata_hash == "SHA256:" + digest) }
            #expect(status.detail.contains("Verified \(index == 2 ? 0 : 2) chapter titles/times"))
        }
        #expect(try Data(contentsOf: source) == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".staxrip-batch-") })
    }
    @Test(.enabled(if: FFmpegTools.discover() != nil), arguments: ["chapters", "attachments"])
    func alteredStagedResultCannotPublish(category: String) async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let tools = try #require(FFmpegTools.discover()), source = try await fixture(root, tools: tools)
        let before = try Data(contentsOf: source), prior = root.appendingPathComponent("prior.mkv")
        try Data("Existing output must survive".utf8).write(to: prior)
        let script = root.appendingPathComponent("encoder")
        // Paths are generated locally; shell quote even the discovered executable path.
        let quoted = "'" + tools.ffmpeg.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let body = """
        #!/bin/sh
        set -eu
        \(quoted) "$@"
        for target do :; done
        \(quoted) -v error -n -i "$target" -map 0:v \(category == "chapters" ? "-map 0:t? -map_chapters -1" : "-map_chapters 0") -c copy "${target%/*}/altered.mkv"
        /bin/mv "${target%/*}/altered.mkv" "$target"
        """
        try Data(body.utf8).write(to: script); try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let job = QueueJob(id: UUID(), source: source.path, isDemo: false, destination: root.appendingPathComponent("result.mkv").path, configuration: configuration(), created: Date())
        let batch = BatchController(journalURL: root.appendingPathComponent("journal.json"))
        batch.tools = FFmpegTools(ffmpeg: script, ffprobe: tools.ffprobe); batch.encoders = ["libx264"]; batch.start([job]); try await finish(batch)
        let status = try #require(batch.statuses[job.id])
        #expect(status.phase == "Failed"); #expect(status.detail.contains("Container preservation:"))
        #expect(!FileManager.default.fileExists(atPath: job.destination))
        #expect(try Data(contentsOf: source) == before)
        #expect(try Data(contentsOf: prior) == Data("Existing output must survive".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".staxrip-batch-") })
    }
}
