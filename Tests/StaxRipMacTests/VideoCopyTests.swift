import Foundation
import Testing
@testable import StaxRipMac

struct VideoCopyTests {
    private let digest = "SHA256:" + String(repeating: "ab", count: 32)
    private func probe(_ changes: [String: Any] = [:], format: [String: Any]? = nil) throws -> MediaProbe {
        var video: [String: Any] = ["index": 0, "codec_type": "video", "codec_name": "h264", "profile": "High",
            "width": 160, "height": 96, "pix_fmt": "yuv420p", "field_order": "progressive", "sample_aspect_ratio": "1:1",
            "time_base": "1/24000", "start_pts": 0, "extradata_size": 32, "extradata_hash": digest]
        video.merge(changes) { _, new in new }
        let object: [String: Any] = ["streams": [video], "format": format ?? ["format_name": "mov,mp4,m4a,3gp,3g2,mj2", "start_time": "0", "duration": "3"]]
        return try JSONDecoder().decode(MediaProbe.self, from: JSONSerialization.data(withJSONObject: object))
    }
    private var configuration: EncodeConfiguration {
        var c = EncodeConfiguration(); c.selectCodec("Copy original"); c.audio = "No audio"
        c.subtitleMode = "Remove all subtitles"; return c
    }
    private func line(pts: Int = 0, duration: Int = 1000, size: Int = 42) -> String {
        "pts=\(pts)|duration=\(duration)|size=\(size)|data_hash=\(digest)\n"
    }

    @Test func copyIntentKeepsStoredEncodingChoicesAndRoundTrips() throws {
        var c = configuration; c.rate.backend = "Apple hardware"; c.rate.mode = "Target bitrate"; c.rate.bitrate = 8732
        c.quality = 17; c.speed = "Thorough"
        let job = QueueJob(id: UUID(), source: "/generated/source.mp4", isDemo: false,
                           destination: "/generated/output.mkv", configuration: c, created: Date())
        let session = SessionDocument(configuration: c, outputFolder: "/generated", outputStem: "output", jobs: [job])
        let decoded = try JSONDecoder().decode(SessionDocument.self, from: JSONEncoder().encode(session)).validated()
        #expect(decoded.configuration == c && decoded.jobs[0].configuration == c)
        let journal = try JSONDecoder().decode(BatchJournal.self, from: JSONEncoder().encode(BatchJournal(jobs: [job], statuses: [:]))).validated()
        #expect(journal.jobs[0].configuration == c)
        let preset = CustomPreset(name: "Original video", configuration: CustomPreset.recipe(c))
        let library = try PresetDocument.decode(PresetDocument(presets: [preset]).encoded())
        #expect(try library.presets[0].applying(to: configuration).codec == "Copy original")
        let plan = try EncodePlan.make(job: job, probe: probe(), encoders: [], staged: URL(fileURLWithPath: "/generated/staged.mkv"))
        #expect(plan.videoCopy != nil && plan.expectedCodec == "h264")
        #expect(plan.arguments.contains("copy"))
        for unused in ["-pix_fmt", "-fps_mode:v", "-enc_time_base:v", "-crf", "-b:v", "-preset", "-allow_sw", "-vf", "-ss", "-t"] {
            #expect(!plan.arguments.contains(unused))
        }
        #expect(c.activeEncoder == "No video encoder" && c.rateSummary == "No video re-encoding")
        c.selectCodec("HEVC")
        #expect(c.encoder == "x265" && c.rate.backend == "Apple hardware" && c.rate.bitrate == 8732 && c.quality == 17 && c.speed == "Thorough")
        var malformed = configuration; malformed.encoder = "x264"
        #expect(throws: (any Error).self) { try SessionDocument.validate(malformed) }
    }

