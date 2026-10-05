import Foundation

struct SessionDocument: Codable, Equatable {
    var format = "staxrip-mac-session"
    var version = 11
    var sourcePath: String?
    var configuration: EncodeConfiguration
    var outputFolder: String
    var outputStem: String
    var jobs: [QueueJob]

    func validated() throws -> SessionDocument {
        guard format == "staxrip-mac-session", (1...11).contains(version) else {
            throw SessionError.invalid("This session version is not supported.")
        }
        guard jobs.count <= 1000 else { throw SessionError.invalid("This session contains too many queue items.") }
        guard version >= 6 || (configuration.externalSubtitle == nil && jobs.allSatisfy { $0.configuration.externalSubtitle == nil }) else {
            throw SessionError.invalid("External subtitle references require session version 6.")
        }
        guard version >= 7 || (configuration.chapterEdits == nil && jobs.allSatisfy { $0.configuration.chapterEdits == nil }) else {
            throw SessionError.invalid("Chapter editing requires session version 7.")
        }
        guard version >= 8 || (configuration.additionalExternalSubtitles == nil && jobs.allSatisfy { $0.configuration.additionalExternalSubtitles == nil }) else {
            throw SessionError.invalid("Multiple external caption tracks require session version 8.")
        }
        guard version >= 9 || ([configuration] + jobs.map(\.configuration)).allSatisfy({ $0.externalCaptions.allSatisfy { $0.playback == nil } }) else {
            throw SessionError.invalid("Caption playback choices require session version 9.")
        }
        guard version >= 10 || ([configuration] + jobs.map(\.configuration)).allSatisfy({ $0.hevcBufferLimits == nil }) else {
            throw SessionError.invalid("HEVC buffer limits require session version 10.")
        }
        guard version >= 11 || ([configuration] + jobs.map(\.configuration)).allSatisfy({ $0.colorMode != DolbyConversionIntent.hdr10Copy && $0.dolbyLossAcknowledgement == nil }) else {
            throw SessionError.invalid("Dolby conversion intent requires session version 11.")
        }
        let chapterCount = (configuration.chapterEdits?.entries.count ?? 0) + jobs.reduce(0) { $0 + ($1.configuration.chapterEdits?.entries.count ?? 0) }
        guard chapterCount <= 10000 else { throw SessionError.invalid("A session can store at most 10000 authored chapter entries across its workspace and queue.") }
        try Self.validate(configuration)
        try Self.validatePath(outputFolder)
        if let path = sourcePath { try Self.validatePath(path) }
        try Self.validateAcknowledgement(configuration, source: sourcePath)
        guard WorkspaceModel.filenameIssue(outputStem) == nil else { throw SessionError.invalid("The output name is invalid.") }
        guard Set(jobs.map(\.id)).count == jobs.count else { throw SessionError.invalid("Queue item IDs must be unique.") }
        var destinations = Set<String>()
        for job in jobs {
            try Self.validate(job.configuration)
            try Self.validateAcknowledgement(job.configuration, source: job.isDemo ? nil : job.source)
            if !job.isDemo { try Self.validatePath(job.source) }
            try Self.validatePath(job.destination)
            let url = URL(fileURLWithPath: job.destination)
            guard url.pathExtension.lowercased() == job.configuration.container.lowercased(),
                  WorkspaceModel.filenameIssue(url.deletingPathExtension().lastPathComponent) == nil else {
                throw SessionError.invalid("A queue output name or extension is invalid.")
            }
            guard destinations.insert(url.standardizedFileURL.path).inserted else {
                throw SessionError.invalid("Queue outputs must have different names.")
            }
            if !job.isDemo && url.standardizedFileURL.path == URL(fileURLWithPath: job.source).standardizedFileURL.path {
                throw SessionError.invalid("A queue output points to its source.")
            }
        }
        return self
    }

