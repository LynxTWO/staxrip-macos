import Foundation

/// Geometry proposals only. No RPU writing or edited-Dolby admission follows from a result.
/// Coordinates are half-open luma edges; coded, codec-visible and container-visible
/// origins are explicit. Callers must establish those origins independently.
enum DolbyEditGeometry {
    struct Size: Equatable, Sendable {
        let width: Int, height: Int
    }
    struct Crop: Equatable, Sendable {
        let left: Int, right: Int, top: Int, bottom: Int
        static let none = Crop(left: 0, right: 0, top: 0, bottom: 0)
        var values: [Int] { [left, right, top, bottom] }
    }
    enum Space: Equatable, Sendable { case coded, codecVisible, containerVisible, unresolved }
    enum Orientation: Sendable { case unchanged, transformed, unresolved }
    enum Scan: Sendable { case progressive, interlaced, unresolved }
    struct Aspect: Equatable, Sendable {
        let numerator: Int, denominator: Int
    }
    struct Fraction: Equatable, Sendable {
        let numerator: Int64, denominator: Int64
        fileprivate init(_ numerator: Int64, _ denominator: Int64) {
            var a = numerator, b = denominator
            while b != 0 { (a, b) = (b, a % b) }
            self.numerator = numerator / a; self.denominator = denominator / a
        }
        var integer: Int? { denominator == 1 ? Int(numerator) : nil }
    }
    struct Region: Equatable, Sendable {
        let left: Fraction, right: Fraction, top: Fraction, bottom: Fraction
    }
    struct Input: Sendable {
        let orientation: Orientation
        let scan: Scan
        let coded: Size
        let codecWindow: Crop
        // Declared pixel raster must agree with the codec-visible raster in this subset.
        // Display dimensions/physical units/aspect-ratio declarations are not input pixels.
        let containerPixels: Size
        let containerCrop: Crop
        let decoderPixels: Size
        let decoderSpace: Space
        let metadataSpace: Space
        let activeArea: Crop
        let userCrop: Crop
        let scaledPixels: Size
        let padding: Crop
        let sourceAspect: Aspect
    }
    struct Proposal: Equatable, Sendable {
        let decoderPixelCrop: Crop
        let croppedPixels: Size
        let scaledPixels: Size
        let canvasPixels: Size
        let activeRegion: Region
        let outputAspect: Aspect
        let declaredActiveRegionWasClipped: Bool
        let rasterResizeRequested: Bool

