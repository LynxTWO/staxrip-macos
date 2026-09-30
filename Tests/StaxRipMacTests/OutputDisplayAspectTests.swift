import Foundation
import Testing
@testable import StaxRipMac

struct OutputDisplayAspectTests {
    @Test func exactFractionsPreserveCroppedDisplayShapeAcrossEvenScaling() throws {
        let plan = try OutputDisplayAspect(width: 706, height: 470, sampleAspectRatio: "32:27")
        #expect(plan.summary == "Expected display proportions 11296:6345")
        #expect(try plan.verify(width: 1082, height: 720, sampleAspectRatio: "90368:76281") == "Verified display proportions 11296:6345")
        #expect(try plan.verify(width: 706, height: 470, sampleAspectRatio: "64:54").contains("Verified"))
        #expect(throws: (any Error).self) { try plan.verify(width: 1082, height: 720, sampleAspectRatio: "1:1") }
        #expect(throws: (any Error).self) { try plan.verify(width: 1082, height: 720, sampleAspectRatio: "90367:76281") }
        #expect(throws: (any Error).self) { try plan.verify(width: 1082, height: 720, sampleAspectRatio: "32:27") }
        let square = try OutputDisplayAspect(width: 720, height: 480, sampleAspectRatio: "2:2")
        #expect(try square.verify(width: 1080, height: 720, sampleAspectRatio: "1:1") == "Verified display proportions 3:2")
    }

    @Test func missingRatiosStayUnknownAndCannotSatisfyAKnownContract() throws {
        for value: String? in [nil, "N/A", "0:1"] {
            let unknown = try OutputDisplayAspect(width: 160, height: 96, sampleAspectRatio: value)
            #expect(unknown.summary == OutputDisplayAspect.unavailable)
            #expect(try unknown.verify(width: 160, height: 96, sampleAspectRatio: nil) == OutputDisplayAspect.unavailable)
            #expect(try unknown.verify(width: 160, height: 96, sampleAspectRatio: "1:1") == OutputDisplayAspect.unavailable)
            let known = try OutputDisplayAspect(width: 160, height: 96, sampleAspectRatio: "1:1")
            #expect(throws: (any Error).self) { try known.verify(width: 160, height: 96, sampleAspectRatio: value) }
        }
    }

    @Test func malformedRatiosAndRasterBoundsRefuseWithoutOverflow() throws {
        let known = try OutputDisplayAspect(width: 160, height: 96, sampleAspectRatio: "1:1")
        let unknown = try OutputDisplayAspect(width: 160, height: 96, sampleAspectRatio: nil)
        for value in ["", "1/1", " 1:1", "1:1\n", "-1:1", "+1:1", "0:0", "1:0", "1:-1", "0:2", "1.0:1", "1:1:1", "2147483648:1", "1:2147483648", "NaN", "∞:1", "١:١", String(repeating: ":", count: 100000)] {
            #expect(throws: (any Error).self) { try OutputDisplayAspect(width: 160, height: 96, sampleAspectRatio: value) }
            #expect(throws: (any Error).self) { try known.verify(width: 160, height: 96, sampleAspectRatio: value) }
            #expect(throws: (any Error).self) { try unknown.verify(width: 160, height: 96, sampleAspectRatio: value) }
        }
        for dimension in [0, -1, Int(Int32.max) + 1, Int.max] {
            #expect(throws: (any Error).self) { try OutputDisplayAspect(width: dimension, height: 96, sampleAspectRatio: "1:1") }
            #expect(throws: (any Error).self) { try OutputDisplayAspect(width: 160, height: dimension, sampleAspectRatio: "1:1") }
            #expect(throws: (any Error).self) { try known.verify(width: dimension, height: 96, sampleAspectRatio: "1:1") }
            #expect(throws: (any Error).self) { try known.verify(width: 160, height: dimension, sampleAspectRatio: "1:1") }
        }
        #expect(throws: (any Error).self) { try known.verify(width: nil, height: 96, sampleAspectRatio: "1:1") }
        #expect(throws: (any Error).self) { try known.verify(width: 160, height: nil, sampleAspectRatio: "1:1") }
        let largest = try OutputDisplayAspect(width: Int(Int32.max), height: 1, sampleAspectRatio: "2147483647:1")
        #expect(try largest.verify(width: Int(Int32.max), height: 1, sampleAspectRatio: "2147483647:1") == "Verified display proportions 4611686014132420609:1")
        let tiny = try OutputDisplayAspect(width: 1, height: Int(Int32.max), sampleAspectRatio: "1:2147483647")
        #expect(try tiny.verify(width: 1, height: Int(Int32.max), sampleAspectRatio: "1:2147483647") == "Verified display proportions 1:4611686014132420609")
    }

    @Test func encodePlanUsesUprightCropAndLeavesFiltersUnchanged() throws {
        var stream: [String: Any] = ["index": 0, "codec_type": "video", "codec_name": "h264", "width": 722, "height": 480,
                                     "pix_fmt": "yuv420p", "sample_aspect_ratio": "32:27", "field_order": "progressive"]
        var configuration = EncodeConfiguration(); configuration.selectCodec("H.264"); configuration.audio = "No audio"
        configuration.picture.cropLeft = 6; configuration.picture.cropRight = 10; configuration.cropTop = 4; configuration.cropBottom = 6
        configuration.resolution = "1280 × 720"
        func plan() throws -> EncodePlan {
            let probe = try JSONDecoder().decode(MediaProbe.self, from: JSONSerialization.data(withJSONObject: ["streams": [stream], "format": ["duration": "1"]]))
            let job = QueueJob(id: UUID(), source: "/generated/source.mp4", isDemo: false, destination: "/generated/output.mkv", configuration: configuration, created: Date())
            return try EncodePlan.make(job: job, probe: probe, encoders: ["libx264"], staged: URL(fileURLWithPath: "/generated/stage.mkv"))
        }
        let cropped = try plan()
        #expect(cropped.summary.contains("Expected display proportions 11296:6345"))
        #expect(cropped.arguments.contains("crop=iw-16:ih-10:6:4,scale=1280:720:force_original_aspect_ratio=decrease:force_divisible_by=2"))
        stream["sample_aspect_ratio"] = "1:1"
        stream["side_data_list"] = [["side_data_type": "Display Matrix", "rotation": 90,
                                     "displaymatrix": "00000000: 0 -65536 0\n00000001: 65536 0 0\n00000002: 0 0 1073741824"]]
        let rotated = try plan()
        // Upright 480x722, then the same crop: 464x712 -> 58:89.
        #expect(rotated.summary.contains("Expected display proportions 58:89"))
        #expect(try rotated.outputDisplayAspect.verify(width: 464, height: 712, sampleAspectRatio: "1:1").contains("58:89"))
        stream.removeValue(forKey: "side_data_list"); stream.removeValue(forKey: "sample_aspect_ratio")
        #expect(try plan().summary.contains(OutputDisplayAspect.unavailable))
    }
}
