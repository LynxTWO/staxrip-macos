import Foundation

struct ChannelLoudness: Identifiable {
    let index: Int
    let label: String
    let report: LoudnessReport
    var id: Int { index }
}

struct DialogueSelection: Equatable {
    var start = 0.0
    var end = 30.0
}

enum AudioAudit {
    static func channels(source: URL, track: Int, tools: FFmpegTools) async throws -> [ChannelLoudness] {
        let probe = try await MediaProbe.read(source, tools: tools)
        guard let stream = probe.streams.first(where: { $0.index == track && $0.codec_type == "audio" }),
              let count = stream.channels, (1...8).contains(count) else {
            throw NativeExportError.invalid("Channel audit supports tracks with one to eight decoded channels.")
        }
        let layouts = ["mono": ["FC"], "stereo": ["FL", "FR"], "5.1": ["FL", "FR", "FC", "LFE", "BL", "BR"],
                       "5.1(side)": ["FL", "FR", "FC", "LFE", "SL", "SR"], "7.1": ["FL", "FR", "FC", "LFE", "BL", "BR", "SL", "SR"]]
        let names = layouts[stream.channel_layout ?? ""]
        var results: [ChannelLoudness] = []
        for index in 0..<count {
            try Task.checkCancellation()
            let label = names?.count == count ? names![index] : "Channel \(index + 1) (speaker unknown)"
            let report = try await AudioEngine.analyze(source: source, track: track, tools: tools,
                                                     filter: "pan=mono|c0=c\(index),loudnorm=print_format=json")
            results.append(ChannelLoudness(index: index, label: label, report: report))
        }
        return results
    }

    static func dialogue(source: URL, track: Int, selection: DialogueSelection, tools: FFmpegTools) async throws -> LoudnessReport {
        let probe = try await MediaProbe.read(source, tools: tools)
        guard selection.start.isFinite, selection.end.isFinite, selection.start >= 0,
              selection.end - selection.start >= 3, selection.end <= probe.seconds else {
            throw NativeExportError.invalid("Select at least three seconds of speech within the source. About 30 seconds of clean dialogue is preferable.")
        }
        // The user identifies dialogue; neither tags nor a centre-channel assumption classify speech.
        return try await AudioEngine.analyze(source: source, track: track, tools: tools,
                                             filter: "atrim=start=\(selection.start):end=\(selection.end),asetpts=PTS-STARTPTS,loudnorm=print_format=json")
    }
}
