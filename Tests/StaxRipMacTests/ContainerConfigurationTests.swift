import Foundation
import Testing
@testable import StaxRipMac

struct ContainerConfigurationTests {
    private func unsigned(_ value: UInt64, width: Int = 4) -> Data {
        Data((0..<width).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }
    private func box(_ type: String, _ bytes: Data, extended: Bool = false) -> Data {
        if extended { return unsigned(1) + Data(type.utf8) + unsigned(UInt64(bytes.count + 16), width: 8) + bytes }
        return unsigned(UInt64(bytes.count + 8)) + Data(type.utf8) + bytes
    }
    private func videoTrack(id: UInt64 = 7, codec: String = "hvc1", configuration: Data = Data([1, 2, 3]),
                            extra: Data = Data(), version: UInt8 = 0, descriptions: UInt64 = 1) -> Data {
        var tkhd = Data(repeating: 0, count: version == 0 ? 12 : 20); tkhd[0] = version; tkhd += unsigned(id); tkhd += Data(repeating: 0, count: 8)
        let hdlr = Data(repeating: 0, count: 8) + Data("vide".utf8)
        let config = box(codec == "av01" ? "av1C" : "hvcC", configuration)
        let entry = box(codec, Data(repeating: 0, count: 78) + config + extra)
        let stsd = box("stsd", unsigned(0) + unsigned(descriptions) + entry)
        return box("trak", box("tkhd", tkhd) + box("mdia", box("hdlr", hdlr) + box("minf", box("stbl", stsd))))
    }
    private func movie(_ tracks: Data, extra: Data = Data()) -> Data {
        box("ftyp", Data("isom".utf8)) + box("moov", tracks + extra, extended: true) + box("mdat", Data([42]))
    }
    private func element(_ id: UInt64, _ payload: Data) -> Data {
        let idWidth = (1...4).first { id < (UInt64(1) << ($0 * 8)) }!
        let sizeWidth = (1...8).first { UInt64(payload.count) < (UInt64(1) << ($0 * 7)) - 1 }!
        return unsigned(id, width: idWidth) + unsigned(UInt64(payload.count) | (UInt64(1) << (sizeWidth * 7)), width: sizeWidth) + payload
    }
    private func mapping(type: UInt64 = 0x68766345, value: UInt64? = nil, extra: Data = Data([4, 5, 6]),
                         fields: Data = Data()) -> Data {
        let number = value.map { element(0x41f0, unsigned($0)) } ?? Data()
        return element(0x41e4, number + element(0x41e7, unsigned(type)) + element(0x41ed, extra) + fields)
    }
    private func track(number: UInt64 = 1, uid: UInt64 = 91, fields: Data = Data()) -> Data {
        element(0xae, element(0xd7, unsigned(number)) + element(0x73c5, unsigned(uid)) + element(0x83, Data([1])) +
                element(0x86, Data("V_MPEGH/ISO/HEVC".utf8)) + element(0x63a2, Data([1, 8, 9])) + fields)
    }
    private func matroska(_ tracks: Data, unknownSegment: Bool = false, extra: Data = Data()) -> Data {
        let header = element(0x1a45dfa3, element(0x4282, Data("matroska".utf8)))
        let content = element(0x1654ae6b, tracks) + extra
        return header + (unknownSegment ? unsigned(0x18538067) + Data([0xff]) + content : element(0x18538067, content))
    }
    @Test func opaqueDolbyAndEnhancementBytesAndIdentitiesSurviveBothContainers() throws {
        let dolby = Data([1, 0, 14, 55, 96, 0, 255, 90])
        let enhancement = Data([1, 222, 173, 190, 239])
        let mp4 = try ContainerConfiguration.parse(movie(videoTrack(extra: box("dvcC", dolby) + box("hvcE", enhancement))))
        let m = try ContainerConfiguration.parse(matroska(track(fields: mapping(extra: enhancement) + mapping(type: 0x64766343, extra: dolby)), unknownSegment: true))
        #expect(mp4.kind == .mp4 && m.kind == .matroska)
        #expect(mp4.videoTracks[0].number == 7 && m.videoTracks[0].number == 1 && m.videoTracks[0].uid == 91)
        #expect(mp4.videoTracks[0].configuration == Data([1, 2, 3]))
        #expect(m.videoTracks[0].configuration == Data([1, 8, 9]))
        #expect(mp4.videoTracks[0].fields.first { $0.type == 0x64766343 }?.bytes == dolby)
        #expect(mp4.videoTracks[0].fields.first { $0.type == 0x68766345 }?.bytes == enhancement)
        #expect(m.videoTracks[0].mappings.first { $0.type == 0x64766343 }?.extra == dolby)
        #expect(m.videoTracks[0].mappings.first { $0.type == 0x68766345 }?.extra == enhancement)
        #expect(m.videoTracks[0].mappings.allSatisfy { $0.value == nil }) // track-only decoder records do not invent frame IDs
        let altered = try ContainerConfiguration.parse(matroska(track(fields: mapping(extra: enhancement + Data([0])) + mapping(type: 0x64766343, extra: dolby))))
        #expect(m.videoTracks != altered.videoTracks)
    }
    @Test func unknownOpaqueFieldsAreCapturedWithoutImplyingAdmission() throws {
        let source = movie(videoTrack(id: 4, codec: "av01", extra: box("zzzz", Data([255, 0, 3])), version: 1))
        let result = try ContainerConfiguration.parse(source)
        #expect(result.videoTracks[0].number == 4 && result.videoTracks[0].codec == "av01")
        #expect(result.videoTracks[0].fields.first { $0.type == 0x7a7a7a7a }?.bytes == Data([255, 0, 3]))
        let unknown = try ContainerConfiguration.parse(matroska(track(fields: mapping(type: 0x12345678, value: 3))))
        #expect(unknown.videoTracks[0].mappings[0].type == 0x12345678)
        #expect(unknown.videoTracks[0].mappings[0].value == 3)
    }
    @Test func duplicateIdentityFieldsAndAmbiguousSampleOwnershipRefuse() throws {
        let cases = [
            movie(videoTrack() + videoTrack()), movie(videoTrack(id: 0)), movie(videoTrack(descriptions: 2)),
            movie(videoTrack(extra: box("hvcC", Data([7])))), movie(videoTrack(), extra: box("mvex", Data())),
            movie(videoTrack(codec: "encv")), movie(videoTrack(configuration: Data())),
            matroska(track() + track()), matroska(track() + track(number: 2)),
            matroska(track(fields: element(0x63a2, Data([0])))),
            matroska(track(fields: mapping() + mapping())),
            matroska(track(fields: mapping(value: 3) + mapping(type: 0x64766343, value: 3))),
            matroska(track(fields: mapping(value: 1))),
            matroska(track(fields: mapping(fields: element(0x41ed, Data([0]))))),
            matroska(track(fields: mapping(fields: element(0x42ff, Data([0]))))),
            matroska(track(fields: element(0x6d80, Data())))
        ]
        for bytes in cases { #expect(throws: (any Error).self) { try ContainerConfiguration.parse(bytes) } }
    }
    @Test func everyTruncationAndUnknownNestedLengthRefuses() throws {
        let bytes = matroska(track(fields: mapping()))
        for count in 0..<bytes.count { #expect(throws: (any Error).self) { try ContainerConfiguration.parse(Data(bytes.prefix(count))) } }
        let invalid = [Data(repeating: 0, count: 32), movie(videoTrack()) + Data([0]),
                       matroska(track(), extra: unsigned(0x1f43b675) + Data([0xff])),
                       matroska(track()) + unsigned(0x18538067) + Data([0xff]),
                       unsigned(1) + Data("moov".utf8) + Data(repeating: 255, count: 8)]
        for bytes in invalid { #expect(throws: (any Error).self) { try ContainerConfiguration.parse(bytes) } }
    }
    @Test func boundedElementsTracksAndPayloadsRefuseWithoutReadingMediaBodies() throws {
        let manyElements = matroska(track(fields: (0..<ContainerConfiguration.maximumElements).reduce(into: Data()) { d, _ in d += element(0xec, Data()) }))
        #expect(throws: ContainerConfiguration.Failure.resourceLimit) { try ContainerConfiguration.parse(manyElements) }
        let manyTracks = (1...257).reduce(into: Data()) { d, id in d += track(number: UInt64(id), uid: UInt64(id)) }
        #expect(throws: ContainerConfiguration.Failure.resourceLimit) { try ContainerConfiguration.parse(matroska(manyTracks)) }
        let oversized = movie(videoTrack(configuration: Data(repeating: 7, count: ContainerConfiguration.maximumPayloadBytes + 1)))
        #expect(throws: ContainerConfiguration.Failure.resourceLimit) { try ContainerConfiguration.parse(oversized) }
    }
    @Test func longMovieClusterTraversalRetainsTheMetadataBoundsAndRejectsLateDuplicateTracks() throws {
        let clusters = (0..<40_000).reduce(into: Data()) { d, _ in d += element(0x1f43b675, Data([0])) }
        let source = matroska(track(fields: mapping()), extra: clusters)
        let expected = try ContainerConfiguration.parse(matroska(track(fields: mapping())))
        #expect(try ContainerConfiguration.parse(source) == expected)
        #expect(throws: ContainerConfiguration.Failure.malformed) {
            try ContainerConfiguration.parse(matroska(track(), extra: clusters + element(0x1654ae6b, track(number: 2, uid: 92))))
        }
        var excessive = Data(capacity: 2 * ContainerConfiguration.maximumSegmentElements)
        for _ in 0..<ContainerConfiguration.maximumSegmentElements { excessive += Data([0xec, 0x80]) }
        #expect(throws: ContainerConfiguration.Failure.resourceLimit) {
            try ContainerConfiguration.parse(matroska(track(), extra: excessive))
        }
    }
    @Test func sparseMovieSkipsLargeMediaPayloadAndFindsLateConfiguration() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("fixture")
        let ftyp = box("ftyp", Data("isom".utf8)); let movie = box("moov", videoTrack())
        let bodyBytes: UInt64 = 1_073_741_824
        let prefix = ftyp + unsigned(1) + Data("mdat".utf8) + unsigned(bodyBytes, width: 8)
        try prefix.write(to: file, options: .withoutOverwriting)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(ftyp.count) + bodyBytes)
        try handle.write(contentsOf: movie); try handle.synchronize()
        let result = try ContainerConfiguration.read(file)
        #expect(result.videoTracks[0].number == 7 && result.videoTracks[0].configuration == Data([1, 2, 3]))
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? UInt64 == UInt64(ftyp.count + movie.count) + bodyBytes)
    }
    @Test func regularFileReaderMatchesMemoryAndRefusesLinksAndDirectories() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("fixture"); let link = root.appendingPathComponent("link")
        let bytes = movie(videoTrack(extra: box("dvcC", Data([1, 0, 14, 55]))))
        try bytes.write(to: file, options: .withoutOverwriting)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        #expect(try ContainerConfiguration.read(file) == ContainerConfiguration.parse(bytes))
        #expect(try Data(contentsOf: file) == bytes)
        #expect(throws: (any Error).self) { try ContainerConfiguration.read(link) }
        #expect(throws: (any Error).self) { try ContainerConfiguration.read(root) }
        #expect(throws: (any Error).self) { try ContainerConfiguration.read(URL(string: "https://example.invalid/media")!) }
    }
}