    static func validateAcknowledgement(_ config: EncodeConfiguration, source: String?) throws {
        if let acknowledgement = config.dolbyLossAcknowledgement {
            guard let source, URL(fileURLWithPath: source).standardizedFileURL.path == acknowledgement.sourcePath else {
                throw SessionError.invalid("Dolby Vision loss acknowledgement belongs to a different source. Review this source again.")
            }
        }
    }

    private static func validatePath(_ value: String) throws {
        guard value.hasPrefix("/"), !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw SessionError.invalid("Session paths must be absolute local paths.")
        }
    }

    static func validate(_ config: EncodeConfiguration) throws {
        try DolbyConversionIntent.validate(config)
        try config.validateExternalCaptions()
        try config.chapterEdits?.validate()
        if let limits = config.hevcBufferLimits {
            try limits.validate()
            guard config.codec == "HEVC", config.encoder == "x265", config.rate.backend == "Software" else {
                throw SessionError.invalid("HEVC buffer limits require software HEVC. Turn them off before changing codec or engine.")
            }
            guard limits.mode != "Custom" || config.rate.mode != "Target bitrate" || config.rate.bitrate <= limits.maxrate else {
                throw SessionError.invalid("Target bitrate exceeds the custom HEVC peak limit.")
            }
        }
        guard ["SDR", "Preserve static HDR10", DolbyConversionIntent.hdr10Copy].contains(config.colorMode) else {
            throw SessionError.invalid("Unknown video color intent.")
        }
        guard ["Software", "Apple hardware"].contains(config.rate.backend),
              ["Constant quality", "Target bitrate"].contains(config.rate.mode),
              (100...200000).contains(config.rate.bitrate),
              config.rate.backend != "Apple hardware" || (config.codec != "AV1" && config.rate.mode == "Target bitrate") else {
            throw SessionError.invalid("Unsupported encoding engine or video bitrate settings.")
        }
        for selection in [config.audioTracks, config.subtitleTracks] {
            if let selection {
                guard selection.count <= 1000, Set(selection).count == selection.count,
                      selection.allSatisfy({ (0...10000).contains($0) }) else {
                    throw SessionError.invalid("Track selections must contain unique nonnegative stream indices.")
                }
            }
        }
        let picture = config.picture
        guard [picture.cropLeft, picture.cropRight].allSatisfy({ (0...4096).contains($0) && $0 % 2 == 0 }),
              picture.start.isFinite, (0...604800).contains(picture.start),
              picture.end.isFinite, (0...604800).contains(picture.end),
              picture.end == 0 || picture.end > picture.start,
              ["Off", "Flagged frames", "All frames"].contains(picture.deinterlace) else {
            throw SessionError.invalid("Invalid crop, trim range or deinterlacing mode.")
        }
        let encoders = ["AV1": "SVT-AV1", "HEVC": "x265", "H.264": "x264", "Copy original": "copy"]
        guard encoders[config.codec] == config.encoder,
              config.quality.isFinite, (0...51).contains(config.quality),
              ["MKV", "MP4"].contains(config.container),
              ["Thorough", "Balanced", "Fast"].contains(config.speed),
              ["Original", "1920 × 1080", "1280 × 720"].contains(config.resolution),
              (0...240).contains(config.cropTop), (0...240).contains(config.cropBottom),
              config.cropTop % 2 == 0, config.cropBottom % 2 == 0,
              ["AAC", "Opus", "Copy original", "No audio"].contains(config.audio),
              ["128 kb/s", "192 kb/s", "256 kb/s", "320 kb/s"].contains(config.audioBitrate),
              ["Keep embedded tracks", "Remove all subtitles"].contains(config.subtitleMode) else {
            throw SessionError.invalid("The session contains unsupported encoding settings.")
        }
    }

    static func read(from url: URL) throws -> SessionDocument {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 5_000_000 else { throw SessionError.invalid("Session files must be smaller than 5 MB.") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Self.self, from: Data(contentsOf: url)).validated()
    }

    func write(to url: URL) throws {
        _ = try validated()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        guard data.count <= 5_000_000 else { throw SessionError.invalid("Session data exceeds 5 MB.") }
        try data.write(to: url, options: .atomic)
    }
}

enum SessionError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}
