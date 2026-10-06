import Foundation
import Testing
@testable import StaxRipMac

@MainActor
struct CaptionPlaybackTests {
    private func configuration() -> EncodeConfiguration {
        var c = EncodeConfiguration(); c.selectCodec("H.264")
        c.externalCaptions = [ExternalSubtitle(path: "/generated/a.srt", playback: .forced),
                              ExternalSubtitle(path: "/generated/b.srt", playback: .defaultAndForced)]
        return c
    }
    private func job(_ c: EncodeConfiguration) -> QueueJob {
        QueueJob(id: UUID(), source: "/generated/source.mkv", isDemo: false, destination: "/generated/output.mkv", configuration: c, created: Date())
    }
    @Test func choicesRoundTripAndOlderVersionsCannotDiscardThem() throws {
        let c = configuration(), item = job(c)
        var session = SessionDocument(configuration: c, outputFolder: "/generated", outputStem: "result", jobs: [item])
        let restored = try JSONDecoder().decode(SessionDocument.self, from: JSONEncoder().encode(session)).validated()
        #expect(restored.version == 12 && restored == session)
        let journal = BatchJournal(jobs: [item], statuses: [:])
        #expect(try JSONDecoder().decode(BatchJournal.self, from: JSONEncoder().encode(journal)).validated().jobs == [item])
        for version in 6...8 {
            session.version = version
            #expect(throws: (any Error).self) { try session.validated() }
            session.configuration.externalCaptions = []
            #expect(throws: (any Error).self) { try session.validated() }
        }
        var legacy = c; legacy.externalCaptions = [ExternalSubtitle(path: "/generated/a.srt")]
        session.configuration = legacy; session.jobs = [job(legacy)]
        for version in 6...8 { session.version = version; _ = try session.validated() }
        for version in 5...7 {
            var old = journal; old.version = version
            #expect(throws: (any Error).self) { try old.validated() }
            old.jobs = [job(legacy)]; _ = try old.validated()
        }
        let encoded = try JSONEncoder().encode(c.externalCaptions[1])
        let malformed = String(decoding: encoded, as: UTF8.self).replacingOccurrences(of: "defaultAndForced", with: "unknown")
        #expect(throws: (any Error).self) { try JSONDecoder().decode(ExternalSubtitle.self, from: Data(malformed.utf8)) }
        let old = Data(#"{"path":"/generated/old.srt","language":"und","title":"Legacy"}"#.utf8)
        #expect(try JSONDecoder().decode(ExternalSubtitle.self, from: old).playback == nil)
        #expect(CustomPreset.recipe(c).externalCaptions.isEmpty)
    }
    @Test func replacementReorderAndUndoRetainIntentButStaleChoicesRefuse() throws {
        var c = configuration()
        let picker = CaptionFileSelection(references: c.externalCaptions, source: "/generated/source.mkv", replacing: 1)
        let result = try picker.applying(URL(fileURLWithPath: "/generated/new.srt"), current: c, source: "/generated/source.mkv")
        #expect(result[1].playback == .defaultAndForced && result[1].path == "/generated/new.srt")
        let model = WorkspaceModel(); model.config = c
        model.config.externalCaptions.reverse(); model.undoSettings()
        #expect(model.config == c)
        model.redoSettings(); #expect(model.config.externalCaptions.map(\.playback) == [.defaultAndForced, .forced])
        c.externalCaptions[1].playback = .optional
        #expect(throws: (any Error).self) { try picker.applying(URL(fileURLWithPath: "/generated/new.srt"), current: c, source: "/generated/source.mkv") }
    }
    @Test func duplicateDefaultsAndMP4HaveExplicitRemedies() throws {
        var c = configuration(); c.externalCaptions[0].playback = .default
        #expect(throws: (any Error).self) { try c.validateExternalCaptions() }
        c = configuration(); c.container = "MP4"
        for choice in CaptionPlayback.allCases {
            c.externalCaptions = [ExternalSubtitle(path: "/generated/a.srt", playback: choice)]
            #expect(throws: (any Error).self) { try SessionDocument.validate(c) }
        }
        c.externalCaptions[0].playback = nil; try SessionDocument.validate(c)
    }
    private func probe(_ dispositions: [[String: Int]?], types: [String] = ["video", "audio", "audio", "subtitle"]) throws -> MediaProbe {
        let streams: [[String: Any]] = dispositions.enumerated().map { index, flags in
            var item: [String: Any] = ["index": index, "codec_type": types[index]]
            if let flags { item["disposition"] = flags }
            return item
        }
        return try JSONDecoder().decode(MediaProbe.self, from: JSONSerialization.data(withJSONObject: ["streams": streams, "format": [:]]))
    }
    @Test func plansPreserveBaselineDefaultsAndVerifyEveryFlag() throws {
        let zero = ["default": 0, "forced": 0], source = try probe([zero, zero, zero, ["default": 1, "forced": 1, "hearing_impaired": 1]])
        var c = configuration()
        func plan(_ c: EncodeConfiguration, _ p: MediaProbe) throws -> CaptionPlaybackPlan? {
            try CaptionPlaybackPlan.make(video: p.streams[0], audio: Array(p.streams[1...2]), embedded: [p.streams[3]], configuration: c)
        }
        let expected = try #require(try plan(c, source))
        #expect(expected.video.map(\.isDefault) == [false])
        #expect(expected.audio.map(\.isDefault) == [true, false])
        #expect(expected.subtitles.map(\.isDefault) == [false, false, true])
        #expect(expected.subtitles.map(\.isForced) == [true, true, true])
        let types = ["video", "audio", "audio", "subtitle", "subtitle", "subtitle"]
        let output = [zero, ["default": 1, "forced": 0], zero, ["default": 0, "forced": 1], ["default": 0, "forced": 1], ["default": 1, "forced": 1]]
        _ = try expected.verify(probe(output, types: types))
        for index in output.indices {
            for key in ["default", "forced"] {
                var altered: [[String: Int]?] = output; altered[index]?[key] = 1 - output[index][key]!
                #expect(throws: (any Error).self) { try expected.verify(probe(altered, types: types)) }
                altered[index]?[key] = nil
                #expect(throws: (any Error).self) { try expected.verify(probe(altered, types: types)) }
            }
        }
        var audioDefault = source.streams.map { $0.disposition }; audioDefault[2]?["default"] = 1
        #expect(try plan(c, probe(audioDefault))?.audio.map(\.isDefault) == [false, true])
        for bad in [nil, ["default": 2, "forced": 0], ["default": 0]] as [[String: Int]?] {
            #expect(throws: (any Error).self) { try plan(c, probe([bad, zero, zero, zero])) }
        }
        c.externalCaptions = [ExternalSubtitle(path: "/generated/a.srt"), ExternalSubtitle(path: "/generated/b.srt")]
        #expect(try plan(c, probe([nil, nil, nil, nil])) == nil)
        c.externalCaptions[0].playback = .optional
        let unmarked = try #require(try plan(c, probe([zero, zero, zero, zero])))
        #expect(unmarked.subtitles.map(\.isDefault) == [true, false, false])
        c.externalCaptions[1].playback = .default
        #expect(try plan(c, source)?.subtitles.map(\.isDefault) == [false, false, true])
    }
}
