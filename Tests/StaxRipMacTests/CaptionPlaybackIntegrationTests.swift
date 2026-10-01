import Foundation
import Testing
@testable import StaxRipMac

@MainActor
struct CaptionPlaybackIntegrationTests {
    private func run(_ args: [String], _ tools: FFmpegTools) async throws -> Data {
        let result = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-nostdin", "-n"] + args)
        try #require(result.status == 0 && !result.truncated, Comment(rawValue: String(decoding: result.stderr, as: UTF8.self)))
        return result.stdout
    }
    private func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(2)),
          arguments: ["embedded copy", "embedded encode", "removed copy", "trim", "optional", "corrupt caption", "corrupt audio"])
    func actualFlagsPreserveCoexistingTracksOrRefusePublication(mode: String) async throws {
        let tools = try #require(FFmpegTools.discover())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("caption-flags-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let batch = BatchController(journalURL: root.appendingPathComponent("journal.json"))
        defer { if !batch.running { try? FileManager.default.removeItem(at: root) } }
        do {
            let source = root.appendingPathComponent("source.mkv"), prior = root.appendingPathComponent("prior.mkv")
            let files = (0..<3).map { root.appendingPathComponent("\($0).srt") }
            let documents = (0..<3).map { Data("1\n00:00:00,000 --> 00:00:01,500\nIndependent caption \($0) é 起点\n\n".utf8) }
            for i in files.indices { try documents[i].write(to: files[i]) }
            try Data("Protected existing output".utf8).write(to: prior)
            _ = try await run(["-f", "lavfi", "-i", "testsrc2=size=160x96:rate=24:duration=2", "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo:d=2",
                              "-i", files[0].path, "-map", "0:v", "-map", "1:a", "-map", "1:a", "-map", "2:s",
                              "-c:v", "libx264", "-preset", "fast", "-threads", "2", "-c:a", "flac", "-c:s", "copy",
                              "-disposition:v:0", "0", "-disposition:a:0", "0", "-disposition:a:1", "0",
                              "-disposition:s:0", "default+forced+hearing_impaired", source.path], tools)
            let before = try Data(contentsOf: source)
            var c = EncodeConfiguration(); c.selectCodec(mode == "embedded encode" || mode == "trim" ? "H.264" : "Copy original")
            c.speed = "Fast"; c.audio = mode == "trim" ? "No audio" : "Copy original"
            let keep = !["removed copy", "trim", "optional"].contains(mode)
            c.subtitleMode = keep ? "Keep embedded tracks" : "Remove all subtitles"
            if mode == "trim" { c.picture.start = 0.5; c.picture.end = 1.5 }
            c.externalCaptions = [ExternalSubtitle(path: files[1].path, language: "eng", title: "First", playback: mode == "optional" ? .optional : .forced),
                                  ExternalSubtitle(path: files[2].path, language: "fra", title: "Second", playback: mode == "optional" ? nil : .defaultAndForced)]
            let output = root.appendingPathComponent("result.mkv")
            let job = QueueJob(id: UUID(), source: source.path, isDemo: false, destination: output.path, configuration: c, created: Date())
            let next = QueueJob(id: UUID(), source: source.path, isDemo: false, destination: root.appendingPathComponent("next.mkv").path, configuration: c, created: Date())
            let corrupt = mode.hasPrefix("corrupt")
            var executingTools = tools
            if corrupt {
                let wrapper = root.appendingPathComponent("encoder-wrapper")
                let alteration = mode == "corrupt audio" ? "-disposition:a:0 -default" : "-disposition:s:2 -default"
                let body = "#!/bin/sh\nset -e\nfor target do :; done\ncase \"$target\" in */encoded.mkv)\n" + quote(tools.ffmpeg.path) + " \"$@\"\n" + quote(tools.ffmpeg.path) + " -v error -n -i \"$target\" -map 0 -c copy " + alteration + " \"$target.changed.mkv\"\n/bin/mv \"$target.changed.mkv\" \"$target\"\nexit 0;; esac\nexec " + quote(tools.ffmpeg.path) + " \"$@\"\n"
                try Data(body.utf8).write(to: wrapper); try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapper.path)
                executingTools = FFmpegTools(ffmpeg: wrapper, ffprobe: tools.ffprobe)
            }
            batch.tools = executingTools; batch.encoders = ["libx264"]; batch.start(corrupt ? [job, next] : [job])
            while batch.running { try await Task.sleep(for: .milliseconds(10)) }
            let status = try #require(batch.statuses[job.id])
            if corrupt {
                #expect(status.phase == "Failed", Comment(rawValue: status.detail))
                #expect(status.detail.contains("unexpected default or forced playback flags"), Comment(rawValue: status.detail))
                #expect(status.detail.contains(mode == "corrupt audio" ? "audio track 1" : "caption track 3"))
                #expect(!FileManager.default.fileExists(atPath: output.path))
                #expect(!FileManager.default.fileExists(atPath: next.destination) && batch.statuses[next.id]?.phase == "Pending")
            } else {
                try #require(status.phase == "Completed", Comment(rawValue: status.detail))
                #expect(status.detail.contains("Verified caption playback flags"))
                let probe = try await MediaProbe.read(output, tools: tools)
                #expect(probe.video?.disposition?["default"] == 0 && probe.video?.disposition?["forced"] == 0)
                let audio = probe.streams.filter { $0.codec_type == "audio" }
                #expect(audio.map { $0.disposition?["default"] } == (mode == "trim" ? [] : [1, 0]))
                if mode != "trim" {
                    // Container changes preserve every decoded silent sample on both copied audio streams.
                    for i in 0..<2 {
                        let args = ["-map", "0:a:\(i)", "-c:a", "pcm_s16le", "-f", "hash", "-hash", "sha256", "pipe:1"]
                        #expect(try await run(["-i", output.path] + args, tools) == run(["-i", source.path] + args, tools))
                    }
                }
                let captions = probe.streams.filter { $0.codec_type == "subtitle" }
                #expect(captions.map { $0.disposition?["default"] } == (mode == "optional" ? [0, 0] : keep ? [0, 0, 1] : [0, 1]))
                #expect(captions.map { $0.disposition?["forced"] } == (mode == "optional" ? [0, 0] : keep ? [1, 1, 1] : [1, 1]))
                if keep { #expect(captions[0].disposition?["hearing_impaired"] == 1) }
                for i in captions.indices {
                    let bytes = try await run(["-i", output.path, "-map", "0:s:\(i)", "-c:s", "srt", "-f", "srt", "pipe:1"], tools)
                    let original = documents[i + (keep ? 0 : 1)]
                    let expected = mode == "trim" ? Data(String(decoding: original, as: UTF8.self).replacingOccurrences(of: "00:00:01,500", with: "00:00:01,000").utf8) : original
                    #expect(bytes == expected)
                }
            }
            #expect(try Data(contentsOf: source) == before)
            #expect(try Data(contentsOf: prior) == Data("Protected existing output".utf8))
            for i in files.indices { #expect(try Data(contentsOf: files[i]) == documents[i]) }
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".staxrip-batch-") })
        } catch {
            batch.cancel()
            await Task { @MainActor in while batch.running { try? await Task.sleep(for: .milliseconds(10)) } }.value
            throw error
        }
    }
}
