import Foundation
import Testing
@testable import StaxRipMac

@MainActor
struct ContainerInspectionTests {
    private func probe(_ fields: [String: Any]) throws -> MediaProbe {
        try JSONDecoder().decode(MediaProbe.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    private func directory() throws -> URL {
        let result = FileManager.default.temporaryDirectory.appendingPathComponent("container-inspection-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: result, withIntermediateDirectories: false)
        return result
    }
    @Test func missingAndMalformedChapterTimesRemainExplicit() throws {
        let absent = try probe(["streams": []])
        #expect(absent.chapters == nil); #expect(ContainerInspection.chapters(absent).isEmpty)
        let value = try probe(["streams": [], "format": ["duration": "5"], "chapters": [
            ["id": 7, "tags": ["title": ""]],
            ["id": 7, "start_time": "NaN", "end_time": "infinity"],
            ["start_time": "3", "end_time": "2"],
            ["start_time": "-1", "end_time": "6"],
            ["start_time": "1.234", "end_time": "4.999", "time_base": "1/1000", "tags": ["TITLE": "Opening"]]
        ]])
        let rows = ContainerInspection.chapters(value)
        #expect(rows.count == 5); #expect(Set(rows.map(\.id)).count == 5)
        #expect(rows[0].title == "Untitled chapter"); #expect(rows[0].identifier == "7")
        #expect(rows[0].start == "Unavailable"); #expect(rows[0].end == "Unavailable")
        #expect(rows[1].note?.contains("missing or invalid") == true)
        #expect(rows[2].note == "End is not after start.")
        #expect(rows[3].start == "−00:00:01.000")
        #expect(rows[3].note?.contains("Starts before zero") == true)
        #expect(rows[3].note?.contains("beyond the reported container duration") == true)
        #expect(rows[4].title == "Opening"); #expect(rows[4].start == "00:00:01.234")
        #expect(rows[4].end == "00:00:04.999"); #expect(rows[4].note == nil)
        #expect(ContainerInspection.timestamp("3599.9999") == "01:00:00.000")
        for raw in ["1e308", "1e999", "", "N/A", "nan", "inf"] { #expect(ContainerInspection.timestamp(raw) == "Unavailable") }
    }
    @Test func boundedLabelsListsAndCoverArtDoNotInventPathsOrHideDuplicates() throws {
        let raw = "name\n\t\u{202E}" + String(repeating: "é", count: 600)
        let label = ContainerInspection.text(raw)
        #expect(!label.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) })
        #expect(label.hasSuffix("[shortened]")); #expect(label.unicodeScalars.count < 540)
        let chapters = Array(repeating: ["id": 1, "start_time": "0", "end_time": "1", "tags": ["title": "Duplicate identifier"]] as [String: Any], count: 201)
        let value = try probe(["streams": [
            ["index": 0, "codec_type": "video", "codec_name": "h264"],
            ["index": 1, "codec_type": "video", "codec_name": "png", "disposition": ["attached_pic": 1]],
            ["index": 2, "codec_type": "attachment", "tags": ["FILENAME": "../../not-a-path-to-open", "MIMETYPE": "text/plain"]]
        ], "chapters": chapters])
        #expect(ContainerInspection.chapters(value).count == 200)
        #expect(Set(ContainerInspection.chapters(value).map(\.id)).count == 200)
        #expect(ContainerInspection.limitNotice(201)?.contains("200 of 201") == true)
        #expect(ContainerInspection.limitNotice(200) == nil)
        #expect(ContainerInspection.tracks(value).map(\.index) == [0])
        #expect(value.video?.index == 0)
        let attachments = ContainerInspection.attachments(value)
        #expect(attachments.map(\.kind) == ["Cover artwork", "Embedded file"])
        #expect(attachments[0].filename == "Unspecified"); #expect(attachments[0].mimeType == "Unspecified")
        #expect(attachments[1].filename == "../../not-a-path-to-open")
        #expect(attachments[1].mimeType == "text/plain"); #expect(attachments[1].codec == "Unspecified")
        let many = try probe(["streams": Array(repeating: ["index": 9, "codec_type": "attachment"], count: 201)])
        #expect(ContainerInspection.attachments(many).count == 200)
        #expect(Set(ContainerInspection.attachments(many).map(\.id)).count == 200)
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil))
    func generatedChaptersAttachmentsAndCoverArtAreReadWithoutMutation() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let tools = try #require(FFmpegTools.discover())
        let metadata = root.appendingPathComponent("chapters.ffmeta"), note = root.appendingPathComponent("notes.txt")
        try Data(";FFMETADATA1\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=0\nEND=500\ntitle=Opening — 起点\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=500\nEND=1000\ntitle=Closing\n".utf8).write(to: metadata)
        try Data("Generated attachment\n".utf8).write(to: note)
        let source = root.appendingPathComponent("chapters.mkv")
        let fixture = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-n", "-f", "lavfi", "-i", "testsrc2=size=160x96:rate=24:duration=1", "-f", "ffmetadata", "-i", metadata.path, "-map", "0:v", "-map_metadata", "1", "-map_chapters", "1", "-c:v", "libx264", "-preset", "ultrafast", "-attach", note.path, "-metadata:s:t:0", "mimetype=text/plain", "-metadata:s:t:0", "filename=notes.txt", source.path])
        try #require(fixture.status == 0)
        let before = try Data(contentsOf: source), listing = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        let data = try await MediaProbe.read(source, tools: tools)
        let rows = ContainerInspection.chapters(data)
        #expect(rows.map(\.title) == ["Opening — 起点", "Closing"])
        #expect(rows.map(\.start) == ["00:00:00.000", "00:00:00.500"])
        #expect(rows.map(\.end) == ["00:00:00.500", "00:00:01.000"])
        #expect(ContainerInspection.attachments(data).first?.filename == "notes.txt")
        #expect(ContainerInspection.attachments(data).first?.mimeType == "text/plain")
        #expect(try Data(contentsOf: source) == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == listing)
        let png = root.appendingPathComponent("cover.png"), movie = root.appendingPathComponent("artwork.mp4")
        let image = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-f", "lavfi", "-i", "color=c=red:size=32x32", "-frames:v", "1", "-threads", "1", png.path])
        try #require(image.status == 0)
        let artwork = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-i", source.path, "-i", png.path, "-map", "0:v:0", "-map", "1:v:0", "-map_chapters", "-1", "-c", "copy", "-disposition:v:1", "attached_pic", movie.path])
        try #require(artwork.status == 0)
        let movieBytes = try Data(contentsOf: movie)
        let cover = try await MediaProbe.read(movie, tools: tools)
        #expect(cover.video?.index == 0)
        #expect(ContainerInspection.chapters(cover).isEmpty)
        #expect(ContainerInspection.attachments(cover).map(\.kind) == ["Cover artwork"])
        #expect(try Data(contentsOf: movie) == movieBytes)
    }

    private actor HeldInspection {
        let entered: AsyncStream<URL>.Continuation
        var pending: [URL: CheckedContinuation<MediaProbe, Error>] = [:]
        var reads: [URL] = []
        init(entered: AsyncStream<URL>.Continuation) { self.entered = entered }
        func read(_ source: URL) async throws -> MediaProbe {
            reads.append(source)
            // Hold the real completion boundary, including an uncooperative late
            // result. No child-process startup speed is part of this state test.
            return try await withCheckedThrowingContinuation { continuation in
                pending[source] = continuation
                entered.yield(source)
            }
        }
        func release(_ source: URL, result: Result<MediaProbe, Error>) {
            guard let continuation = pending.removeValue(forKey: source) else {
                Issue.record("Missing held inspection"); return
            }
            continuation.resume(with: result)
        }
        func releaseAll() {
            let held = pending; pending = [:]
            for continuation in held.values { continuation.resume(throwing: CancellationError()) }
            entered.finish()
        }
    }
    enum OldCompletion: Sendable { case success, failure, cancelled }

    @Test(.timeLimit(.minutes(1)), arguments: [OldCompletion.success, .failure, .cancelled])
    func supersededInspectionCannotClearOrReplaceNewSource(completion: OldCompletion) async throws {
        let oldSource = URL(fileURLWithPath: "/generated/old"), newSource = URL(fileURLWithPath: "/generated/new")
        let (entries, entered) = AsyncStream<URL>.makeStream()
        let reader = HeldInspection(entered: entered)
        let controller = BatchController(readInspection: { source, _ in try await reader.read(source) })
        controller.tools = FFmpegTools(ffmpeg: URL(fileURLWithPath: "/generated/ffmpeg"), ffprobe: URL(fileURLWithPath: "/generated/ffprobe"))
        let oldResult = try probe(["streams": [], "chapters": [["id": 1, "tags": ["title": "Old source"]]]])
        let newResult = try probe(["streams": [], "chapters": [["id": 2, "start_time": "0", "end_time": "2", "tags": ["title": "New source"]]]])
        var iterator = entries.makeAsyncIterator()
        let old = Task { await controller.inspect(oldSource) }
        var newer: Task<Void, Never>?
        do {
            try #require(await iterator.next() == oldSource)
            newer = Task { await controller.inspect(newSource) }
            try #require(await iterator.next() == newSource)
            if completion == .cancelled { old.cancel() }
            await reader.release(oldSource, result: completion == .failure ?
                .failure(NativeExportError.invalid("Generated stale inspection failure")) : .success(oldResult))
            await old.value
            #expect(controller.inspecting)
            #expect(controller.inspection == nil && controller.inspectionError == nil)
            await reader.release(newSource, result: .success(newResult))
            await newer?.value
            #expect(!controller.inspecting && controller.inspectionError == nil)
            #expect(controller.inspection?.chapters?.first?.tags?["title"] == "New source")
            controller.tools = nil
            await controller.inspect(oldSource)
            #expect(controller.inspection == nil && !controller.inspecting)
            #expect(controller.inspectionError == "FFmpeg tools are unavailable.")
            #expect(await reader.reads == [oldSource, newSource])
            await reader.releaseAll()
        } catch {
            old.cancel(); newer?.cancel()
            await reader.releaseAll()
            await old.value; await newer?.value
            throw error
        }
    }
}
