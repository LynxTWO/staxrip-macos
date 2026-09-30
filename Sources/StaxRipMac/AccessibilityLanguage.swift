import SwiftUI
import AppKit

/// Short names stay stable; explanations live in optional hints and visible help.
enum AccessibilityLanguage {
    // Spell codec digits in accessibility text so speech does not read them as a cardinal number.
    static func spokenCodecs(_ text: String) -> String {
        text.replacingOccurrences(of: "H.264", with: "H two six four")
            .replacingOccurrences(of: "H.265", with: "H two six five")
            .replacingOccurrences(of: "HDR10", with: "H D R ten")
    }
    static let qualityHint = "Lower values generally improve quality and increase file size. Values are not directly comparable across encoders."
    static func presetHint(_ title: String) -> String {
        switch title {
        case "H.264 Quality": return "Applies video encoding settings for broad playback compatibility. H two six four is also called AVC, or Advanced Video Coding."
        case "Everyday HEVC": return "Applies balanced H two six five video encoding settings. HEVC means High Efficiency Video Coding."
        case "Compact AV1": return "Applies AV1 video encoding settings aimed at smaller files."
        default: return "Applies this encoding configuration."
        }
    }
    static func channel(_ label: String) -> String {
        switch label {
        case "FL": return "Front left"
        case "FR": return "Front right"
        case "FC": return "Front centre"
        default: return label
        }
    }
    static func measurement(_ value: MeterValue, unit: String) -> String {
        guard value.value != nil else { return "Unavailable. \(value.unavailable ?? "No measurement available.")" }
        return "\(value.display) \(unit)"
    }
    @MainActor static func announce(_ message: String) {
        guard let window = NSApp?.mainWindow, window.isVisible else { return }
        NSAccessibility.post(element: window, notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
}

struct EncodingTermsView: View {
    @Environment(\.dismiss) private var dismiss
    private let terms: [(String, String)] = [
        ("H.264 / AVC", "Advanced Video Coding. A video compression format used by the H.264 Quality preset for broad playback compatibility."),
        ("H.265 / HEVC", "High Efficiency Video Coding. The video format used by the Everyday HEVC preset."),
        ("AV1", "A video compression format used by the Compact AV1 preset. Playback support depends on the device and software."),
        ("HDR10", "High dynamic range using Perceptual Quantizer brightness encoding and static mastering metadata. Preserve static HDR10 checks every decoded source and output frame. It does not certify proprietary dynamic metadata or calibrated display appearance."),
        ("CRF", "Constant rate factor. Lower values generally improve quality and increase file size. Numbers are not directly comparable across encoders."),
        ("LUFS", "Loudness units relative to full scale. Integrated loudness describes the overall measured programme. More negative values indicate quieter audio."),
        ("LRA / LU", "Loudness range, expressed in loudness units. Describes variation in loudness; it is not a limit on individual peaks or a guarantee of comfortable listening."),
        ("dBTP / dBFS", "Decibels true peak and decibels relative to full scale. True peak estimates peaks between samples; sample peak measures the stored samples."),
        ("Momentary / short term", "The loudness chart uses 400-millisecond momentary windows and three-second short-term windows. Missing measurements mean insufficient duration or no finite energy."),
        ("Speech intervals", "Passages selected by you, measured separately with reset filters. Music and effects in the passage remain included. This does not detect or isolate dialogue."),
        ("Source fingerprint", "A SHA-256 hash identifies the source file. Matching the file and track does not prove externally edited report measurements are correct."),
        ("Night / Venue", "Experimental processing with linked compression to reduce volume differences. It is not automatic dialogue detection and does not guarantee listening comfort.")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Encoding and loudness terms").font(.title2).accessibilityAddTraits(.isHeader)
            Text("Short explanations for the controls in this app. VoiceOver hints provide context when enabled in your VoiceOver settings.").foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(terms, id: \.0) { term in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(term.0).font(.headline).accessibilityAddTraits(.isHeader)
                                .accessibilityLabel(AccessibilityLanguage.spokenCodecs(term.0))
                            Text(term.1).textSelection(.enabled)
                                .accessibilityLabel(AccessibilityLanguage.spokenCodecs(term.1))
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 560, height: 560)
    }
}
