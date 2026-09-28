import Foundation
import Testing
@testable import StaxRipMac

// Run with scripts/check-meter-conformance.command. Absence is an unmet gate,
// not a passing conformance result. EBU media remains outside the repository.
struct AnalysisConformanceTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["STAXRIP_EBU_TEST_SET"] != nil))
    func officialMonoStereoFixtures() async throws {
        let root = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["STAXRIP_EBU_TEST_SET"]))
        let tools = try #require(FFmpegTools.discover())
        let manifestURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Docs/EBU-V5-MANIFEST.json")
        let manifest = try JSONDecoder().decode([String:String].self, from: Data(contentsOf: manifestURL))
        var cache: [String:MeterSummary] = [:]
        func measure(_ name: String) async throws -> MeterSummary {
            if let cached = cache[name] { return cached }
            let source = root.appendingPathComponent(name)
            #expect(FileManager.default.fileExists(atPath: source.path), "Required EBU file: \(name)")
            let probe = try await MediaProbe.read(source, tools: tools)
            let count = try #require(probe.streams.first?.channels)
            #expect(count == 1 || count == 2)
            // The official fixture specification supplies the mono/stereo layout,
            // which legacy PCM WAV headers often omit. No surround inference.
            let report = try await MeasuredAnalysis.run(source: source, track: 0, regions: [], tools: tools, declaredLayout: count == 1 ? "mono" : "stereo") { _ in }
            #expect(report.source.sha256 == manifest[name], "Fixture checksum \(name)")
            cache[name] = report.programme
            print("EBU \(name) SHA256=\(report.source.sha256) I=\(report.programme.integrated.display) LRA=\(report.programme.range.display) TP=\(report.programme.truePeak.display)")
            return report.programme
        }
        let integrated: [(String,Double)] = [
            ("seq-3341-1-16bit.wav",-23), ("seq-3341-2-16bit.wav",-33),
            ("seq-3341-3-16bit-v02.wav",-23),("seq-3341-4-16bit-v02.wav",-23),("seq-3341-5-16bit-v02.wav",-23),
            ("seq-3341-7_seq-3342-5-24bit.wav",-23),("seq-3341-2011-8_seq-3342-6-24bit-v02.wav",-23)]
        for (name,target) in integrated { let result = try await measure(name); #expect(abs(try #require(result.integrated.value)-target) <= 0.1, "Integrated \(name)") }
        let ranges: [(String,Double)] = [("seq-3342-1-16bit.wav",10),("seq-3342-2-16bit.wav",5),("seq-3342-3-16bit.wav",20),("seq-3342-4-16bit.wav",15),("seq-3341-7_seq-3342-5-24bit.wav",5),("seq-3341-2011-8_seq-3342-6-24bit-v02.wav",15)]
        for (name,target) in ranges { let result = try await measure(name); #expect(abs(try #require(result.range.value)-target) <= 1, "LRA \(name)") }
        for i in 15...23 {
            let result = try await measure("seq-3341-\(i)-24bit.wav.wav")
            let target = i <= 18 ? -6.0 : (i == 19 ? 3.0 : 0.0)
            let delta = try #require(result.truePeak.value)-target
            #expect(delta >= -0.4 && delta <= 0.2, "True peak case \(i)")
        }
        for name in ["seq-3341-9-24bit.wav"] + (1...20).map({ "seq-3341-10-\($0)-24bit.wav" }) {
            let result = try await measure(name)
            #expect(abs(try #require(result.trace.compactMap(\.shortTerm).max())+23) <= 0.1, "Short term \(name)")
        }
        for name in ["seq-3341-12-24bit.wav"] + (1...20).map({ "seq-3341-13-\($0)-24bit.wav" + ($0 >= 3 ? ".wav" : "") }) {
            let result = try await measure(name)
            #expect(abs(try #require(result.trace.compactMap(\.momentary).max())+23) <= 0.1, "Momentary \(name)")
        }
        for (name,short) in [("seq-3341-11-24bit.wav",true),("seq-3341-14-24bit.wav.wav",false)] {
            let result = try await measure(name)
            let values = result.trace.compactMap { short ? $0.shortTerm : $0.momentary }
            for level in -38 ... -19 { #expect(values.contains { abs($0-Double(level)) <= 0.1 }, "Trajectory \(name) level \(level)") }
        }
        print("Official supported mono/stereo gate completed: \(cache.count) distinct EBU sequences. © EBU. Surround case 6 is outside this slice.")
    }
}
