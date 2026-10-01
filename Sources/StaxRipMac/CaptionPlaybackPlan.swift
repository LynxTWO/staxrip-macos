import Foundation

/// Container hints only; a player's settings still determine what is displayed.
enum CaptionPlayback: String, Codable, CaseIterable, Sendable {
    case optional, `default`, forced, defaultAndForced
    var isDefault: Bool { self == .default || self == .defaultAndForced }
    var isForced: Bool { self == .forced || self == .defaultAndForced }
    var label: String {
        switch self {
        case .optional: "Optional"
        case .default: "Default"
        case .forced: "Forced"
        case .defaultAndForced: "Default and forced"
        }
    }
}

struct CaptionPlaybackPlan: Sendable {
    struct Flags: Equatable, Sendable {
        var isDefault: Bool
        let isForced: Bool
        init(isDefault: Bool = false, isForced: Bool = false) {
            self.isDefault = isDefault; self.isForced = isForced
        }
        init(_ stream: MediaProbe.Stream) throws {
            guard let d = stream.disposition?["default"], let f = stream.disposition?["forced"],
                  [0, 1].contains(d), [0, 1].contains(f) else {
                throw SubRipDocument.failure("Cannot read default and forced flags for stream \(stream.index). Choose Automatic for added captions or use a source with readable track flags.")
            }
            self.init(isDefault: d == 1, isForced: f == 1)
        }
        var argument: String { (isDefault ? "+default" : "-default") + (isForced ? "+forced" : "-forced") }
    }
    let video: [Flags]
    let audio: [Flags]
    let subtitles: [Flags]

    static func make(video: MediaProbe.Stream, audio: [MediaProbe.Stream], embedded: [MediaProbe.Stream],
                     configuration: EncodeConfiguration) throws -> Self? {
        let references = configuration.externalCaptions
        guard references.contains(where: { $0.playback != nil }) else { return nil }
        try configuration.validateExternalCaptions()
        // Explicit dispositions suppress FFmpeg's automatic defaults for every
        // stream type. Recreate the prior result before applying caption intent.
        func automatic(_ flags: [Flags]) -> [Flags] {
            var result = flags
            if result.count > 1 && !result.contains(where: \.isDefault) { result[0].isDefault = true }
            return result
        }
        let v = [try Flags(video)], a = automatic(try audio.map(Flags.init))
        var s = automatic(try embedded.map(Flags.init) + references.map { _ in Flags() })
        let chosenDefault = references.firstIndex { $0.playback?.isDefault == true }
        if chosenDefault != nil { for i in s.indices { s[i].isDefault = false } }
        for (index, reference) in references.enumerated() {
            if let choice = reference.playback {
                s[embedded.count + index] = Flags(isDefault: choice.isDefault, isForced: choice.isForced)
            }
        }
        return Self(video: v, audio: a, subtitles: s)
    }

    var arguments: [String] {
        [("v", video), ("a", audio), ("s", subtitles)].flatMap { type, flags in
            flags.enumerated().flatMap { index, value in ["-disposition:\(type):\(index)", value.argument] }
        } + ["-default_mode", "passthrough"]
    }
    func verify(_ probe: MediaProbe) throws -> String {
        for (type, actual, expected) in [
            ("video", probe.video.map { [$0] } ?? [], video),
            ("audio", probe.streams.filter { $0.codec_type == "audio" }, audio),
            ("caption", probe.streams.filter { $0.codec_type == "subtitle" }, subtitles)
        ] {
            guard actual.count == expected.count else {
                throw SubRipDocument.failure("The output \(type) track count changed while verifying playback flags. Nothing published.")
            }
            for (index, stream) in actual.enumerated() {
                guard let d = stream.disposition?["default"], let f = stream.disposition?["forced"],
                      d == (expected[index].isDefault ? 1 : 0), f == (expected[index].isForced ? 1 : 0) else {
                    throw SubRipDocument.failure("The output \(type) track \(index + 1) has unexpected default or forced playback flags. Nothing published.")
                }
            }
        }
        return "Verified caption playback flags and retained audio/video defaults"
    }
}
