import Foundation
import Testing
@testable import StaxRipMac

/// Local research export, never an output-acceptance or listening-quality gate.
struct MasteringPlannerDiagnosticsTests {
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
