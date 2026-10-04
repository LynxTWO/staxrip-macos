import Foundation
import Testing
@testable import StaxRipMac

struct DolbyEditGeometryTests {
    typealias G = DolbyEditGeometry
    private func input(coded: G.Size = .init(width: 16, height: 10), codec: G.Crop = .none,
                       containerPixels: G.Size? = nil, container: G.Crop = .none,
                       decoder: G.Space = .coded, decoderPixels: G.Size? = nil,
                       metadata: G.Space = .coded, active: G.Crop = .none,
                       user: G.Crop = .none, scaled: G.Size = .init(width: 16, height: 10),
                       padding: G.Crop = .none, aspect: G.Aspect = .init(numerator: 1, denominator: 1),
                       orientation: G.Orientation = .unchanged, scan: G.Scan = .progressive) -> G.Input {
        let visible = G.Size(width: coded.width - codec.left - codec.right,
                             height: coded.height - codec.top - codec.bottom)
        let containerSize = G.Size(width: visible.width - container.left - container.right,
                                   height: visible.height - container.top - container.bottom)
        let actual = decoder == .coded ? coded : decoder == .codecVisible ? visible : containerSize
        return G.Input(orientation: orientation, scan: scan, coded: coded, codecWindow: codec, containerPixels: containerPixels ?? visible,
                       containerCrop: container, decoderPixels: decoderPixels ?? actual,
                       decoderSpace: decoder, metadataSpace: metadata, activeArea: active,
                       userCrop: user, scaledPixels: scaled, padding: padding, sourceAspect: aspect)
    }
    @Test func conformanceWindowAppliedOnceAndOddMetadataRemainsValid() throws {
        let coded = G.Size(width: 176, height: 112), visible = G.Size(width: 162, height: 98)
        let window = G.Crop(left: 0, right: 14, top: 0, bottom: 14)
        let active = G.Crop(left: 3, right: 5, top: 1, bottom: 3)
        let raw = try G.propose(input(coded: coded, codec: window, metadata: .codecVisible,
                                     active: active, scaled: visible))
        let decoded = try G.propose(input(coded: coded, codec: window, decoder: .codecVisible,
                                         metadata: .codecVisible, active: active, scaled: visible))
        #expect(raw.decoderPixelCrop == window)
        #expect(decoded.decoderPixelCrop == .none)
        #expect(raw.croppedPixels == visible && decoded.croppedPixels == visible)
        #expect(raw.activeRegion == decoded.activeRegion)
        #expect(try raw.integerActiveAreaProposal() == active)
        let codedMetadata = try G.propose(input(coded: coded, codec: window,
            active: .init(left: 3, right: 19, top: 1, bottom: 17), scaled: visible))
        #expect(codedMetadata.activeRegion == raw.activeRegion)
    }
    @Test func containerUserCropIntersectionAndPaddingHaveExplicitOrigins() throws {
        let container = G.Crop(left: 2, right: 4, top: 2, bottom: 0)
        let user = G.Crop(left: 2, right: 0, top: 0, bottom: 2)
        let padding = G.Crop(left: 2, right: 4, top: 2, bottom: 0)
        let active = G.Crop(left: 1, right: 3, top: 1, bottom: 1)
        let raw = try G.propose(input(container: container, metadata: .containerVisible, active: active,
            user: user, scaled: .init(width: 16, height: 12), padding: padding))
        #expect(raw.decoderPixelCrop == .init(left: 4, right: 4, top: 2, bottom: 2))
        #expect(raw.croppedPixels == .init(width: 8, height: 6))
        #expect(raw.canvasPixels == .init(width: 22, height: 14))
        #expect(try raw.integerActiveAreaProposal() == .init(left: 2, right: 10, top: 4, bottom: 0))
        let alreadyContainer = try G.propose(input(container: container, decoder: .containerVisible,
            metadata: .containerVisible, active: active, user: user,
            scaled: .init(width: 16, height: 12), padding: padding))
        #expect(alreadyContainer.decoderPixelCrop == user)
        #expect(alreadyContainer.activeRegion == raw.activeRegion)
        let codedArea = try G.propose(input(container: container,
            active: .init(left: 3, right: 7, top: 3, bottom: 1), user: user,
            scaled: .init(width: 16, height: 12), padding: padding))
        #expect(codedArea.activeRegion == raw.activeRegion)
    }
    @Test func fractionalEdgesRefuseSilentIntegerRoundingAndPreserveDisplayShape() throws {
        let result = try G.propose(input(active: .init(left: 3, right: 5, top: 1, bottom: 3),
            user: .init(left: 2, right: 2, top: 0, bottom: 2), scaled: .init(width: 10, height: 6)))
        #expect(result.activeRegion.left.numerator == 5 && result.activeRegion.left.denominator == 6)
        #expect(result.activeRegion.right.numerator == 15 && result.activeRegion.right.denominator == 2)
        #expect(result.activeRegion.top.numerator == 3 && result.activeRegion.top.denominator == 4)
        #expect(result.activeRegion.bottom.numerator == 21 && result.activeRegion.bottom.denominator == 4)
        #expect(result.outputAspect == .init(numerator: 9, denominator: 10))
        #expect(throws: (any Error).self) { try result.integerActiveAreaProposal() }
        let anamorphic = try G.propose(input(user: .init(left: 2, right: 2, top: 0, bottom: 2),
            scaled: .init(width: 24, height: 12), aspect: .init(numerator: 8, denominator: 9)))
        #expect(anamorphic.outputAspect == .init(numerator: 2, denominator: 3))
    }
    @Test func compositeCropDoesNotInventAnIntermediateChromaOperation() throws {
        let result = try G.propose(input(container: .init(left: 0, right: 0, top: 1, bottom: 0),
            metadata: .containerVisible, user: .init(left: 0, right: 0, top: 1, bottom: 0),
            scaled: .init(width: 16, height: 8)))
        #expect(result.decoderPixelCrop == .init(left: 0, right: 0, top: 2, bottom: 0))
        #expect(try result.integerActiveAreaProposal() == .none)
    }
    @Test func unresolvedMalformedAndRemovedRegionsRefuse() {
        let invalid = [
            input(orientation: .unresolved), input(orientation: .transformed),
            input(scan: .unresolved), input(scan: .interlaced),
            input(decoder: .unresolved), input(metadata: .unresolved),
            input(containerPixels: .init(width: 16, height: 9)), // A display ratio is not a pixel raster.
            input(decoderPixels: .init(width: 14, height: 10)),
            input(coded: .init(width: 0, height: 10)),
            input(coded: .init(width: Int.max, height: 10)),
            input(coded: .init(width: 8192, height: 8192)),
            input(active: .init(left: -1, right: 0, top: 0, bottom: 0)),
            input(active: .init(left: 8, right: 8, top: 0, bottom: 0)),
            input(active: .init(left: 12, right: 0, top: 0, bottom: 0),
                  user: .init(left: 0, right: 6, top: 0, bottom: 0)),
            input(user: .init(left: 1, right: 1, top: 0, bottom: 0)),
            input(user: .init(left: 16, right: 0, top: 0, bottom: 0)),
            input(user: .init(left: Int.max, right: 0, top: 0, bottom: 0)),
            input(scaled: .init(width: 15, height: 10)),
            input(padding: .init(left: 1, right: 0, top: 0, bottom: 0)),
            input(padding: .init(left: 8190, right: 0, top: 0, bottom: 0)),
            input(aspect: .init(numerator: 0, denominator: 1)),
            input(aspect: .init(numerator: 1, denominator: 0)),
            input(aspect: .init(numerator: Int.max, denominator: 1)),
        ]
        for candidate in invalid { #expect(throws: (any Error).self) { try G.propose(candidate) } }
    }
    @Test func independentShotRegionsRemainDistinct() throws {
        let scaled = G.Size(width: 32, height: 20)
        let full = try G.propose(input(scaled: scaled))
        let inset = try G.propose(input(active: .init(left: 3, right: 5, top: 1, bottom: 3), scaled: scaled))
        #expect(try full.integerActiveAreaProposal() == .none)
        #expect(try inset.integerActiveAreaProposal() == .init(left: 6, right: 10, top: 2, bottom: 6))
        #expect(full.activeRegion != inset.activeRegion)
    }
    @Test func clippingAndResizeFactsDoNotCertifyBrightness() throws {
        let user = G.Crop(left: 2, right: 2, top: 0, bottom: 2)
        let kept = try G.propose(input(active: .init(left: 3, right: 5, top: 1, bottom: 3),
                                      user: user, scaled: .init(width: 12, height: 8)))
        #expect(!kept.declaredActiveRegionWasClipped && !kept.rasterResizeRequested)
        let cut = try G.propose(input(user: user, scaled: .init(width: 24, height: 16)))
        #expect(cut.declaredActiveRegionWasClipped && cut.rasterResizeRequested)
        let padded = try G.propose(input(padding: .init(left: 2, right: 0, top: 0, bottom: 2)))
        #expect(!padded.declaredActiveRegionWasClipped && !padded.rasterResizeRequested)
    }
    @Test(.enabled(if: FFmpegTools.discover() != nil), .timeLimit(.minutes(1)))
    func actualGeneratedPictureMatchesCompositeCropNearestScaleAndPadding() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("dolby-edit-geometry-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("generated.gray")
        var samples = [UInt8](repeating: 0, count: 16 * 10)
        for y in 1..<7 { for x in 3..<11 { samples[y * 16 + x] = 255 } }
        try Data(samples).write(to: source, options: .withoutOverwriting)
        let original = try Data(contentsOf: source)
        let tools = try #require(FFmpegTools.discover())
        for padding in [G.Crop.none, G.Crop(left: 2, right: 4, top: 2, bottom: 0)] {
            let plan = try G.propose(input(active: .init(left: 3, right: 5, top: 1, bottom: 3),
                user: .init(left: 2, right: 2, top: 0, bottom: 2),
                scaled: .init(width: 24, height: 16), padding: padding))
            let output = root.appendingPathComponent("generated-" + UUID().uuidString + ".gray")
            let crop = plan.decoderPixelCrop
            let filters = "crop=\(plan.croppedPixels.width):\(plan.croppedPixels.height):\(crop.left):\(crop.top),scale=24:16:flags=neighbor,pad=\(plan.canvasPixels.width):\(plan.canvasPixels.height):\(padding.left):\(padding.top):color=black"
            let result = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-nostdin", "-n",
                "-f", "rawvideo", "-pixel_format", "gray", "-video_size", "16x10", "-i", source.path,
                "-vf", filters, "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "gray", output.path])
            try #require(result.status == 0)
            let bytes = [UInt8](try Data(contentsOf: output))
            try #require(bytes.count == plan.canvasPixels.width * plan.canvasPixels.height)
            let offsets = try plan.integerActiveAreaProposal()
            for y in 0..<plan.canvasPixels.height {
                for x in 0..<plan.canvasPixels.width {
                    let inside = x >= offsets.left && x < plan.canvasPixels.width - offsets.right &&
                        y >= offsets.top && y < plan.canvasPixels.height - offsets.bottom
                    #expect(bytes[y * plan.canvasPixels.width + x] == (inside ? 255 : 0))
                }
            }
        }
        #expect(try Data(contentsOf: source) == original)
    }
}