        /// Exact luma-offset proposal, never a metadata-write authorization. Fractional
        /// edges require a separate qualified rounding and picture-resampling contract.
        func integerActiveAreaProposal() throws -> Crop {
            guard let l = activeRegion.left.integer, let r = activeRegion.right.integer,
                  let t = activeRegion.top.integer, let b = activeRegion.bottom.integer else {
                throw DolbyEditGeometry.failure("Scaled active-area edges need a qualified rounding policy.")
            }
            return Crop(left: l, right: canvasPixels.width - r,
                        top: t, bottom: canvasPixels.height - b)
        }
    }
    private static func failure(_ message: String) -> NativeExportError {
        .invalid("Dolby edit geometry: " + message)
    }
    private static func validate(_ size: Size) throws {
        guard (1...8192).contains(size.width), (1...8192).contains(size.height),
              size.width * size.height <= 4096 * 4096 else {
            throw failure("Unsupported picture dimensions.")
        }
    }
    private static func validate(_ crop: Crop) throws {
        guard crop.values.allSatisfy({ (0...8191).contains($0) }) else {
            throw failure("Invalid luma offsets.")
        }
    }
    private static func applying(_ crop: Crop, to size: Size) throws -> Size {
        let result = Size(width: size.width - crop.left - crop.right,
                          height: size.height - crop.top - crop.bottom)
        try validate(result); return result
    }
    private static func origin(_ space: Space, codec: Crop, container: Crop) throws -> (Int, Int) {
        switch space {
        case .coded: return (0, 0)
        case .codecVisible: return (codec.left, codec.top)
        case .containerVisible: return (codec.left + container.left, codec.top + container.top)
        case .unresolved: throw failure("The decoder and metadata coordinate origins must be established.")
        }
    }
    static func propose(_ input: Input) throws -> Proposal {
        guard input.orientation == .unchanged, input.scan == .progressive else {
            throw failure("Orientation and progressive sampling must be established; transformed pictures need a separate contract.")
        }
        for size in [input.coded, input.containerPixels, input.decoderPixels, input.scaledPixels] { try validate(size) }
        for crop in [input.codecWindow, input.containerCrop, input.activeArea, input.userCrop, input.padding] { try validate(crop) }
        guard (1...1_000_000).contains(input.sourceAspect.numerator),
              (1...1_000_000).contains(input.sourceAspect.denominator) else {
            throw failure("Sample aspect must be known and bounded.")
        }
        let codecVisible = try applying(input.codecWindow, to: input.coded)
        guard codecVisible == input.containerPixels else {
            throw failure("Declared container pixels disagree with the codec-visible raster.")
        }
        let containerVisible = try applying(input.containerCrop, to: codecVisible)
        let cropped = try applying(input.userCrop, to: containerVisible)
        let decoderSize: Size
        switch input.decoderSpace {
        case .coded: decoderSize = input.coded
        case .codecVisible: decoderSize = codecVisible
        case .containerVisible: decoderSize = containerVisible
        case .unresolved: throw failure("The decoder coordinate origin is unresolved.")
        }
        guard decoderSize == input.decoderPixels else { throw failure("Decoded raster disagrees with its declared coordinate origin.") }
        let decoderOrigin = try origin(input.decoderSpace, codec: input.codecWindow, container: input.containerCrop)
        let cropX = input.codecWindow.left + input.containerCrop.left + input.userCrop.left
        let cropY = input.codecWindow.top + input.containerCrop.top + input.userCrop.top
        let decoderCrop = Crop(left: cropX - decoderOrigin.0,
                               right: decoderSize.width - cropped.width - (cropX - decoderOrigin.0),
                               top: cropY - decoderOrigin.1,
                               bottom: decoderSize.height - cropped.height - (cropY - decoderOrigin.1))
        // One composite pixel crop. Intermediate declaration windows are not separate
        // filter operations. Only the effective decoder crop must preserve this 4:2:0 grid.
        guard decoderCrop.values.allSatisfy({ $0 >= 0 && $0.isMultiple(of: 2) }),
              cropped.width.isMultiple(of: 2), cropped.height.isMultiple(of: 2),
              input.scaledPixels.width.isMultiple(of: 2), input.scaledPixels.height.isMultiple(of: 2),
              input.padding.values.allSatisfy({ $0.isMultiple(of: 2) }) else {
            throw failure("This pixel crop/scale/padding needs a separately qualified chroma-grid policy.")
        }
        let basis: Size
        switch input.metadataSpace {
        case .coded: basis = input.coded
        case .codecVisible: basis = codecVisible
        case .containerVisible: basis = containerVisible
        case .unresolved: throw failure("The metadata coordinate origin is unresolved.")
        }
        _ = try applying(input.activeArea, to: basis)
        let metadataOrigin = try origin(input.metadataSpace, codec: input.codecWindow, container: input.containerCrop)
        let left = max(metadataOrigin.0 + input.activeArea.left, cropX) - cropX
        let right = min(metadataOrigin.0 + basis.width - input.activeArea.right, cropX + cropped.width) - cropX
        let top = max(metadataOrigin.1 + input.activeArea.top, cropY) - cropY
        let bottom = min(metadataOrigin.1 + basis.height - input.activeArea.bottom, cropY + cropped.height) - cropY
        guard left < right, top < bottom else { throw failure("The picture crop removes the declared active region.") }
        let canvas = Size(width: input.scaledPixels.width + input.padding.left + input.padding.right,
                          height: input.scaledPixels.height + input.padding.top + input.padding.bottom)
        try validate(canvas)
        func x(_ edge: Int) -> Fraction {
            Fraction(Int64(edge) * Int64(input.scaledPixels.width) + Int64(input.padding.left) * Int64(cropped.width), Int64(cropped.width))
        }
        func y(_ edge: Int) -> Fraction {
            Fraction(Int64(edge) * Int64(input.scaledPixels.height) + Int64(input.padding.top) * Int64(cropped.height), Int64(cropped.height))
        }
        let aspect = Fraction(Int64(input.sourceAspect.numerator) * Int64(cropped.width) * Int64(input.scaledPixels.height),
                              Int64(input.sourceAspect.denominator) * Int64(cropped.height) * Int64(input.scaledPixels.width))
        return Proposal(decoderPixelCrop: decoderCrop, croppedPixels: cropped,
                        scaledPixels: input.scaledPixels, canvasPixels: canvas,
                        activeRegion: Region(left: x(left), right: x(right), top: y(top), bottom: y(bottom)),
                        outputAspect: Aspect(numerator: Int(aspect.numerator), denominator: Int(aspect.denominator)),
                        declaredActiveRegionWasClipped:
                            metadataOrigin.0 + input.activeArea.left < cropX ||
                            metadataOrigin.0 + basis.width - input.activeArea.right > cropX + cropped.width ||
                            metadataOrigin.1 + input.activeArea.top < cropY ||
                            metadataOrigin.1 + basis.height - input.activeArea.bottom > cropY + cropped.height,
                        rasterResizeRequested: input.scaledPixels != cropped)
    }
}
