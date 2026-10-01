// Original StaxRip Mac vector artwork. Run with the system Swift toolchain.
// One geometry source produces editable SVG layers and multi-resolution PNGs.
import AppKit

struct Contour {
    enum Command { case move(Double, Double), line(Double, Double), curve(Double, Double, Double, Double, Double, Double), close }
    let commands: [Command]
    var path: CGPath {
        let p = CGMutablePath()
        for c in commands {
            switch c {
            case .move(let x, let y): p.move(to: CGPoint(x: x, y: y))
            case .line(let x, let y): p.addLine(to: CGPoint(x: x, y: y))
            case .curve(let x1, let y1, let x2, let y2, let x, let y):
                p.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
            case .close: p.closeSubpath()
            }
        }
        return p
    }
    var svg: String {
        commands.map { c in
            switch c {
            case .move(let x, let y): return "M\(x),\(y)"
            case .line(let x, let y): return "L\(x),\(y)"
            case .curve(let a, let b, let c, let d, let e, let f): return "C\(a),\(b) \(c),\(d) \(e),\(f)"
            case .close: return "Z"
            }
        }.joined(separator: " ")
    }
    static func rounded(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) -> Self {
        let k = r * 0.5522847498
        return Self(commands: [.move(x+r,y), .line(x+w-r,y), .curve(x+w-r+k,y,x+w,y+r-k,x+w,y+r),
            .line(x+w,y+h-r), .curve(x+w,y+h-r+k,x+w-r+k,y+h,x+w-r,y+h), .line(x+r,y+h),
            .curve(x+r-k,y+h,x,y+h-r+k,x,y+h-r), .line(x,y+r), .curve(x,y+r-k,x+r-k,y,x+r,y), .close])
    }
    static func polygon(_ points: [(Double, Double)]) -> Self {
        Self(commands: [.move(points[0].0, points[0].1)] + points.dropFirst().map { .line($0.0,$0.1) } + [.close])
    }
}
struct Layer {
    let name: String
    let contour: Contour
    let top: String
    let bottom: String
    var clip: Contour? = nil
    var rotation: Double = 0
    var shadow = true
}
func color(_ hex: String) -> CGColor {
    let n = UInt32(hex, radix: 16)!
    return CGColor(red: Double((n >> 16)&255)/255, green: Double((n >> 8)&255)/255, blue: Double(n&255)/255, alpha: 1)
}
func layers(_ appearance: String) -> [Layer] {
    let mono = appearance == "mono", dark = appearance == "dark"
    let board = Contour.rounded(188, 408, 624, 390, 52)
    let clap = Contour.rounded(188, 300, 624, 108, 23)
    var result = [
        Layer(name: "01-Rear-frame", contour: .rounded(258, 334, 588, 400, 54), top: mono ? "9C9C9C" : "5CE4C6", bottom: mono ? "646464" : "198D92"),
        Layer(name: "02-Middle-frame", contour: .rounded(222, 370, 608, 400, 54), top: mono ? "DADADA" : "B3FFF1", bottom: mono ? "969696" : "47B8B4"),
        Layer(name: "03-Slate", contour: board, top: mono ? "F7F7F7" : (dark ? "8DBCC3" : "F0FFFA"), bottom: dark ? "3E737F" : (mono ? "BEBEBE" : "9ACED2")),
        Layer(name: "04-Clapper", contour: clap, top: mono ? "F7F7F7" : "F4FFFB", bottom: mono ? "C6C6C6" : "AFE5DF", rotation: -12)
    ]
    // Three broad diagonal cuts read as a clapperboard even at small Dock sizes.
    for (i, x) in [240.0, 438.0, 636.0].enumerated() {
        result.append(Layer(name: "05-Stripe-\(i)", contour: .polygon([(x,300),(x+98,300),(x+170,408),(x+72,408)]),
            top: mono ? "343434" : "154756", bottom: mono ? "191919" : "0A2B38", clip: clap, rotation: -12, shadow: false))
    }
    // A continuous ribbon of frames forms the S; broad geometry avoids tiny lettering.
    let ribbon = Contour(commands: [.move(658,474), .line(407,474), .curve(329,474,320,586,400,597),
        .line(578,619), .curve(612,623,610,654,577,654), .line(350,654), .line(326,720),
        .line(582,720), .curve(681,720,697,578,591,565), .line(419,544),
        .curve(398,541,400,534,418,534), .line(634,534), .close])
    result.append(Layer(name: "06-Frame-ribbon", contour: ribbon, top: mono ? "454545" : "216577", bottom: mono ? "151515" : "083A4B", shadow: false))
    return result
}
let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".build/icons", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func render(_ appearance: String, size: Int) throws {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size*4,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.translateBy(x: 0, y: CGFloat(size)); context.scaleBy(x: Double(size)/1024, y: -Double(size)/1024)
    func draw(_ layer: Layer) {
        context.saveGState()
        if layer.rotation != 0 {
            context.translateBy(x: 188, y: 408); context.rotate(by: layer.rotation * .pi/180); context.translateBy(x: -188, y: -408)
        }
        if let clip = layer.clip { context.addPath(clip.path); context.clip() }
        if layer.shadow {
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: 12), blur: 20, color: CGColor(gray: 0, alpha: 0.25))
            context.addPath(layer.contour.path); context.setFillColor(color(layer.bottom)); context.fillPath()
            context.restoreGState()
        }
        context.addPath(layer.contour.path); context.clip()
        let gradient = CGGradient(colorsSpace: space, colors: [color(layer.top),color(layer.bottom)] as CFArray, locations: [0,1])!
        let box = layer.contour.path.boundingBoxOfPath
        context.drawLinearGradient(gradient, start: CGPoint(x: box.midX, y: box.minY), end: CGPoint(x: box.midX,y: box.maxY), options: [.drawsBeforeStartLocation,.drawsAfterEndLocation])
        context.restoreGState()
    }
    draw(Layer(name: "Background", contour: .rounded(64,64,896,896,196),
        top: appearance == "mono" ? "3C3C3C" : (appearance == "dark" ? "152A34" : "174A5D"),
        bottom: appearance == "mono" ? "141414" : "071A24"))
    layers(appearance).forEach(draw)
    let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(appearance)-\(size).png"))
}
for appearance in ["default", "dark", "mono"] {
    let folder = output.appendingPathComponent(appearance, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for layer in layers(appearance) {
        let clip = layer.clip.map { "<clipPath id=\"clip\"><path d=\"\($0.svg)\"/></clipPath>" } ?? ""
        let clipAttribute = layer.clip == nil ? "" : " clip-path=\"url(#clip)\""
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
        <defs><linearGradient id="fill" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#\(layer.top)"/><stop offset="1" stop-color="#\(layer.bottom)"/></linearGradient>\(clip)</defs>
        <g transform="rotate(\(layer.rotation) 188 408)"\(clipAttribute)><path d="\(layer.contour.svg)" fill="url(#fill)"/></g>
        </svg>
        """
        try svg.write(to: folder.appendingPathComponent(layer.name + ".svg"), atomically: true, encoding: .utf8)
    }
    for size in [16,32,64,128,256,512,1024] { try render(appearance, size: size) }
}
print("Generated original vector layers and fallback renders in \(output.lastPathComponent)")
