import Foundation
import Darwin

// Structural capture only. These records do not authorize HDR copying, decode
// enhancement pictures, or prove that per-packet additions are preserved.
struct ContainerConfiguration: Equatable, Sendable {
    enum Kind: String, Sendable { case mp4, matroska }
    struct Field: Equatable, Sendable {
        let type: UInt64
        let bytes: Data
    }
    struct Mapping: Equatable, Sendable {
        let value: UInt64?
        let type: UInt64
        let name: Data?
        let extra: Data?
    }
    struct Track: Equatable, Sendable {
        let number: UInt64
        let uid: UInt64?
        let codec: String
        let configuration: Data?
        let fields: [Field]
        let mappings: [Mapping]
    }
    let kind: Kind
    let videoTracks: [Track]

    enum Failure: Error { case malformed, unsupported, resourceLimit, changedSource }
    static let maximumReadBytes = 64 * 1024 * 1024
    static let maximumPayloadBytes = 16 * 1024 * 1024
    static let maximumElements = 16_384
    static let maximumSegmentElements = 1_000_000
    static let maximumTracks = 256

    // Call from an owned background operation; synchronous filesystem reads
    // can wait for the filesystem. Cancellation is checked between reads.
    static func read(_ url: URL) throws -> Self {
        try Task.checkCancellation()
        guard url.isFileURL else { throw Failure.unsupported }
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw Failure.unsupported }
        defer { Darwin.close(fd) }
        var before = stat()
        guard fstat(fd, &before) == 0, (before.st_mode & S_IFMT) == S_IFREG, before.st_size > 0 else {
            throw Failure.unsupported
        }
        let parser = Parser(size: Int64(before.st_size)) { offset, count in
            var result = Data(count: count)
            try result.withUnsafeMutableBytes { buffer in
                var completed = 0
                while completed < count {
                    try Task.checkCancellation()
                    let n = pread(fd, buffer.baseAddress!.advanced(by: completed), count - completed, off_t(offset + Int64(completed)))
                    if n < 0 && errno == EINTR { continue }
                    guard n > 0 else { throw Failure.malformed }
                    completed += n
                }
            }
            return result
        }
        let result = try parser.parse()
        var after = stat()
        guard fstat(fd, &after) == 0, before.st_dev == after.st_dev, before.st_ino == after.st_ino,
              before.st_size == after.st_size, before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec else { throw Failure.changedSource }
        return result
    }

    static func parse(_ bytes: Data) throws -> Self {
        let data = Data(bytes)
        return try Parser(size: Int64(data.count)) { offset, count in
            data.subdata(in: Int(offset)..<(Int(offset) + count))
        }.parse()
    }

    private final class Parser {
        struct Element { let type: UInt64; let payload: Int64; let end: Int64 }
        let size: Int64
        let read: (Int64, Int) throws -> Data
        var readBytes = 0
        var elements = 0
        var segmentElements = 0
        init(size: Int64, read: @escaping (Int64, Int) throws -> Data) { self.size = size; self.read = read }

        func take(_ offset: Int64, _ count: Int) throws -> Data {
            try Task.checkCancellation()
            guard offset >= 0, count >= 0, offset <= size, Int64(count) <= size - offset else { throw Failure.malformed }
            guard count <= maximumPayloadBytes, readBytes <= maximumReadBytes - count else { throw Failure.resourceLimit }
            readBytes += count
            let result = try read(offset, count)
            guard result.count == count else { throw Failure.malformed }
            return result
        }
        func integer(_ bytes: Data) throws -> UInt64 {
            guard !bytes.isEmpty, bytes.count <= 8 else { throw Failure.malformed }
            return bytes.reduce(0) { ($0 << 8) | UInt64($1) }
        }
        func payload(_ e: Element) throws -> Data {
            guard e.end - e.payload <= Int64(maximumPayloadBytes) else { throw Failure.resourceLimit }
            return try take(e.payload, Int(e.end - e.payload))
        }
        func next(segmentLevel: Bool = false) throws {
            if segmentLevel {
                segmentElements += 1
                guard segmentElements <= maximumSegmentElements else { throw Failure.resourceLimit }
                return
            }
            elements += 1
            guard elements <= maximumElements else { throw Failure.resourceLimit }
        }
        func parse() throws -> ContainerConfiguration {
            guard size >= 8 else { throw Failure.malformed }
            let signature = try take(0, 4)
            return signature == Data([0x1a, 0x45, 0xdf, 0xa3]) ? try matroska() : try mp4()
        }

        func box(_ offset: Int64, end: Int64) throws -> Element {
            try next()
            guard offset <= end, end - offset >= 8 else { throw Failure.malformed }
            let header = try take(offset, Int(min(16, end - offset)))
            var length = try integer(header.subdata(in: 0..<4)); let type = try integer(header.subdata(in: 4..<8))
            var headerBytes: Int64 = 8
            if length == 1 {
                guard header.count >= 16 else { throw Failure.malformed }
                length = try integer(header.subdata(in: 8..<16)); headerBytes = 16
            } else if length == 0 { length = UInt64(end - offset) }
            guard length >= UInt64(headerBytes), length <= UInt64(end - offset) else { throw Failure.malformed }
            return Element(type: type, payload: offset + headerBytes, end: offset + Int64(length))
        }
        func boxes(_ start: Int64, _ end: Int64) throws -> [Element] {
            var result: [Element] = []; var offset = start
            while offset < end { let e = try box(offset, end: end); result.append(e); offset = e.end }
            return result
        }
        func one(_ type: UInt64, in entries: [Element], required: Bool = true) throws -> Element? {
            let matches = entries.filter { $0.type == type }
            guard matches.count <= 1, !required || matches.count == 1 else { throw Failure.malformed }
            return matches.first
        }
        func required(_ type: UInt64, in entries: [Element]) throws -> Element {
            guard let result = try one(type, in: entries) else { throw Failure.malformed }; return result
        }
        func mp4() throws -> ContainerConfiguration {
            let top = try boxes(0, size)
            let moov = try required(0x6d6f6f76, in: top)
            let movie = try boxes(moov.payload, moov.end)
            guard !movie.contains(where: { $0.type == 0x6d766578 }), !top.contains(where: { $0.type == 0x6d6f6f66 }) else {
                throw Failure.unsupported // fragmented sample-description ownership needs its own contract
            }
            let tracks = movie.filter { $0.type == 0x7472616b }
            guard !tracks.isEmpty, tracks.count <= maximumTracks else { throw Failure.resourceLimit }
            var ids = Set<UInt64>(); var result: [Track] = []
            for track in tracks {
                let children = try boxes(track.payload, track.end)
                let header = try payload(required(0x746b6864, in: children))
                guard let version = header.first, version <= 1 else { throw Failure.unsupported }
                let idOffset = version == 0 ? 12 : 20
                guard header.count >= idOffset + 4 else { throw Failure.malformed }
                let id = try integer(header.subdata(in: idOffset..<(idOffset + 4)))
                guard id > 0, ids.insert(id).inserted else { throw Failure.malformed }
                let mdia = try required(0x6d646961, in: children); let media = try boxes(mdia.payload, mdia.end)
                let handler = try payload(required(0x68646c72, in: media))
                guard handler.count >= 12, handler[0] == 0 else { throw Failure.malformed }
                guard handler.subdata(in: 8..<12) == Data("vide".utf8) else { continue }
                let minf = try required(0x6d696e66, in: media); let info = try boxes(minf.payload, minf.end)
                let stbl = try required(0x7374626c, in: info); let table = try boxes(stbl.payload, stbl.end)
                let stsd = try required(0x73747364, in: table)
                guard stsd.end - stsd.payload >= 8 else { throw Failure.malformed }
                let prefix = try take(stsd.payload, 8)
                guard prefix.prefix(4) == Data(repeating: 0, count: 4), try integer(prefix.suffix(4)) == 1 else { throw Failure.unsupported }
                let entries = try boxes(stsd.payload + 8, stsd.end)
                guard entries.count == 1 else { throw Failure.malformed }
                let sample = entries[0]
                let codecs: [UInt64: String] = [0x68766331: "hvc1", 0x68657631: "hev1", 0x64766831: "dvh1", 0x64766865: "dvhe", 0x61763031: "av01", 0x61766331: "avc1"]
                guard let codec = codecs[sample.type] else { throw Failure.unsupported }
                guard sample.end - sample.payload >= 78 else { throw Failure.malformed }
                let fields = try boxes(sample.payload + 78, sample.end)
                var types = Set<UInt64>(); var captured: [Field] = []
                for field in fields {
                    guard types.insert(field.type).inserted else { throw Failure.malformed }
                    captured.append(Field(type: field.type, bytes: try payload(field)))
                }
                let configurationType: UInt64 = codec == "av01" ? 0x61763143 : codec == "avc1" ? 0x61766343 : 0x68766343
                guard let configuration = captured.first(where: { $0.type == configurationType }), !configuration.bytes.isEmpty else { throw Failure.malformed }
                // Keep all opaque sample-entry fields; later admission must
                // classify each field. Unknown fields are not a preservation bypass.
                result.append(Track(number: id, uid: nil, codec: codec, configuration: configuration.bytes,
                                    fields: captured, mappings: []))
            }
            guard !result.isEmpty else { throw Failure.unsupported }
            return ContainerConfiguration(kind: .mp4, videoTracks: result)
        }

        func ebml(_ offset: Int64, end: Int64, unknownSegment: Bool = false, segmentLevel: Bool = false) throws -> Element {
            try next(segmentLevel: segmentLevel)
            guard offset < end else { throw Failure.malformed }
            let header = try take(offset, Int(min(12, end - offset)))
            func width(_ byte: UInt8) throws -> Int {
                guard byte != 0 else { throw Failure.malformed }
                return byte.leadingZeroBitCount + 1
            }
            let idBytes = try width(header[0])
            guard idBytes <= 4, header.count > idBytes else { throw Failure.malformed }
            let id = try integer(header.prefix(idBytes)); let sizeBytes = try width(header[idBytes])
            let idMask = (UInt64(1) << (7 * idBytes)) - 1
            guard id & idMask != 0, id & idMask != idMask else { throw Failure.malformed }
            guard sizeBytes <= 8, header.count >= idBytes + sizeBytes else { throw Failure.malformed }
            var length = UInt64(header[idBytes] & (0xff >> sizeBytes))
            if sizeBytes > 1 { for byte in header[(idBytes + 1)..<(idBytes + sizeBytes)] { length = (length << 8) | UInt64(byte) } }
            let begin = offset + Int64(idBytes + sizeBytes)
            let unknown = length == (UInt64(1) << (7 * sizeBytes)) - 1
            if unknown {
                guard unknownSegment, id == 0x18538067 else { throw Failure.unsupported }
                return Element(type: id, payload: begin, end: end)
            }
            guard length <= UInt64(end - begin) else { throw Failure.malformed }
            return Element(type: id, payload: begin, end: begin + Int64(length))
        }
        func ebmlChildren(_ parent: Element) throws -> [Element] {
            var result: [Element] = []; var offset = parent.payload
            while offset < parent.end { let e = try ebml(offset, end: parent.end); result.append(e); offset = e.end }
            return result
        }
        func matroska() throws -> ContainerConfiguration {
            let header = try ebml(0, end: size)
            let declarations = try ebmlChildren(header)
            guard try payload(required(0x4282, in: declarations)) == Data("matroska".utf8) else { throw Failure.unsupported }
            for (id, maximum): (UInt64, UInt64) in [(0x42f7, 1), (0x42f2, 4), (0x42f3, 8), (0x4285, 4)] {
                if let declaration = try one(id, in: declarations, required: false) {
                    let value = try integer(payload(declaration))
                    guard value > 0, value <= maximum else { throw Failure.unsupported }
                }
            }
            var offset = header.end; var segment: Element?
            while offset < size {
                let e = try ebml(offset, end: size, unknownSegment: true)
                if e.type == 0x18538067 { guard segment == nil else { throw Failure.unsupported }; segment = e }
                else if e.type != 0xec { throw Failure.unsupported }
                offset = e.end
            }
            guard let segment else { throw Failure.malformed }
            // A long movie can have tens of thousands of clusters. Traverse
            // their bounded headers without retaining a cluster array or
            // consuming the separate metadata-element budget.
            var tracksElement: Element?; offset = segment.payload
            while offset < segment.end {
                let e = try ebml(offset, end: segment.end, segmentLevel: true)
                if e.type == 0x1654ae6b {
                    guard tracksElement == nil else { throw Failure.malformed }; tracksElement = e
                }
                offset = e.end
            }
            guard let tracks = tracksElement else { throw Failure.malformed }
            let children = try ebmlChildren(tracks).filter { $0.type == 0xae }
            guard !children.isEmpty, children.count <= maximumTracks else { throw Failure.resourceLimit }
            var numbers = Set<UInt64>(); var uids = Set<UInt64>(); var result: [Track] = []
            for child in children {
                let fields = try ebmlChildren(child)
                let number = try integer(payload(required(0xd7, in: fields)))
                let uid = try integer(payload(required(0x73c5, in: fields)))
                guard number > 0, uid > 0, numbers.insert(number).inserted, uids.insert(uid).inserted else { throw Failure.malformed }
                let type = try integer(payload(required(0x83, in: fields)))
                guard type == 1 else { continue }
                let codecBytes = try payload(required(0x86, in: fields))
                guard codecBytes.count <= 128, !codecBytes.isEmpty, codecBytes.allSatisfy({ $0 >= 0x20 && $0 <= 0x7e }),
                      let codec = String(data: codecBytes, encoding: .ascii) else { throw Failure.malformed }
                guard !fields.contains(where: { $0.type == 0x6d80 }) else { throw Failure.unsupported } // encoded/encrypted track content
                let configElement = try one(0x63a2, in: fields, required: false)
                let config = try configElement.map { try payload($0) }
                var mappings: [Mapping] = []; var mappingTypes = Set<UInt64>(); var values = Set<UInt64>()
                for entry in fields where entry.type == 0x41e4 {
                    let contents = try ebmlChildren(entry)
                    guard contents.allSatisfy({ [0x41f0, 0x41e7, 0x41a4, 0x41ed, 0xec, 0xbf].contains($0.type) }) else { throw Failure.unsupported }
                    let typeElement = try one(0x41e7, in: contents, required: false)
                    let type = try typeElement.map { try integer(payload($0)) } ?? 0
                    let valueElement = try one(0x41f0, in: contents, required: false)
                    let value = try valueElement.map { try integer(payload($0)) }
                    guard mappingTypes.insert(type).inserted else { throw Failure.malformed }
                    if let value { guard values.insert(value).inserted, value >= 2 || (type == 0 && value == 1) else { throw Failure.malformed } }
                    guard type != 0 || value == 1 else { throw Failure.malformed }
                    let name = try one(0x41a4, in: contents, required: false).map { try payload($0) }
                    let extra = try one(0x41ed, in: contents, required: false).map { try payload($0) }
                    mappings.append(Mapping(value: value, type: type, name: name, extra: extra))
                }
                result.append(Track(number: number, uid: uid, codec: codec, configuration: config, fields: [], mappings: mappings))
            }
            guard !result.isEmpty else { throw Failure.unsupported }
            return ContainerConfiguration(kind: .matroska, videoTracks: result)
        }
    }
}
