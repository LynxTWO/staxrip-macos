import Foundation
import Testing
@testable import StaxRipMac

// Local-only rights-cleared corpus from Docs/Planning/LISTENING-MANIFEST.md.
// Absence skips this gate; it never constitutes listening acceptance.
struct MasteringListeningPreparationTests {
    private struct ListeningManifest: Decodable {
        struct Group: Decodable {
            struct Option: Decodable { let label: String; let sha256: String }
            let number: Int
            let frames: Int64
            let matchedTargetLUFS: Double
            let options: [Option]
        }
        let excerpts: [Group]
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["STAXRIP_LISTENING_PACK"] != nil))
    func independentMeterVerifiesConcealedListeningPack() async throws {
        let folder = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["STAXRIP_LISTENING_PACK"]))
        let manifest = try JSONDecoder().decode(ListeningManifest.self,from: Data(contentsOf: folder.appendingPathComponent("review-key/manifest.json")))
        try #require(manifest.excerpts.count == 6 && Set(manifest.excerpts.map(\.number)) == Set(1...6))
        let tools = try #require(FFmpegTools.discover())
        var passed = true
        var results = [[String: Any]]()
        for group in manifest.excerpts {
            try #require(group.frames == 2160000 && Set(group.options.map(\.label)) == Set(["A","B","C","D","E"]) && group.options.count == 5)
            var readings = [Double]()
            for option in group.options {
                let file = folder.appendingPathComponent(String(format: "%02d",group.number)).appendingPathComponent(option.label+".flac")
                let fresh = try await MeasuredAnalysis.fresh(source: file,track: 0,regions: [],tools: tools) { _ in }
                try #require(fresh.report.source.sha256 == option.sha256)
                try #require(fresh.report.programme.frames == group.frames && fresh.report.sampleRate == 48000 && fresh.report.channelLabels == ["FL","FR"])
                let value = try #require(fresh.report.programme.integrated.value)
                #expect(abs(value-group.matchedTargetLUFS) <= 0.15)
                passed = passed && abs(value-group.matchedTargetLUFS) <= 0.15
                print("INDEPENDENT LISTENING OPTION \(group.number) \(option.label) integratedLUFS=\(value)")
                try #require((try #require(fresh.report.programme.truePeak.value)) <= -1)
                readings.append(value)
            }
            let spread = readings.max()!-readings.min()!
            #expect(spread <= 0.2)
            passed = passed && spread <= 0.2
            results.append(["group": group.number,"integratedLUFS": readings,"spreadLU": spread])
            print("INDEPENDENT LISTENING GROUP \(group.number) levelSpreadLU=\(spread)")
        }
        try #require(passed)
        let identity = try await SourceFingerprint.read(folder.appendingPathComponent("review-key/manifest.json"))
        let data = try JSONSerialization.data(withJSONObject: ["status":"passed","manifestSHA256":identity.sha256,
            "meter":StreamingLoudness.algorithm,"groups":results],options: [.sortedKeys])
        let receipt = folder.appendingPathComponent("INDEPENDENT-VERIFIED.json")
        if FileManager.default.fileExists(atPath: receipt.path) {
            try #require(Data(contentsOf: receipt) == data)
        } else { try data.write(to: receipt,options: .withoutOverwriting) }
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["STAXRIP_LISTENING_SOURCE"] != nil))
    func prepareSmart() async throws { try await prepare(mode: .smart) }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["STAXRIP_LISTENING_SOURCE"] != nil))
    func prepareNight() async throws { try await prepare(mode: .night) }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["STAXRIP_LISTENING_ALTERNATIVES"] == "1"))
    func prepareExplicitAlternativeListeningSettings() async throws {
        try await prepare(mode: .smart, maximumLRA: 20)
        try await prepare(mode: .night, maximumLRA: 11)
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["STAXRIP_LISTENING_BASELINE"] == "1"))
    func prepareLegacyNightListeningBaseline() async throws {
        let tools = try #require(FFmpegTools.discover())
        let source = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["STAXRIP_LISTENING_SOURCE"]))
        let fingerprint = try await SourceFingerprint.read(source)
        try #require(fingerprint.sha256 == "7512d492a4d479a6c5ffe5429dce35077aab653bfdc8362a2529a6a4ce323306")
        let folder = source.deletingLastPathComponent().appendingPathComponent("legacy-"+UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: false)
        var retained = false
        defer { if !retained { try? FileManager.default.removeItem(at: folder) } }
        var settings = AudioSettings(); settings.normalize = true; settings.loudnessMode = "Night / Venue"
        settings.targetLUFS = -30; settings.targetLRA = 20
        let output = folder.appendingPathComponent("LegacyNight.flac")
        try await AudioEngine.export(source: source,track: 0,destination: output,settings: settings,tools: tools) { _ in }
        let after = try await MeasuredAnalysis.fresh(source: output,track: 0,regions: [],tools: tools) { _ in }
        let independent = try await MasteringEngine.independent(output,tools: tools)
        try #require(abs((try #require(after.report.programme.integrated.value))+30) <= 0.5)
        try #require((try #require(after.report.programme.truePeak.value)) <= -1 && independent.truePeak <= -1)
        try #require((try #require(after.report.programme.range.value)) <= 21)
        try #require(try await SourceFingerprint.read(source) == fingerprint)
        try after.report.save(to: folder.appendingPathComponent("LegacyNight-analysis.json"))
        retained = true
        print("LEGACY LISTENING I=\(after.report.programme.integrated.display) LRA=\(after.report.programme.range.display) TP=\(after.report.programme.truePeak.display) folder=\(folder.path)")
    }
    private func prepare(mode: MasterMode, maximumLRA: Double? = nil) async throws {
        let tools = try #require(FFmpegTools.discover())
        let source = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["STAXRIP_LISTENING_SOURCE"]))
        try #require(try await SourceFingerprint.read(source).sha256 == "7512d492a4d479a6c5ffe5429dce35077aab653bfdc8362a2529a6a4ce323306")
        let folder = source.deletingLastPathComponent().appendingPathComponent("comparison-"+UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: false)
        var published = false
        defer { if !published { try? FileManager.default.removeItem(at: folder) } }
            var settings = MasterSettings(); settings.mode = mode; settings.maximumLRA = mode == .night ? 3 : 11
            if let maximumLRA { settings.maximumLRA = maximumLRA }
            settings.target = mode == .night ? -30 : -23
            print("EXPLICIT LISTENING REQUEST \(mode.rawValue) target=\(settings.target) maximumLRA=\(settings.maximumLRA); no fallback or default change")
            let fresh = try await MeasuredAnalysis.fresh(source: source,track: 0,regions: [],tools: tools) { _ in }
            let plan = try await GainPlanner.build(fresh,settings: settings)
            let prediction = GainPrediction(energies: fresh.planningEnergies,envelope: plan.envelope)
            print("PLANNER DIAGNOSTIC \(mode.rawValue) predictedI=\(prediction.integrated ?? 0) predictedLow=\(prediction.low ?? 0) predictedHigh=\(prediction.high ?? 0) gainMin=\(plan.minimumDB) gainMax=\(plan.maximumDB)")
            if maximumLRA == nil {
            try #require(abs((prediction.integrated ?? 0)-settings.target) <= 0.5,
                         "First plan already misses predicted reference; avoid a known-failing full-film render.")
            try #require((prediction.high ?? 100)-(prediction.low ?? -100) <= settings.maximumLRA+1,
                         "First plan already misses predicted range; avoid a known-failing full-film render.")
            }
            let candidate = try await MasteringEngine.prepare(source: source,track: 0,regions: [],layout: nil,settings: settings,destination: folder.appendingPathComponent(mode.rawValue+".flac"),tools: tools) { phase,_ in print("LISTENING \(mode.rawValue): \(phase)") }
            try await candidate.publish()
            published = true
            try candidate.verification.save(to: folder.appendingPathComponent(mode.rawValue+".json"))
            print("LISTENING MODE \(mode.rawValue) I=\(candidate.verification.after.integrated.display) LRA=\(candidate.verification.after.range.display) TP=\(candidate.verification.after.truePeak.display) attempts=\(candidate.verification.attempts)")
        print("Local comparison folder: \(folder.path)")
    }
}
