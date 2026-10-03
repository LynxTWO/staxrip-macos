import Foundation

/// Nil in EncodeConfiguration preserves older unrestricted recipes.
struct HEVCBufferLimits: Codable, Equatable {
    var mode = "Suggested"
    var tier = "High"
    var maxrate = 100000 // decimal kilobits/second
    var bufsize = 100000 // decimal kilobits, not bytes or bitrate
    func validate() throws {
        guard ["Suggested", "Custom"].contains(mode), ["Main", "High"].contains(tier),
              (1...800000).contains(maxrate), (1...800000).contains(bufsize) else {
            throw SessionError.invalid("Invalid HEVC buffer limits. Use positive peak and buffer values up to 800000, and a supported mode/tier.")
        }
    }
}

struct HEVCBufferRecommendation: Equatable {
    let level: String
    let tier: String
    let maxrate: Int
    let bufsize: Int
    var summary: String { "HEVC level \(level), \(tier) tier · peak \(maxrate) kb/s · buffer \(bufsize) kbit" }
    var parameters: String {
        "vbv-maxrate=\(maxrate):vbv-bufsize=\(bufsize):hrd=1:level-idc=\(level):high-tier=\(tier == "High" ? 1 : 0)"
    }
}

enum HEVCBufferPlanner {
    // Main/Main 10 level limits: published numeric facts, not a quality model.
    // x265 still validates its DPB/CTU requirements and the encoded stream.
    private struct Level {
        let name: String
        let samples: Int64
        let perSecond: Int64
        let mainRate: Int
        let mainBuffer: Int
        let highRate: Int?
    }
    private static let levels: [Level] = [
        .init(name: "1", samples: 36864, perSecond: 552960, mainRate: 128, mainBuffer: 350, highRate: nil),
        .init(name: "2", samples: 122880, perSecond: 3686400, mainRate: 1500, mainBuffer: 1500, highRate: nil),
        .init(name: "2.1", samples: 245760, perSecond: 7372800, mainRate: 3000, mainBuffer: 3000, highRate: nil),
        .init(name: "3", samples: 552960, perSecond: 16588800, mainRate: 6000, mainBuffer: 6000, highRate: nil),
        .init(name: "3.1", samples: 983040, perSecond: 33177600, mainRate: 10000, mainBuffer: 10000, highRate: nil),
        .init(name: "4", samples: 2228224, perSecond: 66846720, mainRate: 12000, mainBuffer: 12000, highRate: 30000),
        .init(name: "4.1", samples: 2228224, perSecond: 133693440, mainRate: 20000, mainBuffer: 20000, highRate: 50000),
        .init(name: "5", samples: 8912896, perSecond: 267386880, mainRate: 25000, mainBuffer: 25000, highRate: 100000),
        .init(name: "5.1", samples: 8912896, perSecond: 534773760, mainRate: 40000, mainBuffer: 40000, highRate: 160000),
        .init(name: "5.2", samples: 8912896, perSecond: 1069547520, mainRate: 60000, mainBuffer: 60000, highRate: 240000),
        .init(name: "6", samples: 35651584, perSecond: 1069547520, mainRate: 60000, mainBuffer: 60000, highRate: 240000),
        .init(name: "6.1", samples: 35651584, perSecond: 2139095040, mainRate: 120000, mainBuffer: 120000, highRate: 480000),
        .init(name: "6.2", samples: 35651584, perSecond: 4278190080, mainRate: 240000, mainBuffer: 240000, highRate: 800000)
    ]

    static func resolve(_ c: EncodeConfiguration, video: MediaProbe.Stream) throws -> HEVCBufferRecommendation? {
        guard let limits = c.hevcBufferLimits else { return nil }
        try limits.validate()
        guard c.codec == "HEVC", c.encoder == "x265", c.rate.backend == "Software" else {
            throw failure("These limits require software HEVC. Turn them off before choosing another codec or engine.")
        }
        let orientation = try SourceOrientation.read(video)
        let width = (orientation.swapsAxes ? video.height : video.width) ?? 0
        let height = (orientation.swapsAxes ? video.width : video.height) ?? 0
        guard (2...16384).contains(width), (2...16384).contains(height) else { throw failure("A bounded source raster is required.") }
        let geometry = try OutputGeometry(width: width - c.picture.cropLeft - c.picture.cropRight,
                                          height: height - c.cropTop - c.cropBottom, resolution: c.resolution)
        // Use the fit box conservatively; the actual proportional fit can be smaller.
        let w = geometry.box?.width ?? geometry.width, h = geometry.box?.height ?? geometry.height
        let rate = try HDRFraction(video.r_frame_rate), average = try HDRFraction(video.avg_frame_rate)
        guard rate == average, rate.numerator > 0, (1...240).contains(rate.value) else {
            throw failure("Matching declared frame rates from 1 to 240 fps are required for this initial level recommendation. Variable or missing cadence needs separate qualification.")
        }
        return try recommend(width: w, height: h, fps: rate.value, limits: limits,
                             target: c.rate.mode == "Target bitrate" ? c.rate.bitrate : nil)
    }

    static func recommend(width: Int, height: Int, fps: Double, limits: HEVCBufferLimits, target: Int? = nil) throws -> HEVCBufferRecommendation {
        try limits.validate()
        guard (2...16384).contains(width), (2...16384).contains(height), fps.isFinite, (1...240).contains(fps),
              target == nil || (100...200000).contains(target!) else { throw failure("Invalid raster, cadence or target bitrate.") }
        if limits.mode == "Custom", let target, target > limits.maxrate {
            throw failure("The target bitrate exceeds your peak limit. Increase the peak or reduce the target.")
        }
        let samples = Int64(width) * Int64(height)
        for level in levels {
            let high = limits.tier == "High" && level.highRate != nil
            let maximum = high ? level.highRate! : level.mainRate
            let buffer = high ? level.highRate! : level.mainBuffer
            guard samples <= level.samples, Double(samples) * fps <= Double(level.perSecond),
                  Double(width * width) <= Double(level.samples) * 8,
                  Double(height * height) <= Double(level.samples) * 8,
                  (target ?? 0) <= maximum else { continue }
            let peak = limits.mode == "Custom" ? limits.maxrate : maximum
            let size = limits.mode == "Custom" ? limits.bufsize : buffer
            guard peak <= maximum, size <= buffer else { continue }
            return HEVCBufferRecommendation(level: level.name, tier: high ? "High" : "Main", maxrate: peak, bufsize: size)
        }
        throw failure("Raster, cadence or manual limits exceed the supported HEVC level/tier table through 6.2. Review the output and limits.")
    }
    private static func failure(_ message: String) -> NativeExportError { .invalid("HEVC buffer limits: " + message) }
}
