import AppKit
import Testing
@testable import StaxRipMac

@MainActor
struct AppPaletteTests {
    private func components(_ color: NSColor, in appearance: NSAppearance) throws -> [Double] {
        var resolved: NSColor?
        appearance.performAsCurrentDrawingAppearance { resolved = color.usingColorSpace(.sRGB) }
        let value = try #require(resolved)
        #expect(value.alphaComponent == 1)
        return [Double(value.redComponent), Double(value.greenComponent), Double(value.blueComponent)]
    }
    private func over(_ foreground: [Double], _ background: [Double], opacity: Double) -> [Double] {
        zip(foreground, background).map { $0 * opacity + $1 * (1 - opacity) }
    }
    private func luminance(_ rgb: [Double]) -> Double {
        let linear = rgb.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return zip(linear, [0.2126, 0.7152, 0.0722]).map(*).reduce(0, +)
    }
    private func contrast(_ a: [Double], _ b: [Double]) -> Double {
        let values = [luminance(a), luminance(b)].sorted()
        return (values[1] + 0.05) / (values[0] + 0.05)
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
    func resolvedActiveTextAndActionPairsMeetReferenceContrast(name: NSAppearance.Name) throws {
        let appearance = try #require(NSAppearance(named: name))
        let dark = name == .darkAqua || name == .accessibilityHighContrastDarkAqua
        let reference = Array(repeating: dark ? 0.12 : 0.93, count: 3)
        let marginSurface = Array(repeating: dark ? 0.22 : 0.90, count: 3)
        let surfaces = [reference, marginSurface, try components(.windowBackgroundColor, in: appearance),
                        try components(.controlBackgroundColor, in: appearance)]
        var minimum = Double.infinity
        for role: AppPalette.Role in [.accent, .warning] {
            let foreground = try components(AppPalette.color(role), in: appearance)
            for surface in surfaces {
                for opacity in [0.0, 0.06, 0.07, 0.08, 0.09, 0.10, 0.12] {
                    let background = over(foreground, surface, opacity: opacity)
                    minimum = min(minimum, contrast(foreground, background))
                    #expect(contrast(foreground, background) >= 7,
                            "Role \(role), surface \(surface), tint \(opacity), appearance \(appearance.name.rawValue)")
                }
            }
        }
        let fill = try components(AppPalette.color(.primaryFill), in: appearance)
        let white = [1.0, 1.0, 1.0]
        #expect(contrast(white, fill) >= 7)
        #expect(contrast(over(white, fill, opacity: 0.85), fill) >= 4.5)
        print("PALETTE_REFERENCE requested=\(name.rawValue) effective=\(appearance.name.rawValue) surfaces=\(surfaces) minimum=\(minimum)")
    }

    @Test func originalFixedAccentFailsLightTextBenchmark() {
        let original = [0.24, 0.73, 0.64]
        #expect(contrast(original, [1, 1, 1]) < 4.5)
        #expect(contrast(original, [0.93, 0.93, 0.93]) < 4.5)
        #expect(contrast(original, [0.12, 0.12, 0.12]) >= 4.5)
    }
}
