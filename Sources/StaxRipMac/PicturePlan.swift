import Foundation

// Both queued exports and still previews consume this ordered picture plan.
struct PicturePlan: Equatable, Sendable {
    let filters: [String]
    let summary: String
    init(_ c: EncodeConfiguration) {
        let p = c.picture
        var result: [String] = []
        if p.deinterlace != "Off" {
            result.append("bwdif=mode=send_frame:parity=auto:deint=\(p.deinterlace == "Flagged frames" ? "interlaced" : "all")")
        }
        if c.cropTop + c.cropBottom + p.cropLeft + p.cropRight > 0 {
            result.append("crop=iw-\(p.cropLeft + p.cropRight):ih-\(c.cropTop + c.cropBottom):\(p.cropLeft):\(c.cropTop)")
        }
        if c.resolution != "Original" {
            let size = c.resolution == "1920 × 1080" ? "1920:1080" : "1280:720"
            result.append("scale=\(size):force_original_aspect_ratio=decrease:force_divisible_by=2")
        }
        filters = result
        var descriptions: [String] = []
        if p.deinterlace != "Off" { descriptions.append("Deinterlace: " + p.deinterlace.lowercased()) }
        if c.cropTop + c.cropBottom + p.cropLeft + p.cropRight > 0 {
            descriptions.append("Crop: top \(c.cropTop), bottom \(c.cropBottom), left \(p.cropLeft), right \(p.cropRight) pixels")
        }
        if c.resolution != "Original" { descriptions.append("Fit within " + c.resolution) }
        summary = descriptions.isEmpty ? "No picture filters" : descriptions.joined(separator: " · ")
    }
    var expression: String { filters.joined(separator: ",") }
}
