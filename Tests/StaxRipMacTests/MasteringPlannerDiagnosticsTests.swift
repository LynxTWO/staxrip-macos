import Foundation
import Testing
@testable import StaxRipMac

/// Local research export, never an output-acceptance or listening-quality gate.
struct MasteringPlannerDiagnosticsTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["STAXRIP_RESEARCH_ENVELOPES"] != nil))
    func verifyLocalResearchEnvelopesAgainstDecodedFilm() async throws {
        let environment = ProcessInfo.processInfo.environment
        let source = URL(fileURLWithPath: try #require(environment["STAXRIP_LISTENING_SOURCE"]))
        let file = URL(fileURLWithPath: try #require(environment["STAXRIP_RESEARCH_ENVELOPES"]))
        let fingerprint = try await SourceFingerprint.read(source)
        try #require(fingerprint.sha256 == "7512d492a4d479a6c5ffe5429dce35077aab653bfdc8362a2529a6a4ce323306")
        let envelopes = try JSONDecoder().decode([String: [Double]].self,from: Data(contentsOf: file))
        let tools = try #require(FFmpegTools.discover())
        let fresh = try await MeasuredAnalysis.fresh(source: source,track: 0,regions: [],tools: tools) { _ in }
        let folder = source.deletingLastPathComponent().appendingPathComponent("research-"+UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: false)
        var retain = false
        defer { if !retain { try? FileManager.default.removeItem(at: folder) } }
        let raw = folder.appendingPathComponent("source.f64")
        try await MasteringEngine.runTool(tools,["-i",source.path,"-c:a","pcm_f64le","-f","f64le",raw.path])
        for mode in MasterMode.allCases {
            let envelope = try #require(envelopes[mode == .smart ? "smart" : "night"])
            try #require(envelope.count == fresh.planningEnergies.count+1)
            try #require(envelope.allSatisfy { $0.isFinite && (-36...12).contains($0) })
            var settings = MasterSettings(); settings.mode = mode
            settings.target = mode == .smart ? -23 : -30; settings.maximumLRA = mode == .smart ? 11 : 3
            let plan = GainPlan(analysis: fresh,settings: settings,baseDB: settings.target-(try #require(fresh.report.programme.integrated.value)),
                                dynamic: true,envelope: envelope,minimumDB: envelope.min()!,maximumDB: envelope.max()!)
            let rendered = folder.appendingPathComponent(mode.rawValue+".f64")
            let output = folder.appendingPathComponent(mode.rawValue+".flac")
            try LinkedRenderer.render(raw: raw,to: rendered,plan: plan)
            try await MasteringEngine.encode(raw: rendered,output: output,rate: plan.rate,channels: 2,dynamic: true,tools: tools)
            let after = try await MeasuredAnalysis.fresh(source: output,track: 0,regions: [],tools: tools) { _ in }
            let independent = try await MasteringEngine.independent(output,tools: tools)
            let failures = MasteringEngine.failures(after,plan: plan,independent: independent)
            print("RESEARCH RENDER \(mode) I=\(after.report.programme.integrated.display) LRA=\(after.report.programme.range.display) TP=\(after.report.programme.truePeak.display) failures=\(failures)")
            try #require(failures.isEmpty)
            try FileManager.default.removeItem(at: rendered)
        }
        try #require(try await SourceFingerprint.read(source) == fingerprint)
        try FileManager.default.removeItem(at: raw)
        // Research files only. No MasterCandidate, product receipt or publication API.
        retain = true
        print("Numerically verified research audio, not listening acceptance: \(folder.path)")
    }
    private struct Snapshot: Encodable {
        let energies: [Double]
        let trace: [LoudnessPoint]
        let sourceIntegrated: Double
        let smart: [Double]
        let night: [Double]
        let smartPrediction: [Double]
        let nightPrediction: [Double]
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["STAXRIP_PLANNER_DIAGNOSTICS"] != nil))
    func exportLicensedFilmPlanningInputs() async throws {
        let environment = ProcessInfo.processInfo.environment
        let source = URL(fileURLWithPath: try #require(environment["STAXRIP_LISTENING_SOURCE"]))
        let destination = URL(fileURLWithPath: try #require(environment["STAXRIP_PLANNER_DIAGNOSTICS"]))
        try #require(try await SourceFingerprint.read(source).sha256 == "7512d492a4d479a6c5ffe5429dce35077aab653bfdc8362a2529a6a4ce323306")
        let tools = try #require(FFmpegTools.discover())
        let fresh = try await MeasuredAnalysis.fresh(source: source, track: 0, regions: [], tools: tools) { _ in }
        var smart = MasterSettings(); smart.target = -23; smart.maximumLRA = 11
        var night = MasterSettings(); night.mode = .night; night.target = -30; night.maximumLRA = 3
        let smartPlan = try await GainPlanner.build(fresh, settings: smart)
        let nightPlan = try await GainPlanner.build(fresh, settings: night)
        func predicted(_ plan: GainPlan) throws -> [Double] {
            let value = GainPrediction(energies: fresh.planningEnergies, envelope: plan.envelope)
            return [try #require(value.integrated), try #require(value.low), try #require(value.high)]
        }
        let snapshot = Snapshot(energies: fresh.planningEnergies, trace: fresh.report.programme.trace,
                                sourceIntegrated: try #require(fresh.report.programme.integrated.value),
                                smart: smartPlan.envelope, night: nightPlan.envelope,
                                smartPrediction: try predicted(smartPlan), nightPrediction: try predicted(nightPlan))
        // Explicit local destination; no media, paths or derived timelines enter Git/CI.
        try JSONEncoder().encode(snapshot).write(to: destination, options: .withoutOverwriting)
    }
}
