import AppKit
import SwiftUI

/// Text accents and filled actions have different contrast requirements.
/// AppKit resolves these against the drawing appearance, including Increase Contrast.
enum AppPalette {
    enum Role: Sendable { case accent, warning, primaryFill }

    static func color(_ role: Role) -> NSColor {
        NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.accessibilityHighContrastAqua,
                .accessibilityHighContrastDarkAqua, .aqua, .darkAqua])
            let dark = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
            // The base pair also meets our increased-contrast reference target.
            // Some AppKit versions normalize requested high-contrast appearances
            // when the system preference is off; readability must survive that fallback.
            let hex: UInt32
            switch role {
            case .accent:
                hex = dark ? 0xAFFFEE : 0x034236
            case .warning:
                hex = dark ? 0xFFEDCD : 0x633000
            case .primaryFill:
                hex = 0x034236
            }
            return NSColor(srgbRed: Double((hex >> 16) & 255) / 255,
                green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, alpha: 1)
        }
    }
}

extension Color {
    static let accent = Color(nsColor: AppPalette.color(.accent))
    static let warning = Color(nsColor: AppPalette.color(.warning))
    static let primaryActionFill = Color(nsColor: AppPalette.color(.primaryFill))
}

extension View {
    /// Retains the system button's focus, pressed and disabled behavior.
    func primaryAction() -> some View {
        buttonStyle(.borderedProminent).tint(Color.primaryActionFill).foregroundStyle(.white)
    }
}
