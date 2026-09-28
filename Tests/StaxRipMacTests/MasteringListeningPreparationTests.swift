import Foundation
import Testing
@testable import StaxRipMac

// Local-only rights-cleared corpus from Docs/Planning/LISTENING-MANIFEST.md.
// Absence skips this gate; it never constitutes listening acceptance.
struct MasteringListeningPreparationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["STAXRIP_LISTENING_SOURCE"] != nil))
    func prepareSmart() async throws { try await prepare(mode: .smart) }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["STAXRIP_LISTENING_SOURCE"] != nil))
    func prepareNight() async throws { try await prepare(mode: .night) }
    private func prepare(mode: MasterMode) async throws {
        let tools = try #require(FFmpegTools.discover())
        let source = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["STAXRIP_LISTENING_SOURCE"]))
        try #require(try await SourceFingerprint.read(source).sha256 == "7512d492a4d479a6c5ffe5429dce35077aab653bfdc8362a2529a6a4ce323306")
        let folder = source.deletingLastPathComponent().appendingPathComponent("comparison-"+UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: false)
            var settings = MasterSettings(); settings.mode = mode; settings.maximumLRA = mode == .night ? 3 : 11
            settings.target = mode == .night ? -30 : -23
            let fresh = try await MeasuredAnalysis.fresh(source: source,track: 0,regions: [],tools: tools) { _ in }
            let plan = try await GainPlanner.build(fresh,settings: settings)
            let prediction = GainPrediction(energies: fresh.planningEnergies,envelope: plan.envelope)
            print("PLANNER DIAGNOSTIC \(mode.rawValue) predictedI=\(prediction.integrated ?? 0) predictedLow=\(prediction.low ?? 0) predictedHigh=\(prediction.high ?? 0) gainMin=\(plan.minimumDB) gainMax=\(plan.maximumDB)")
            try #require(abs((prediction.integrated ?? 0)-settings.target) <= 0.5,
                         "First plan already misses predicted reference; avoid a known-failing full-film render.")
            try #require((prediction.high ?? 100)-(prediction.low ?? -100) <= settings.maximumLRA+1,
                         "First plan already misses predicted range; avoid a known-failing full-film render.")
            let candidate = try await MasteringEngine.prepare(source: source,track: 0,regions: [],layout: nil,settings: settings,destination: folder.appendingPathComponent(mode.rawValue+".flac"),tools: tools) { phase,_ in print("LISTENING \(mode.rawValue): \(phase)") }
            try await candidate.publish()
            try candidate.verification.save(to: folder.appendingPathComponent(mode.rawValue+".json"))
            print("LISTENING MODE \(mode.rawValue) I=\(candidate.verification.after.integrated.display) LRA=\(candidate.verification.after.range.display) TP=\(candidate.verification.after.truePeak.display) attempts=\(candidate.verification.attempts)")
        print("Local comparison folder: \(folder.path)")
    }
}