    @Test func unsupportedIntentAndMetadataRefuseBeforeCopy() throws {
        for change in 0..<7 {
            var c = configuration
            switch change {
            case 0: c.cropTop = 2
            case 1: c.picture.cropRight = 2
            case 2: c.resolution = "1280 × 720"
            case 3: c.picture.start = 1
            case 4: c.picture.end = 2
            case 5: c.picture.deinterlace = "All frames"
            default: c.colorMode = "Preserve static HDR10"
            }
            #expect(throws: (any Error).self) { try VideoCopyContract.make(probe: probe(), configuration: c) }
        }
        let invalid: [[String: Any]] = [["codec_name": "av1"], ["pix_fmt": "yuv420p10le"], ["field_order": "tt"],
            ["sample_aspect_ratio": "4:3"], ["start_pts": 1], ["color_transfer": "smpte2084"], ["color_transfer": "arib-std-b67"],
            ["extradata_hash": "SHA256:bad"], ["extradata_size": 0], ["time_base": "1/24"], ["width": 159],
            ["disposition": ["attached_pic": 1]], ["side_data_list": [["side_data_type": "DOVI configuration record"]]]]
        for change in invalid { #expect(throws: (any Error).self) { try VideoCopyContract.make(probe: probe(change), configuration: configuration) } }
        for format: [String: Any] in [["format_name": "mpegts", "start_time": "0", "duration": "3"],
                                      ["format_name": "mov", "duration": "3"],
                                      ["format_name": "mov", "start_time": "0", "duration": "172801"]] {
            #expect(throws: (any Error).self) { try VideoCopyContract.make(probe: probe(format: format), configuration: configuration) }
        }
        let contract = try VideoCopyContract.make(probe: probe(), configuration: configuration)
        for change: [String: Any] in [["profile": "Main"], ["width": 162], ["color_range": "pc"], ["extradata_hash": "SHA256:" + String(repeating: "cd", count: 32)]] {
            #expect(throws: (any Error).self) { try contract.verifyMetadata(probe(change)) }
        }
    }

    @Test func packetFramingBoundsAndBinaryRecordsAreStrict() throws {
        let input = Data((line() + line(pts: 2000)).utf8)
        for width in [1, 2, 7, 55, 56, 57, 4096] {
            var records: [VideoCopyPacket] = []
            let parser = VideoCopyPacketStream { records.append($0) }
            for start in stride(from: 0, to: input.count, by: width) { parser.accept(input.subdata(in: start..<min(input.count, start + width))) }
            try parser.finish()
            #expect(records.count == 2 && records[1].pts == 2000)
            for record in records {
                #expect(record.record.count == 56)
                #expect(try VideoCopyPacket(record: record.record) == record)
                try record.validate(tick: 1.0 / 24000, seconds: 3)
            }
        }
        let malformed = ["", String(line().dropLast()), "\n", line().replacingOccurrences(of: "pts=0", with: "pts=N/A"),
            line().replacingOccurrences(of: "duration=1000", with: "pts=1000"),
            line().replacingOccurrences(of: "|duration=1000", with: ""),
            line().replacingOccurrences(of: "SHA256:", with: "SHA1:"),
            line().replacingOccurrences(of: "size=42", with: "size=99999999999999999999999"),
            String(repeating: "x", count: 513) + "\n", line() + "trailing"]
        for text in malformed {
            let parser = VideoCopyPacketStream { _ in }
            parser.accept(Data(text.utf8))
            #expect(throws: (any Error).self) { try parser.finish() }
        }
        let bounded = VideoCopyPacketStream(limit: 1) { _ in }
        bounded.accept(input)
        #expect(throws: (any Error).self) { try bounded.finish() }
        for text in [line(pts: -1), line(duration: 0), line(size: 0), line(size: 64 * 1024 * 1024 + 1), line(pts: 99999999)] {
            let packet = try VideoCopyPacket(line: Data(text.dropLast().utf8))
            #expect(throws: (any Error).self) { try packet.validate(tick: 1.0 / 24000, seconds: 3) }
        }
    }
}
