import SwiftUI

struct AlpinePreview: View {
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            ZStack {
                LinearGradient(colors: [Color(red: 0.12, green: 0.24, blue: 0.31), Color(red: 0.46, green: 0.60, blue: 0.59), Color(red: 0.85, green: 0.78, blue: 0.61)], startPoint: .top, endPoint: .bottom)
                Circle().fill(Color(red: 1, green: 0.91, blue: 0.71).opacity(0.8))
                    .frame(width: w * 0.10, height: w * 0.10).blur(radius: 1)
                    .position(x: w * 0.73, y: h * 0.27)
                Canvas { context, size in
                    func mountain(_ points: [CGPoint], _ color: Color) {
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: size.height))
                        for point in points { path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height)) }
                        path.addLine(to: CGPoint(x: size.width, y: size.height))
                        path.closeSubpath()
                        context.fill(path, with: .color(color))
                    }
                    mountain([.init(x: 0, y: 0.66), .init(x: 0.16, y: 0.28), .init(x: 0.27, y: 0.49), .init(x: 0.40, y: 0.15), .init(x: 0.55, y: 0.48), .init(x: 0.65, y: 0.32), .init(x: 0.83, y: 0.58), .init(x: 1, y: 0.38)], Color(red: 0.34, green: 0.45, blue: 0.47))
                    var snow = Path()
                    snow.move(to: CGPoint(x: size.width * 0.30, y: size.height * 0.40))
                    for p in [CGPoint(x: 0.40, y: 0.15), .init(x: 0.49, y: 0.36), .init(x: 0.425, y: 0.31), .init(x: 0.40, y: 0.23), .init(x: 0.365, y: 0.36), .init(x: 0.35, y: 0.32)] {
                        snow.addLine(to: CGPoint(x: p.x * size.width, y: p.y * size.height))
                    }
                    snow.closeSubpath()
                    context.fill(snow, with: .color(Color(red: 0.79, green: 0.83, blue: 0.77)))
                    mountain([.init(x: 0, y: 0.58), .init(x: 0.13, y: 0.48), .init(x: 0.33, y: 0.73), .init(x: 0.60, y: 0.50), .init(x: 0.76, y: 0.67), .init(x: 0.94, y: 0.47), .init(x: 1, y: 0.55)], Color(red: 0.15, green: 0.32, blue: 0.34))
                    mountain([.init(x: 0, y: 0.72), .init(x: 0.19, y: 0.83), .init(x: 0.42, y: 0.94), .init(x: 0.68, y: 0.77), .init(x: 0.86, y: 0.79), .init(x: 1, y: 0.65)], Color(red: 0.07, green: 0.23, blue: 0.26))
                    for i in 0..<30 {
                        let x = CGFloat(i) / 29 * size.width
                        let base = size.height * (0.97 + sin(CGFloat(i) * 1.7) * 0.03)
                        let height = size.height * (0.07 + CGFloat((i * 7) % 6) * 0.01)
                        var tree = Path()
                        tree.move(to: .init(x: x, y: base - height))
                        tree.addLine(to: .init(x: x - height * 0.26, y: base))
                        tree.addLine(to: .init(x: x + height * 0.26, y: base))
                        tree.closeSubpath()
                        context.fill(tree, with: .color(Color(red: 0.035, green: 0.15, blue: 0.17)))
                    }
                }
                LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 7) {
                    Spacer()
                    Text("ROOM TO EXPLORE").font(.system(size: 8, weight: .medium)).tracking(3)
                    Text("Alpine escape").font(.system(size: 27, weight: .light, design: .serif))
                }.foregroundStyle(.white.opacity(0.9)).padding(25).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.accessibilityLabel("Illustrated alpine landscape, demo preview")
    }
}
