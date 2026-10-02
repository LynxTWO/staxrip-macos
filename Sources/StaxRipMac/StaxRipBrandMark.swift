import SwiftUI
import AppKit

struct StaxRipBrandMark: View {
    @Environment(\.colorScheme) private var scheme
    private static let light = load("StaxRipBrandLight")
    private static let dark = load("StaxRipBrandDark")
    private static func load(_ name: String) -> NSImage {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"), let image = NSImage(contentsOf: url) else { return NSImage() }
        return image
    }
    var body: some View {
        Image(nsImage: scheme == .dark ? Self.dark : Self.light)
            .resizable().interpolation(.high).scaledToFit()
            .frame(width: 42, height: 42)
            .accessibilityHidden(true) // Adjacent StaxRip text supplies the name once.
    }
}
