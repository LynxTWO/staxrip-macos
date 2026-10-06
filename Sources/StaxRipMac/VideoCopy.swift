import Foundation
import Darwin
import CryptoKit

struct VideoCopyContract: Sendable {
    static let maximumSeconds = 172_800.0
    let source: MediaProbe.Stream
    let timeBase: HDRFraction
    let seconds: Double

    static func failure(_ reason: String) -> NativeExportError {
        .invalid("Video copy: " + reason)
    }
    static func validateSettings(_ c: EncodeConfiguration) throws {
        let p = c.picture
        guard c.colorMode == "SDR", c.resolution == "Original", c.cropTop == 0, c.cropBottom == 0,
              p.cropLeft == 0, p.cropRight == 0, p.start == 0, p.end == 0, p.deinterlace == "Off" else {
            throw failure("Choose SDR, original size, zero crop, no trim and deinterlacing Off, or select a video encoder. Picture settings are never discarded automatically.")
        }
    }
    static func tick(_ text: String?) throws -> HDRFraction {
        let value: HDRFraction
        do { value = try HDRFraction(text) }
        catch { throw failure("A valid video time base is required.") }
        guard value.numerator > 0, value.value <= 0.001 else {
            throw failure("Video timing must have at least millisecond precision.")
        }
        return value
    }
    private static func supportsPictureFormat(_ video: MediaProbe.Stream) -> Bool {
        if video.codec_name == "av1" {
            return video.profile == "Main" && ["yuv420p", "yuv420p10le"].contains(video.pix_fmt ?? "") &&
                video.color_primaries == "bt709" && video.color_transfer == "bt709" &&
                video.color_space == "bt709" && video.color_range == "tv"
        }
        if video.pix_fmt == "yuv420p" { return true }
        return video.codec_name == "hevc" && video.profile == "Main 10" && video.pix_fmt == "yuv420p10le" &&
            video.color_primaries == "bt709" && video.color_transfer == "bt709" &&
            video.color_space == "bt709" && video.color_range == "tv"
    }
    static func make(probe: MediaProbe, configuration: EncodeConfiguration) throws -> Self {
        try validateSettings(configuration)
        let formats = (probe.format?.format_name ?? "").split(separator: ",")
        guard formats.contains("mov") || formats.contains("matroska"),
              let video = probe.video, ["h264", "hevc", "av1"].contains(video.codec_name ?? ""),
              video.disposition?["attached_pic"] != 1,
              supportsPictureFormat(video), video.field_order == "progressive", video.sample_aspect_ratio == "1:1",
              !["smpte2084", "arib-std-b67"].contains(video.color_transfer ?? ""),
              try SourceOrientation.read(video) == .identity,
              (video.side_data_list ?? []).allSatisfy({ $0.side_data_type == "Display Matrix" }),
              video.start_pts == 0, Double(probe.format?.start_time ?? "") == 0,
              probe.seconds.isFinite, probe.seconds > 0, probe.seconds <= maximumSeconds,
              let width = video.width, let height = video.height, width > 0, height > 0,
              width.isMultiple(of: 2), height.isMultiple(of: 2) else {
            throw failure("Use a zero-start MP4/QuickTime or Matroska source with upright, progressive, square-pixel video, up to 48 hours. Copy supports 8-bit SDR H.264/HEVC, 10-bit HEVC Main 10 with declared BT.709 limited-range SDR, or 8/10-bit AV1 Main with declared BT.709 limited-range SDR. Other formats need a supported workflow.")
        }
        _ = try VideoCopyPacket.hash(video.extradata_hash ?? "")
        guard let size = video.extradata_size, size > 0, size <= 64 * 1024 * 1024 else {
            throw failure("The source codec configuration cannot be verified.")
        }
        return Self(source: video, timeBase: try tick(video.time_base), seconds: probe.seconds)
    }
    func verifyMetadata(_ output: MediaProbe) throws -> HDRFraction {
        guard let video = output.video,
              video.disposition?["attached_pic"] != 1,
              video.codec_name == source.codec_name, video.profile == source.profile,
              video.width == source.width, video.height == source.height,
              video.pix_fmt == source.pix_fmt, video.field_order == source.field_order,
              video.sample_aspect_ratio == source.sample_aspect_ratio,
              video.color_transfer == source.color_transfer, video.color_primaries == source.color_primaries,
              video.color_space == source.color_space, video.color_range == source.color_range,
              video.chroma_location == source.chroma_location,
              video.extradata_size == source.extradata_size,
              video.extradata_hash == source.extradata_hash,
              video.start_pts == 0, try SourceOrientation.read(video) == .identity,
              (video.side_data_list ?? []).allSatisfy({ $0.side_data_type == "Display Matrix" }) else {
            throw Self.failure("Copied video codec configuration, geometry, color or display metadata changed. Nothing published.")
        }
        return try Self.tick(video.time_base)
    }
}

struct VideoCopyPacket: Equatable, Sendable {
    static let recordBytes = 56
    let pts, duration, size: Int64
    let digest: Data

    static func hash(_ value: String) throws -> Data {
        let bytes = Array(value.utf8)
        guard bytes.count == 71, value.hasPrefix("SHA256:") else {
            throw VideoCopyContract.failure("A complete SHA-256 packet/configuration hash is required.")
        }
        func nibble(_ byte: UInt8) -> UInt8? {
            switch byte {
            case 48...57: return byte - 48
            case 65...70: return byte - 65 + 10
            case 97...102: return byte - 97 + 10
            default: return nil
            }
        }
        var result = Data(); result.reserveCapacity(32)
        for index in stride(from: 7, to: 71, by: 2) {
            guard let a = nibble(bytes[index]), let b = nibble(bytes[index + 1]) else {
                throw VideoCopyContract.failure("Invalid SHA-256 packet/configuration hash.")
            }
            result.append(a * 16 + b)
        }
        return result
    }
    init(line: Data) throws {
        guard let text = String(data: line, encoding: .utf8) else { throw VideoCopyContract.failure("Invalid packet text.") }
        let fields = text.split(separator: "|", omittingEmptySubsequences: false)
        var values: [String: String] = [:]
        for field in fields {
            let pair = field.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2, values.updateValue(String(pair[1]), forKey: String(pair[0])) == nil else {
                throw VideoCopyContract.failure("Malformed or duplicate packet fields.")
            }
        }
        guard Set(values.keys) == Set(["pts", "duration", "size", "data_hash"]),
              let pts = Int64(values["pts"]!), let duration = Int64(values["duration"]!),
              let size = Int64(values["size"]!) else {
            throw VideoCopyContract.failure("Packet timing, size or hash is missing or invalid.")
        }
        self.pts = pts; self.duration = duration; self.size = size
        digest = try Self.hash(values["data_hash"]!)
    }
    init(record: Data) throws {
        guard record.count == Self.recordBytes else { throw VideoCopyContract.failure("Truncated packet manifest.") }
        let numbers = record.withUnsafeBytes { bytes in
            (Int64(littleEndian: bytes.loadUnaligned(fromByteOffset: 0, as: Int64.self)),
             Int64(littleEndian: bytes.loadUnaligned(fromByteOffset: 8, as: Int64.self)),
             Int64(littleEndian: bytes.loadUnaligned(fromByteOffset: 16, as: Int64.self)))
        }
        (pts, duration, size) = numbers; digest = record.subdata(in: 24..<56)
    }
    var record: Data {
        var result = Data(); result.reserveCapacity(Self.recordBytes)
        for value in [pts, duration, size] {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { result.append(contentsOf: $0) }
        }
        result.append(digest); return result
    }
    func validate(tick: Double, seconds: Double) throws {
        let start = Double(pts) * tick, span = Double(duration) * tick
        guard tick.isFinite, tick > 0, tick <= 0.001, seconds.isFinite, seconds > 0, seconds <= VideoCopyContract.maximumSeconds,
              pts >= 0, duration > 0, size > 0, size <= 64 * 1024 * 1024,
              start.isFinite, span.isFinite, start + span <= seconds + 0.25,
              start + span <= VideoCopyContract.maximumSeconds + 0.25 else {
            throw VideoCopyContract.failure("Packet size or presentation interval is outside the supported bounds.")
        }
    }
}

// One ToolRunner stdout reader calls accept serially; finish is used only after
// the runner has joined process exit and both pipe readers.
final class VideoCopyPacketStream: @unchecked Sendable {
    static let maximumPackets = 2_000_000
    private let limit: Int
    private let consume: (VideoCopyPacket) throws -> Void
    private let failed: () -> Void
    private var line = Data()
    private(set) var count = 0
    private(set) var error: Error?
    init(limit: Int = maximumPackets, failed: @escaping () -> Void = {}, consume: @escaping (VideoCopyPacket) throws -> Void) {
        self.limit = max(1, min(Self.maximumPackets, limit)); self.failed = failed; self.consume = consume
    }
    func accept(_ data: Data) {
        guard error == nil else { return }
        do {
            for byte in data {
                if byte == 10 {
                    guard !line.isEmpty, count < limit else { throw VideoCopyContract.failure("Empty packet record or more than two million video packets.") }
                    let packet = try VideoCopyPacket(line: line)
                    try consume(packet); count += 1; line.removeAll(keepingCapacity: true)
                } else {
                    guard line.count < 512 else { throw VideoCopyContract.failure("Packet metadata exceeds 512 bytes.") }
                    line.append(byte)
                }
            }
        } catch { self.error = error; failed() }
    }
    func finish() throws {
        if let error { throw error }
        guard line.isEmpty, count > 0 else { throw VideoCopyContract.failure("Missing or incomplete packet records.") }
    }
}

private final class VideoPacketFile: @unchecked Sendable {
    private let handle: FileHandle
    private var buffer = Data()
    private var offset = 0
    private(set) var count = 0
    init(url: URL, writing: Bool, expectedBytes: Int? = nil) throws {
        let flags = writing ? O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC : O_RDONLY | O_NOFOLLOW | O_CLOEXEC
        let descriptor = Darwin.open(url.path, flags, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              expectedBytes.map({ info.st_size == $0 }) ?? true else {
            try? handle.close(); throw VideoCopyContract.failure("The private packet manifest changed or is not a regular file.")
        }
    }
    func append(_ packet: VideoCopyPacket) throws {
        guard count < VideoCopyPacketStream.maximumPackets else { throw VideoCopyContract.failure("Packet manifest exceeds its supported bound.") }
        buffer.append(packet.record); count += 1
        if buffer.count >= 64 * 1024 { try flush() }
    }
    func flush() throws {
        if !buffer.isEmpty { try handle.write(contentsOf: buffer); buffer.removeAll(keepingCapacity: true) }
    }
    func next() throws -> VideoCopyPacket? {
        while buffer.count - offset < VideoCopyPacket.recordBytes {
            buffer = Data(buffer.dropFirst(offset)); offset = 0
            guard let data = try handle.read(upToCount: 64 * 1024), !data.isEmpty else { break }
            buffer.append(data)
        }
        guard buffer.count - offset >= VideoCopyPacket.recordBytes else {
            guard buffer.count == offset else { throw VideoCopyContract.failure("Truncated private packet manifest.") }
            return nil
        }
        let packet = try VideoCopyPacket(record: buffer.subdata(in: offset..<(offset + VideoCopyPacket.recordBytes)))
        offset += VideoCopyPacket.recordBytes; count += 1; return packet
    }
    func close() throws { try handle.close() }
}

struct VideoCopyManifest: Sendable {
    let contract: VideoCopyContract
    let url: URL
    let count: Int

    // File setup/settlement owns a worker, including cancellation cleanup. Once
    // submitted it always settles; a cancelled caller must still close its FD.
    private static func fileWork<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        let priority = Task.currentPriority
        let qos: DispatchQoS.QoSClass = priority >= .high ? .userInitiated : priority >= .medium ? .default : priority >= .low ? .utility : .background
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue(label: "StaxRip.video-copy-file", qos: DispatchQoS(qosClass: qos, relativePriority: 0)).async {
                do { continuation.resume(returning: try body()) } catch { continuation.resume(throwing: error) }
            }
        }
    }
    private static func scan(_ source: URL, index: Int, tools: FFmpegTools,
                             consume: @escaping (VideoCopyPacket) throws -> Void) async throws -> Int {
        let runner = ToolRunner()
        let parser = VideoCopyPacketStream(failed: { runner.cancel() }, consume: consume)
        let result: ToolResult
        do { result = try await runner.run(executable: tools.ffprobe, arguments: ["-v", "error", "-protocol_whitelist", "file,pipe", "-select_streams", String(index), "-show_packets", "-show_entries", "packet=pts,duration,size,data_hash", "-show_data_hash", "sha256", "-of", "compact=p=0:nk=0", source.path], stdoutLimit: 0) { parser.accept($0) }
        } catch {
            try Task.checkCancellation()
            // A malformed stream deliberately stops its tool. Keep the audit
            // failure rather than presenting that internal stop as user Cancel.
            if let failure = parser.error { throw failure }
            throw error
        }
        try Task.checkCancellation()
        if let error = parser.error { throw error }
        guard result.status == 0 else { throw VideoCopyContract.failure("Packet audit failed: " + String(decoding: result.stderr, as: UTF8.self)) }
        try parser.finish(); return parser.count
    }
    static func capture(_ source: URL, contract: VideoCopyContract, directory: URL, tools: FFmpegTools) async throws -> Self {
        try Task.checkCancellation()
        let url = directory.appendingPathComponent("video-packets.bin")
        let writer = try await fileWork { try VideoPacketFile(url: url, writing: true) }
        do {
            try Task.checkCancellation()
            let count = try await scan(source, index: contract.source.index, tools: tools) { packet in
                try packet.validate(tick: contract.timeBase.value, seconds: contract.seconds)
                try writer.append(packet)
            }
            try await fileWork { try writer.flush(); try writer.close() }
            try Task.checkCancellation()
            return Self(contract: contract, url: url, count: count)
        } catch {
            try? await fileWork { try writer.close() }
            throw error
        }
    }
    func verify(_ output: URL, probe: MediaProbe, tools: FFmpegTools) async throws -> String {
        try Task.checkCancellation()
        guard (1...VideoCopyPacketStream.maximumPackets).contains(count) else {
            throw VideoCopyContract.failure("Invalid private packet manifest count.")
        }
        let actualTick = try contract.verifyMetadata(probe)
        let tick = max(contract.timeBase.value, actualTick.value)
        let reader = try await Self.fileWork { try VideoPacketFile(url: url, writing: false, expectedBytes: count * VideoCopyPacket.recordBytes) }
        do {
            try Task.checkCancellation()
            let actualCount = try await Self.scan(output, index: probe.video!.index, tools: tools) { packet in
                try packet.validate(tick: actualTick.value, seconds: contract.seconds)
                guard let original = try reader.next(), original.size == packet.size, original.digest == packet.digest,
                      abs(Double(original.pts) * contract.timeBase.value - Double(packet.pts) * actualTick.value) <= tick + 0.0000001,
                      abs(Double(original.duration) * contract.timeBase.value - Double(packet.duration) * actualTick.value) <= tick + 0.0000001 else {
                    throw VideoCopyContract.failure("Encoded video packet content or presentation timing changed. Nothing published.")
                }
            }
            let complete = try await Self.fileWork { () -> Bool in
                let exhausted = try reader.next() == nil
                try reader.close(); return exhausted
            }
            guard actualCount == count, complete else { throw VideoCopyContract.failure("Copied video packet count changed. Nothing published.") }
            try Task.checkCancellation()
            return "Verified copied video: \(count) encoded packets · payloads, presentation timestamps and packet durations match within \(String(format: "%.4g", tick * 1000)) ms · codec configuration and display/color metadata unchanged"
        } catch {
            try? await Self.fileWork { try reader.close() }
            throw error
        }
    }
}

// Dedicated exact-copy timing evidence. This is not SDR VideoCopy admission and
// does not authorize Dolby conversion, picture equality or publication.
enum DolbyCopyTiming {
    struct Packet: Sendable {
        let pts, dts, duration, bytes: Int64
        let hash: Data
        init(_ line: Data) throws {
            guard let text = String(data: line, encoding: .utf8) else { throw failure() }
            var fields: [String: String] = [:]
            for field in text.split(separator: "|", omittingEmptySubsequences: false) {
                let pair = field.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard pair.count == 2, fields.updateValue(String(pair[1]), forKey: String(pair[0])) == nil else { throw failure() }
            }
            guard Set(fields.keys) == Set(["pts", "dts", "duration", "size", "data_hash"]),
                  let pts = Int64(fields["pts"]!), let dts = Int64(fields["dts"]!),
                  let duration = Int64(fields["duration"]!), duration > 0,
                  let bytes = Int64(fields["size"]!), (1...DolbyInspection.maximumPacketBytes).contains(bytes) else { throw failure() }
            self.pts = pts; self.dts = dts; self.duration = duration; self.bytes = bytes
            hash = try VideoCopyPacket.hash(fields["data_hash"]!)
        }
    }
    struct Receipt: Sendable, Equatable {
        let packets: Int
        let timeBase: HDRFraction
        let packetSequence: Data
        let timingSequence: Data
        func requireSameTiming(as other: Self) throws {
            guard packets == other.packets, timeBase == other.timeBase, timingSequence == other.timingSequence else { throw failure() }
        }
    }
    static func failure() -> NativeExportError { .invalid("Dolby HDR10 copy: complete exact packet timing could not be verified. Nothing published.") }
    // Fixed-width signed values preserve duplicates and nonmonotonic encoded
    // order. Domain prefixes distinguish packet binding from timing equality.
    static func integers(_ values: [Int64]) -> Data {
        var result = Data()
        for value in values {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { result.append(contentsOf: $0) }
        }
        return result
    }
    final class Stream: @unchecked Sendable {
        private let timeBase: HDRFraction
        private let limit: Int
        private var line = Data(), count = 0
        private var packets = SHA256(), timing = SHA256()
        private(set) var error: Error?
        private(set) var peakLineBytes = 0
        init(timeBase: HDRFraction, limit: Int = DolbyInspection.maximumPackets) throws {
            guard timeBase.numerator > 0, timeBase.value <= 0.001, (1...DolbyInspection.maximumPackets).contains(limit) else { throw failure() }
            self.timeBase = timeBase; self.limit = limit
            packets.update(data: Data("DOLBY-COPY-PACKETS-1\0".utf8))
            timing.update(data: Data("DOLBY-COPY-TIMING-1\0".utf8))
        }
        func accept(_ chunk: Data) {
            guard error == nil else { return }
            do {
                for byte in chunk {
                    if byte == 10 {
                        guard !line.isEmpty, count < limit else { throw failure() }
                        let p = try Packet(line)
                        // Native binding must supply the same declared time base
                        // and ordered packet records; no DTS is inferred from PTS.
                        packets.update(data: integers([Int64(count), p.pts, p.bytes]))
                        packets.update(data: p.hash)
                        timing.update(data: integers([Int64(count), p.pts, p.dts, p.duration]))
                        count += 1; line.removeAll(keepingCapacity: true)
                    } else {
                        guard line.count < 512 else { throw failure() }
                        line.append(byte); peakLineBytes = max(peakLineBytes, line.count)
                    }
                }
            } catch { self.error = error }
        }
        func finish() throws -> Receipt {
            if let error { throw error }
            guard line.isEmpty, count > 0 else { throw failure() }
            return .init(packets: count, timeBase: timeBase,
                         packetSequence: Data(packets.finalize()), timingSequence: Data(timing.finalize()))
        }
    }
    // The caller still owns source/candidate access and staging, and must retain
    // them on CompanionUnsettledOwnership. A timing receipt alone is insufficient.
    static func read(_ source: URL, stream: Int, timeBase: HDRFraction, tools: FFmpegTools) async throws -> Receipt {
        guard source.isFileURL, stream >= 0 else { throw failure() }
        let parser = try Stream(timeBase: timeBase)
        let runner = ToolRunner(checkedReaders: true)
        let result: ToolResult
        do {
            result = try await runner.run(executable: tools.ffprobe, arguments: [
                "-v", "error", "-protocol_whitelist", "file,pipe", "-select_streams", String(stream),
                "-show_packets", "-show_data_hash", "sha256", "-show_entries",
                "packet=pts,dts,duration,size,data_hash", "-of", "compact=p=0:nk=0", source.path
            ], stdoutLimit: 0) { chunk in
                guard parser.error == nil else { return }
                parser.accept(chunk)
                if parser.error != nil { runner.cancel() }
            }
        } catch var error as ToolRunner.ReaderCloseFailure {
            error.consumerCause = parser.error
            throw error
        } catch {
            if error is any CompanionUnsettledOwnership { throw error }
            if let parse = parser.error { throw parse }
            throw error
        }
        try Task.checkCancellation()
        guard result.status == 0, result.stderr.isEmpty else { throw failure() }
        // stdoutLimit=0 intentionally keeps no transcript; complete lines/count
        // plus the joined successful helper are independent requirements.
        return try parser.finish()
    }
}

/// Encoded-only proof for the first single-video, SimpleBlock Matroska route.
/// ReadView access belongs to the caller. This is not decoded HDR or admission proof.
enum DolbyCopyNative {
    enum Role { case source, output }
    struct Receipt {
        let configuration: Data
        let packets: Int
        let wholeSequence, keptSequence, presentationSequence: Data
        let strictlyIncreasingPTS: Bool
        let timeBase: HDRFraction
        let defaultDuration: UInt64
        let rpus, enhancement: Int
        func bind(_ timing: DolbyCopyTiming.Receipt) throws {
            guard packets == timing.packets, timeBase == timing.timeBase,
                  wholeSequence == timing.packetSequence else { throw failure() }
        }
        func requireCopy(_ output: Self) throws {
            guard configuration == output.configuration, packets == output.packets,
                  keptSequence == output.wholeSequence, timeBase == output.timeBase,
                  defaultDuration == output.defaultDuration,
                  rpus == packets, enhancement > 0, output.rpus == 0, output.enhancement == 0 else { throw failure() }
        }
    }
    static func failure() -> NativeExportError { .invalid("Dolby HDR10 copy: native encoded base-layer proof refused.") }
    static func read(_ view: CompanionDiskCheck.ReadView, role: Role, timeBase: HDRFraction) throws -> Receipt {
        try Scan(view, role, timeBase).read()
    }
    static func verify(source: Receipt, output: Receipt, sourceTiming: DolbyCopyTiming.Receipt,
                       outputTiming: DolbyCopyTiming.Receipt) throws {
        try source.bind(sourceTiming); try output.bind(outputTiming)
        try sourceTiming.requireSameTiming(as: outputTiming)
        try source.requireCopy(output)
    }
    private final class Scan {
        typealias Track = CompanionOriginalTrackCheck
        typealias Element = Track.Element
        let view: CompanionDiskCheck.ReadView, walker: Track.Walker, role: Role, timeBase: HDRFraction
        let tickNS: Int64
        var selected: Track.Selected?, width = 0, packets = 0, rpus = 0, enhancement = 0
        var defaultDuration: UInt64 = 0, whole = SHA256(), kept = SHA256(), presentation = SHA256()
        var lastPTS: Int64?, increasing = true
        init(_ view: CompanionDiskCheck.ReadView, _ role: Role, _ timeBase: HDRFraction) throws {
            let (ns, overflow) = timeBase.numerator.multipliedReportingOverflow(by: 1_000_000_000)
            guard !overflow, ns > 0, ns % timeBase.denominator == 0,
                  timeBase.value <= 0.001 else { throw failure() }
            let checked = CompanionDiskCheck.ReadView(sourceBytes: view.sourceBytes, source: { offset, count in
                guard offset >= 0, count >= 0, offset <= view.sourceBytes,
                      Int64(count) <= view.sourceBytes - offset else { throw failure() }
                let data = try view.source(offset, count)
                guard data.count == count else { throw failure() }; return data
            }, component: view.component, checkpoint: view.checkpoint)
            self.view = checked; self.role = role; self.timeBase = timeBase; tickNS = ns / timeBase.denominator
            walker = Track.Walker(checked, elementLimit: 128_000_000)
            whole.update(data: Data("DOLBY-COPY-PACKETS-1\0".utf8))
            kept.update(data: Data("DOLBY-COPY-PACKETS-1\0".utf8))
            presentation.update(data: Data("DOLBY-COPY-PRESENTATION-1\0".utf8))
        }
        func children(_ e: Element, _ body: (Element) throws -> Void) throws {
            var cursor = e.payload
            while cursor < e.end {
                let child = try walker.element(cursor, end: e.end)
                guard !child.unknown else { throw failure() }
                try body(child); cursor = child.end
            }
        }
        func read() throws -> Receipt {
            guard (1...(1 << 40)).contains(view.sourceBytes) else { throw failure() }
            let header = try walker.element(0, end: view.sourceBytes)
            guard header.id == 0x1a45dfa3, !header.unknown else { throw failure() }
            var docType = false, headerFields: Set<UInt64> = []
            try children(header) { e in
                guard headerFields.insert(e.id).inserted else { throw failure() }
                switch e.id {
                case 0x4282: docType = try walker.bytes(e, maximum: 64) == Data("matroska".utf8)
                case 0x4285: guard try (1...4).contains(walker.unsigned(e)) else { throw failure() }
                case 0x42f7: guard try walker.unsigned(e) == 1 else { throw failure() }
                case 0x42f2: guard try walker.unsigned(e) == 4 else { throw failure() }
                case 0x42f3: guard try walker.unsigned(e) == 8 else { throw failure() }
                default: break
                }
            }
            guard docType else { throw failure() }
            let segment = try walker.element(header.end, end: view.sourceBytes)
            guard segment.id == 0x18538067, segment.end == view.sourceBytes else { throw failure() }
            var scale: UInt64?, began = false
            try children(segment) { e in
                switch e.id {
                case 0x1549a966:
                    guard scale == nil, !began else { throw failure() }
                    var value: UInt64 = 1_000_000, found = false
                    try children(e) { f in
                        if f.id == 0x2ad7b1 {
                            guard !found else { throw failure() }; found = true; value = try walker.unsigned(f)
                        }
                    }
                    guard value == UInt64(tickNS) else { throw failure() }; scale = value
                case 0x1654ae6b:
                    guard selected == nil, !began else { throw failure() }
                    let track = try walker.tracks(e)
                    guard walker.trackNumbers.count == 1 else { throw failure() }
                    try declarations(track); selected = track
                case 0x1f43b675:
                    guard selected != nil, let scale else { throw failure() }
                    began = true; try cluster(e, scale)
                case 0x1a45dfa3, 0x18538067, 0xa0, 0xa1, 0xa3, 0x1941a469, 0x1043a770: throw failure()
                default: break
                }
            }
            guard began, packets > 0, let selected,
                  role == .output || (rpus == packets && enhancement > 0) else { throw failure() }
            try view.checkpoint()
            return .init(configuration: selected.configuration, packets: packets,
                         wholeSequence: Data(whole.finalize()), keptSequence: Data(kept.finalize()),
                         presentationSequence: Data(presentation.finalize()), strictlyIncreasingPTS: increasing,
                         timeBase: timeBase, defaultDuration: defaultDuration, rpus: rpus, enhancement: enhancement)
        }
        func declarations(_ track: Track.Selected) throws {
            width = try Track.configuration(track.configuration, checkpoint: view.checkpoint)
            let config = track.configuration
            var cursor = 23, types: Set<UInt8> = []
            for _ in 0..<Int(config[22]) {
                let type = config[cursor] & 63, count = Int(config[cursor + 1]) << 8 | Int(config[cursor + 2])
                guard [32,33,34].contains(type), count > 0, types.insert(type).inserted else { throw failure() }
                cursor += 3
                for _ in 0..<count {
                    let length = Int(config[cursor]) << 8 | Int(config[cursor + 1]); cursor += 2
                    guard config[cursor] & 1 == 0, config[cursor + 1] >> 3 == 0 else { throw failure() }
                    cursor += length
                }
            }
            guard types == Set([UInt8(32),33,34]) else { throw failure() }
            let entry = Element(id: 0xae, payload: track.offset, end: track.offset + Int64(track.payload.count), unknown: false)
            var seen: Set<UInt64> = [], mapping = false, maxID: UInt64 = 0
            try children(entry) { e in
                guard seen.insert(e.id).inserted else { throw failure() }
                switch e.id {
                case 0x6d80, 0xe2: throw failure()
                case 0x56aa: guard try walker.unsigned(e) == 0 else { throw failure() }
                case 0x537f:
                    let data = try walker.bytes(e, maximum: 8)
                    guard !data.isEmpty, data.allSatisfy({ $0 == 0 }) else { throw failure() }
                case 0x23314f:
                    let data = try walker.bytes(e, maximum: 8)
                    guard data == Data([0x3f,0x80,0,0]) || data == Data([0x3f,0xf0,0,0,0,0,0,0]) else { throw failure() }
                case 0x23e383:
                    defaultDuration = try walker.unsigned(e); guard defaultDuration > 0 else { throw failure() }
                case 0x55ee: maxID = try walker.unsigned(e)
                case 0x41e4:
                    guard role == .source else { throw failure() }
                    var fields: [UInt64: Data] = [:]
                    try children(e) { f in
                        guard fields.updateValue(try walker.bytes(f, maximum: 64), forKey: f.id) == nil else { throw failure() }
                    }
                    // Narrow initial P7/L6/CCID6 v1 declaration; MEL/CM2.9 still
                    // require independent full source metadata admission.
                    guard Set(fields.keys) == Set([0x41f0,0x41e7,0x41ed]), fields[0x41f0] == Data([1]),
                          fields[0x41e7] == Data("dvcC".utf8),
                          fields[0x41ed] == Data([1,0,14,55,96] + Array(repeating: 0, count: 19)) else { throw failure() }
                    mapping = true
                default: break
                }
            }
            guard defaultDuration > 0, role == .source ? (mapping && maxID == 1) : (!mapping && maxID == 0) else { throw failure() }
        }
        func cluster(_ e: Element, _ scale: UInt64) throws {
            var timestamp: UInt64?
            try children(e) { f in
                switch f.id {
                case 0xe7:
                    guard timestamp == nil else { throw failure() }; timestamp = try walker.unsigned(f)
                case 0xa3:
                    guard let timestamp else { throw failure() }; try packet(f, timestamp, scale)
                case 0xa0, 0xa1, 0x1549a966, 0x1654ae6b, 0x1f43b675: throw failure()
                default: break
                }
            }
            guard timestamp != nil else { throw failure() }
        }
        func packet(_ e: Element, _ timestamp: UInt64, _ scale: UInt64) throws {
            guard packets < 2_000_000, e.end > e.payload, let selected else { throw failure() }
            let header = try view.source(e.payload, Int(min(11, e.end - e.payload)))
            guard let first = header.first, first != 0 else { throw failure() }
            let trackWidth = first.leadingZeroBitCount + 1
            guard trackWidth <= 8, header.count >= trackWidth + 3 else { throw failure() }
            let mask = (UInt64(1) << (7 * trackWidth)) - 1
            let number = header.prefix(trackWidth).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) } & mask
            guard number != mask, number == selected.number, header[trackWidth + 2] & 0x7f == 0 else { throw failure() }
            let relative = Int16(bitPattern: UInt16(header[trackWidth]) << 8 | UInt16(header[trackWidth + 1]))
            let ns = try CompanionOriginalPacketCheck.pts(cluster: timestamp, relative: relative, scale: scale)
            guard ns % tickNS == 0 else { throw failure() }
            let pts = ns / tickNS, start = e.payload + Int64(trackWidth + 3), size = e.end - start
            guard (1...(16 << 20)).contains(size) else { throw failure() }
            var cursor = start, packetHash = SHA256(), projectionHash = SHA256(), keptBytes: Int64 = 0, packetRPUs = 0, vcl = 0
            while cursor < e.end {
                try view.checkpoint()
                guard Int64(width) <= e.end - cursor else { throw failure() }
                let prefix = try view.source(cursor, width)
                let length = prefix.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
                cursor += Int64(width)
                guard length >= 2, length <= UInt64(e.end - cursor) else { throw failure() }
                let h = try view.source(cursor, 2)
                guard h[0] & 0x80 == 0, h[1] & 7 != 0 else { throw failure() }
                let type = h[0] >> 1 & 63, removed = type == 62 || type == 63
                if removed {
                    guard role == .source else { throw failure() }
                    if type == 62 {
                        guard h[0] & 1 == 0, h[1] >> 3 == 0, length > 2, length <= 65_538 else { throw failure() }
                        packetRPUs += 1; rpus += 1
                    } else { enhancement += 1 }
                } else {
                    guard h[0] & 1 == 0, h[1] >> 3 == 0 else { throw failure() }
                    if type <= 31 { vcl += 1 }
                    projectionHash.update(data: prefix); keptBytes += Int64(width) + Int64(length)
                }
                packetHash.update(data: prefix)
                let end = cursor + Int64(length)
                while cursor < end {
                    let count = Int(min(1 << 20, end - cursor)), data = try view.source(cursor, Int(min(1 << 20, end - cursor)))
                    guard data.count == count else { throw failure() }
                    packetHash.update(data: data); if !removed { projectionHash.update(data: data) }
                    cursor += Int64(count); try view.checkpoint()
                }
            }
            guard keptBytes > 0, vcl > 0, role == .output || packetRPUs == 1 else { throw failure() }
            whole.update(data: DolbyCopyTiming.integers([Int64(packets),pts,size])); whole.update(data: Data(packetHash.finalize()))
            kept.update(data: DolbyCopyTiming.integers([Int64(packets),pts,keptBytes])); kept.update(data: Data(projectionHash.finalize()))
            if let lastPTS, pts <= lastPTS { increasing = false }; lastPTS = pts
            presentation.update(data: DolbyCopyTiming.integers([Int64(packets),pts]))
            packets += 1
        }
    }
}

/// Full-frame evidence for the unchanged, no-reorder HDR10 base-layer copy route.
/// Callers retain concrete access and staging on every shared ownership marker.
enum DolbyCopyFrames {
    struct Receipt: Equatable {
        let frames: Int64
        let presentation, pixels: Data
        let mastering: HDRMasteringDisplay
        let light: HDRContentLight?
        let chroma: String
        let timeBase: HDRFraction
        func bind(_ native: DolbyCopyNative.Receipt) throws {
            guard timeBase == native.timeBase, native.strictlyIncreasingPTS, frames == native.packets,
                  presentation == native.presentationSequence else { throw failure() }
        }
    }
    static func failure() -> NativeExportError { .invalid("Dolby HDR10 copy: full frame, static HDR or decoded base-layer equality refused.") }
    final class Frames {
        let stream: MediaProbe.Stream, source: Bool
        let timeBase: HDRFraction
        var declaredMastering: HDRMasteringDisplay?, declaredLight: HDRContentLight?
        var count: Int64 = 0, last: Int64?, sequence = SHA256()
        var mastering: HDRMasteringDisplay?, light: HDRContentLight?
        init(_ stream: MediaProbe.Stream, source: Bool) throws {
            self.stream = stream; self.source = source; timeBase = try HDRFraction(stream.time_base)
            guard timeBase.numerator > 0 else { throw failure() }
            guard stream.codec_name == "hevc", stream.profile == "Main 10", stream.pix_fmt == "yuv420p10le",
                  stream.width == 3840, stream.height == 2160, stream.chroma_location == "topleft",
                  stream.color_range == "tv", stream.color_space == "bt2020nc", stream.color_primaries == "bt2020",
                  stream.color_transfer == "smpte2084", (stream.field_order == nil || stream.field_order == "progressive"),
                  stream.sample_aspect_ratio == "1:1", try SourceOrientation.read(stream) == .identity,
                  try HDRFraction(stream.avg_frame_rate) == HDRFraction("24000/1001"),
                  try HDRFraction(stream.r_frame_rate) == HDRFraction("24000/1001") else { throw failure() }
            let allowed = ["Mastering display metadata", "Content light level metadata"] + (source ? ["DOVI configuration record"] : [])
            guard (stream.side_data_list ?? []).count <= 3 else { throw failure() }
            var seen: Set<String> = []
            for side in stream.side_data_list ?? [] {
                guard let type = side.side_data_type, allowed.contains(type), seen.insert(type).inserted else { throw failure() }
                if type == "Mastering display metadata" { declaredMastering = try HDRMasteringDisplay(side.fields()) }
                if type == "Content light level metadata" { declaredLight = try HDRContentLight(side.fields()) }
            }
            sequence.update(data: Data("DOLBY-COPY-PRESENTATION-1\0".utf8))
        }
        func consume(_ frame: [String: Any]) throws {
            guard count < 2_000_000,
                  try HDR10Audit.integer(frame["width"], range: 1...16384) == 3840,
                  try HDR10Audit.integer(frame["height"], range: 1...16384) == 2160,
                  try HDR10Audit.integer(frame["interlaced_frame"], range: 0...1) == 0,
                  frame["pix_fmt"] as? String == "yuv420p10le", frame["color_range"] as? String == "tv",
                  frame["color_space"] as? String == "bt2020nc", frame["color_primaries"] as? String == "bt2020",
                  frame["color_transfer"] as? String == "smpte2084", frame["chroma_location"] as? String == "topleft",
                  frame["sample_aspect_ratio"] as? String == "1:1" else { throw failure() }
            let pts = try HDR10Audit.integer(frame["pts"], range: Int64.min...Int64.max)
            if let last { guard pts > last else { throw failure() } }; last = pts
            guard let side = frame["side_data_list"] as? [[String: Any]], side.count <= 8 else { throw failure() }
            var seen: Set<String> = [], md: HDRMasteringDisplay?, cll: HDRContentLight?
            for record in side {
                guard let type = record["side_data_type"] as? String, seen.insert(type).inserted else { throw failure() }
                switch type {
                case "Mastering display metadata": md = try HDRMasteringDisplay(record)
                case "Content light level metadata": cll = try HDRContentLight(record)
                case "H.26[45] User Data Unregistered SEI message": break // Encoded-byte proof preserves the original payload.
                case "Dolby Vision RPU Data", "Dolby Vision Metadata": guard source else { throw failure() }
                default: throw failure()
                }
            }
            guard let md else { throw failure() }
            if let declaredMastering { guard declaredMastering == md else { throw failure() } }
            if let declaredLight { guard declaredLight == cll else { throw failure() } }
            if count == 0 { mastering = md; light = cll }
            else { guard mastering == md, light == cll else { throw failure() } }
            sequence.update(data: DolbyCopyTiming.integers([count,pts])); count += 1
        }
    }
    final class Pixels: @unchecked Sendable {
        let frameBytes: Int
        var count: Int64 = 0, offset = 0, frame = SHA256(), sequence = SHA256()
        private(set) var error: Error?
        init(frameBytes: Int = 3840 * 2160 * 3) {
            self.frameBytes = frameBytes
            sequence.update(data: Data("DOLBY-COPY-DECODED-1\0".utf8))
        }
        func accept(_ data: Data) {
            guard error == nil else { return }
            guard frameBytes > 0 else { error = failure(); return }
            var cursor = 0
            while cursor < data.count {
                guard count < 2_000_000 else { error = failure(); return }
                let length = min(data.count - cursor, frameBytes - offset)
                frame.update(data: data.subdata(in: (data.startIndex + cursor)..<(data.startIndex + cursor + length))); cursor += length; offset += length
                if offset == frameBytes {
                    sequence.update(data: DolbyCopyTiming.integers([count,Int64(frameBytes)]))
                    sequence.update(data: Data(frame.finalize())); count += 1; offset = 0; frame = SHA256()
                }
            }
        }
        func finish(expected: Int64) throws -> Data {
            if let error { throw error }
            guard offset == 0, count > 0, count == expected else { throw failure() }
            return Data(sequence.finalize())
        }
    }
    static func read(_ url: URL, stream: MediaProbe.Stream, source: Bool, tools: FFmpegTools) async throws -> Receipt {
        let frames = try Frames(stream, source: source), parser = HDRFrameJSON { try frames.consume($0) }
        let runner = ToolRunner(checkedReaders: true)
        let result: ToolResult
        do {
            result = try await runner.run(executable: tools.ffprobe, arguments: [
                "-v","error","-threads","2","-protocol_whitelist","file,pipe","-select_streams",String(stream.index),"-show_frames",
                "-show_entries","frame=pts,width,height,pix_fmt,color_range,color_space,color_primaries,color_transfer,chroma_location,sample_aspect_ratio,interlaced_frame:frame_side_data","-of","json",url.path
            ], stdoutLimit: 0) { data in
                guard parser.error == nil else { return }; parser.accept(data); if parser.error != nil { runner.cancel() }
            }
        } catch var error as ToolRunner.ReaderCloseFailure { error.consumerCause = parser.error; throw error }
        catch { if error is any CompanionUnsettledOwnership { throw error }; if let error = parser.error { throw error }; throw error }
        guard result.status == 0, result.stderr.isEmpty else { throw failure() }; try parser.finish(); try Task.checkCancellation()
        guard frames.count > 0, let mastering = frames.mastering else { throw failure() }
        let pixels = Pixels(), decoder = ToolRunner(checkedReaders: true)
        let decoded: ToolResult
        do {
            decoded = try await decoder.run(executable: tools.ffmpeg, arguments: [
                "-v","error","-nostdin","-threads","2","-noautorotate","-copyts","-i",url.path,
                "-map","0:\(stream.index)","-an","-sn","-dn","-c:v","rawvideo","-pix_fmt","+yuv420p10le",
                "-noautoscale","-fps_mode","passthrough","-enc_time_base","demux","-f","rawvideo","pipe:1"
            ], stdoutLimit: 0) { data in guard pixels.error == nil else { return }; pixels.accept(data); if pixels.error != nil { decoder.cancel() } }
        } catch var error as ToolRunner.ReaderCloseFailure { error.consumerCause = pixels.error; throw error }
        catch { if error is any CompanionUnsettledOwnership { throw error }; if let error = pixels.error { throw error }; throw error }
        guard decoded.status == 0, decoded.stderr.isEmpty else { throw failure() }; try Task.checkCancellation()
        return .init(frames: frames.count, presentation: Data(frames.sequence.finalize()), pixels: try pixels.finish(expected: frames.count),
                     mastering: mastering, light: frames.light, chroma: "topleft", timeBase: frames.timeBase)
    }
}

// Full metadata source admission for the explicitly narrow P8.1 candidate.
// This receipt never authorizes conversion, decoding, publication or cleanup.
enum DolbyP81Metadata {
    typealias JSON = CompanionArchiveJSON
    typealias Object = JSON.Object
    enum Unsupported: Error { case metadata }
    static func require(_ condition: Bool) throws { if !condition { throw Unsupported.metadata } }
    static func object(_ value: JSON.Value?) throws -> Object {
        guard case .object(let o)? = value else { throw Unsupported.metadata }; return o
    }
    static func keys(_ o: Object, _ names: String) throws { try require(Set(o.keys) == Set(names.split(separator: " ").map(String.init))) }
    static func n(_ o: Object, _ k: String, _ range: ClosedRange<UInt64>) throws -> UInt64 { try JSON.unsigned(o,k,range) }
    static let header = #"{"bl_bit_depth_minus8":2,"bl_video_full_range_flag":false,"chroma_resampling_explicit_filter_flag":false,"coefficient_data_type":0,"coefficient_log2_denom":23,"coefficient_log2_denom_length":23,"disable_residual_flag":false,"el_bit_depth_minus8":2,"el_spatial_resampling_filter_flag":true,"ext_mapping_idc_0_4":0,"ext_mapping_idc_5_7":0,"prev_vdr_rpu_id":0,"reserved_zero_3bits":0,"rpu_format":18,"rpu_nal_prefix":25,"rpu_type":2,"spatial_resampling_filter_flag":false,"use_prev_vdr_rpu_flag":false,"vdr_bit_depth_minus8":4,"vdr_dm_metadata_present_flag":true,"vdr_rpu_level":0,"vdr_rpu_normalized_idc":1,"vdr_rpu_profile":1,"vdr_seq_info_present_flag":true}"#
    static let mapping = #"{"curves":[{"linear_interp_flag":[false],"mapping_idc":"Polynomial","num_pivots_minus2":0,"pivots":[0,1023],"poly_coef":[[0,0]],"poly_coef_int":[[0,1]],"poly_order_minus1":[0]},{"linear_interp_flag":[false],"mapping_idc":"Polynomial","num_pivots_minus2":0,"pivots":[0,1023],"poly_coef":[[0,0]],"poly_coef_int":[[0,1]],"poly_order_minus1":[0]},{"linear_interp_flag":[false],"mapping_idc":"Polynomial","num_pivots_minus2":0,"pivots":[0,1023],"poly_coef":[[0,0]],"poly_coef_int":[[0,1]],"poly_order_minus1":[0]}],"mapping_chroma_format_idc":0,"mapping_color_space":0,"nlq":{"linear_deadzone_slope":[0,0,0],"linear_deadzone_slope_int":[0,0,0],"linear_deadzone_threshold":[0,0,0],"linear_deadzone_threshold_int":[0,0,0],"nlq_offset":[0,0,0],"vdr_in_max":[0,0,0],"vdr_in_max_int":[1,1,1]},"nlq_method_idc":"LinearDeadzone","nlq_num_pivots_minus2":0,"nlq_pred_pivot_value":[0,1023],"num_x_partitions_minus1":0,"num_y_partitions_minus1":0,"vdr_rpu_id":0}"#
    static let fixedDM = #"{"compressed":false,"rgb_to_lms_coef0":7222,"rgb_to_lms_coef1":8771,"rgb_to_lms_coef2":390,"rgb_to_lms_coef3":2654,"rgb_to_lms_coef4":12430,"rgb_to_lms_coef5":1300,"rgb_to_lms_coef6":0,"rgb_to_lms_coef7":422,"rgb_to_lms_coef8":15962,"signal_bit_depth":12,"signal_chroma_format":0,"signal_color_space":0,"signal_eotf":65535,"signal_eotf_param0":0,"signal_eotf_param1":0,"signal_eotf_param2":0,"signal_full_range_flag":1,"ycc_to_rgb_coef0":9574,"ycc_to_rgb_coef1":0,"ycc_to_rgb_coef2":13802,"ycc_to_rgb_coef3":9574,"ycc_to_rgb_coef4":-1540,"ycc_to_rgb_coef5":-5348,"ycc_to_rgb_coef6":9574,"ycc_to_rgb_coef7":17610,"ycc_to_rgb_coef8":0,"ycc_to_rgb_offset0":16777216,"ycc_to_rgb_offset1":134217728,"ycc_to_rgb_offset2":134217728}"#
    static func template(_ text: String) throws -> Object { try JSON.metadataObject(Data(text.utf8)) }
    static func normalized(_ input: Object, source: Bool) throws -> JSON.Value {
        var r = input
        if !source {
            try keys(r,"dovi_profile header rpu_data_mapping vdr_dm_data rpu_data_crc32")
            try require(r["dovi_profile"] == .unsigned(8))
            var h = try object(r["header"]), m = try object(r["rpu_data_mapping"])
            try require(h["disable_residual_flag"] == .bool(true) && h["el_spatial_resampling_filter_flag"] == .bool(false))
            h["disable_residual_flag"] = .bool(false); h["el_spatial_resampling_filter_flag"] = .bool(true)
            let original = try template(mapping)
            for k in ["nlq_method_idc","nlq_num_pivots_minus2","nlq_pred_pivot_value","nlq"] {
                try require(m[k] == nil); m[k] = original[k]
            }
            r["dovi_profile"] = .unsigned(7); r["el_type"] = .string("MEL"); r["header"] = .object(h); r["rpu_data_mapping"] = .object(m)
        }
        try keys(r,"dovi_profile el_type header rpu_data_mapping vdr_dm_data rpu_data_crc32")
        try require(r["dovi_profile"] == .unsigned(7) && r["el_type"] == .string("MEL"))
        try require(r["header"] == .object(template(header)) && r["rpu_data_mapping"] == .object(template(mapping)))
        _ = try n(r,"rpu_data_crc32",0...UInt64(UInt32.max)) // Actual encoded CRC is validated by the helper.
        let d = try object(r["vdr_dm_data"]), fixed = try template(fixedDM)
        try require(Set(d.keys) == Set(fixed.keys).union(["affected_dm_metadata_id","current_dm_metadata_id","scene_refresh_flag","source_min_pq","source_max_pq","source_diagonal","cmv29_metadata"]))
        for (k,v) in fixed { try require(d[k] == v) }
        for k in ["affected_dm_metadata_id","current_dm_metadata_id"] { _ = try n(d,k,0...0) }
        _ = try n(d,"scene_refresh_flag",0...1); _ = try n(d,"source_diagonal",0...1023)
        let low = try n(d,"source_min_pq",0...4095); _ = try n(d,"source_max_pq",low...4095)
        let cm = try object(d["cmv29_metadata"]); try keys(cm,"num_ext_blocks ext_metadata_blocks")
        _ = try n(cm,"num_ext_blocks",3...3)
        guard case .array(let blocks)? = cm["ext_metadata_blocks"], blocks.count == 3 else { throw Unsupported.metadata }
        var levels: [Object] = []
        for (value,name) in zip(blocks,["Level1","Level5","Level6"]) {
            let block = try object(value); try keys(block,name); levels.append(try object(block[name]))
        }
        let l1 = levels[0]; try keys(l1,"min_pq max_pq avg_pq")
        let high = try n(l1,"max_pq",0...4095)
        _ = try n(l1,"min_pq",0...high); _ = try n(l1,"avg_pq",0...high) // Narrow candidate policy.
        let l5 = levels[1]; try keys(l5,"active_area_left_offset active_area_right_offset active_area_top_offset active_area_bottom_offset")
        for k in l5.keys { _ = try n(l5,k,0...0) }
        let l6 = levels[2]; try keys(l6,"max_display_mastering_luminance min_display_mastering_luminance max_content_light_level max_frame_average_light_level")
        for k in l6.keys { _ = try n(l6,k,0...10000) }
        let maxNits = try n(l6,"max_display_mastering_luminance",0...10000)
        let scaled = maxNits.multipliedReportingOverflow(by: 10000)
        try require(!scaled.overflow && n(l6,"min_display_mastering_luminance",0...10000) <= scaled.partialValue)
        var h = try object(r["header"]), m = try object(r["rpu_data_mapping"])
        h["disable_residual_flag"] = .bool(true); h["el_spatial_resampling_filter_flag"] = .bool(false)
        for k in ["nlq_method_idc","nlq_num_pivots_minus2","nlq_pred_pivot_value","nlq"] { m.removeValue(forKey:k) }
        r["dovi_profile"] = .unsigned(8); r.removeValue(forKey:"el_type"); r.removeValue(forKey:"rpu_data_crc32")
        r["header"] = .object(h); r["rpu_data_mapping"] = .object(m)
        return .object(r)
    }
    /// Caller is the existing Batch copy owner, holding source/parent access and
    /// retaining concrete staging/FDs on every failure. This owns no cleanup.
    static func read(_ source: URL, report: DolbySourceReport, helper: URL) async throws -> DolbyP81MetadataStream.Receipt {
        let stream = try DolbyP81MetadataStream(source:report.source)
        let runner = ToolRunner(checkedReaders:true)
        let result: ToolResult
        do {
            result = try await runner.run(executable:helper, arguments:["mkv-json",source.path], stdoutLimit:0) { data in
                stream.receive(data); if stream.error != nil { runner.cancel() }
            }
        } catch var error as ToolRunner.ReaderCloseFailure {
            error.consumerCause = stream.error; throw error
        } catch {
            if error is any CompanionUnsettledOwnership { throw error }
            if let error = stream.error { throw error }
            throw error
        }
        let receipt = try stream.finish(status:result.status,packetSequence:report.packetSequenceSHA256,header:report.header)
        guard receipt.packets == report.packets, receipt.records == report.records,
              receipt.enhancementNALs == report.enhancementNALs else { throw DolbyCopyNative.failure() }
        try Task.checkCancellation()
        return receipt
    }
    static func append(_ value: JSON.Value, to hash: inout SHA256) {
        func bytes(_ tag: UInt8, _ data: Data) { hash.update(data:Data([tag])); hash.update(data:DolbyCopyTiming.integers([Int64(data.count)])); hash.update(data:data) }
        switch value {
        case .object(let o):
            bytes(1,DolbyCopyTiming.integers([Int64(o.count)]))
            for k in o.keys.sorted() { bytes(2,Data(k.utf8)); append(o[k]!,to:&hash) }
        case .array(let a): bytes(3,DolbyCopyTiming.integers([Int64(a.count)])); for v in a { append(v,to:&hash) }
        case .string(let s): bytes(4,Data(s.utf8))
        case .unsigned(let n): var v = n.littleEndian; bytes(5,withUnsafeBytes(of:&v) { Data($0) })
        case .signed(let n): bytes(6,DolbyCopyTiming.integers([n]))
        case .bool(let b): bytes(7,Data([b ? 1 : 0]))
        case .null: bytes(8,Data())
        }
    }
}
final class DolbyP81MetadataStream: @unchecked Sendable {
    typealias JSON = CompanionArchiveJSON
    struct Receipt: Sendable {
        let source: SourceFingerprint
        let packets: Int64, records: Int64, enhancementNALs: Int64
        let packetSequenceSHA256: String
        let peakRecordBytes: Int, peakTrackedHeap: Int
        let expectedOutputMetadataSHA256: String?
        var supported: Bool { expectedOutputMetadataSHA256 != nil }
    }
    private let source: SourceFingerprint, sourceRole: Bool
    private var metadata = SHA256(), supported = true
    private var beginHeader: JSON.Object?
    private(set) var error: Error?
    private var line = Data(), rows = 0, began = false, resources = false, complete: Receipt?
    private var packets: Int64 = 0, records: Int64 = 0, peak = 0, heap = 0
    private var currentPTS: Int64 = 0, currentOffset: UInt64 = 0, currentBytes: UInt64 = 0
    private var nal: UInt64?, sequence = SHA256()
    init(source: SourceFingerprint, sourceRole: Bool = true) throws {
        guard (1...(1 << 40)).contains(source.byteCount) else { throw Self.refused() }
        _ = try DolbyInspection.hash(source.sha256)
        self.source = source; self.sourceRole = sourceRole
        metadata.update(data:Data("STAXRIP-P81-METADATA-1\0".utf8))
    }
    private static func refused() -> NativeExportError { .invalid("Native metadata stream refused. No successful settled result.") }
    func receive(_ data: Data) {
        guard error == nil else { return }
        do { try accept(data) } catch { self.error = error }
    }
    func accept(_ data: Data) throws {
        for byte in data {
            guard complete == nil else { throw Self.refused() }
            if byte == 10 {
                guard !line.isEmpty, rows < 4_000_003 else { throw Self.refused() }; rows += 1
                try consume(line); line.removeAll(keepingCapacity:true)
            } else { guard line.count < 65_535 else { throw Self.refused() }; line.append(byte) }
        }
    }
    func finish(status: Int32, packetSequence: String, header: DolbyInspectionHeader) throws -> Receipt {
        guard error == nil, status == 0, line.isEmpty, let complete,
              complete.packetSequenceSHA256 == packetSequence, let h = beginHeader,
              try n(h,"track_number") == header.trackNumber,
              try n(h,"timestamp_scale_ns") == header.timestampScaleNs,
              try n(h,"declared_pixel_width") == header.declaredPixelWidth,
              try n(h,"declared_pixel_height") == header.declaredPixelHeight,
              try n(h,"declared_display_unit") == header.declaredDisplayUnit,
              try n(h,"configuration_bytes") == header.configurationBytes,
              try JSON.digest(h,"configuration_sha256") == header.configurationSha256,
              try JSON.string(h,"parser") == header.parser,
              h["declared_crop_left_right_top_bottom"] == .array(header.declaredCropLeftRightTopBottom.map { .unsigned(UInt64($0)) }),
              h["declared_display_width_height"] == .array(header.declaredDisplayWidthHeight.map { $0.map { .unsigned(UInt64($0)) } ?? .null })
        else { throw Self.refused() }
        return complete
    }
    private func n(_ o: JSON.Object, _ key: String, _ range: ClosedRange<UInt64> = 0...UInt64.max) throws -> UInt64 { try JSON.unsigned(o,key,range) }
    private func optionalNumber(_ o: JSON.Object, _ key: String) throws -> UInt64? {
        switch o[key] { case .null?: return nil; case .unsigned(let n)? where n > 0: return n; default: throw Self.refused() }
    }
    private func optionalBool(_ o: JSON.Object, _ key: String) throws -> Bool? {
        switch o[key] { case .null?: return nil; case .bool(let b)?: return b; default: throw Self.refused() }
    }
    private func consume(_ data: Data) throws {
        let o = try JSON.metadataObject(data), kind = try JSON.string(o,"kind")
        guard !resources || kind == "complete" else { throw Self.refused() }
        switch kind {
        case "begin":
            guard !began, rows == 1, Set(o.keys) == ["kind","version","input_type","parser","track_number","timestamp_scale_ns","declared_pixel_width","declared_pixel_height","declared_crop_left_right_top_bottom","declared_display_width_height","declared_display_unit","default_duration_ns","nal_length_bytes","configuration_bytes","configuration_sha256","segment_unknown_size","packet_limit","file_limit","count_limit"],
                  try n(o,"version") == 2, try JSON.string(o,"input_type") == "matroska-hevc-packets", try JSON.string(o,"parser") == "libdovi 3.3.2",
                  try n(o,"track_number",1...(1 << 40)) > 0, try n(o,"timestamp_scale_ns",1...UInt64.max) > 0,
                  try n(o,"nal_length_bytes",1...4) > 0, try n(o,"configuration_bytes",23...(1 << 20)) >= 23,
                  try n(o,"packet_limit") == 16 << 20, try n(o,"file_limit") == 1 << 40, try n(o,"count_limit") == 2_000_000,
                  case .bool? = o["segment_unknown_size"] else { throw Self.refused() }
            _ = try JSON.digest(o,"configuration_sha256"); _ = try optionalNumber(o,"default_duration_ns")
            let w = try n(o,"declared_pixel_width",2...16384), h = try n(o,"declared_pixel_height",2...16384)
            _ = try n(o,"declared_display_unit",0...4)
            guard case .array(let crop)? = o["declared_crop_left_right_top_bottom"], crop.count == 4,
                  case .array(let display)? = o["declared_display_width_height"], display.count == 2 else { throw Self.refused() }
            var offsets: [UInt64] = []
            for v in crop { guard case .unsigned(let n) = v, n <= 16384 else { throw Self.refused() }; offsets.append(n) }
            guard offsets[0]+offsets[1] < w, offsets[2]+offsets[3] < h else { throw Self.refused() }
            for v in display {
                switch v { case .null: break; case .unsigned(let n) where (1...65536).contains(n): break; default: throw Self.refused() }
            }
            beginHeader = o; began = true
        case "packet":
            guard began, records == packets, Set(o.keys) == ["kind","index","input_byte_offset","block_input_byte_offset","pts_ns","duration_ns","invisible","keyframe","discardable","encoded_bytes","sha256"],
                  packets < 2_000_000, try n(o,"index") == UInt64(packets), case .bool? = o["invisible"] else { throw Self.refused() }
            let size = try n(o,"encoded_bytes",1...(16 << 20)), offset = try n(o,"input_byte_offset",1...UInt64(source.byteCount))
            guard size <= UInt64(source.byteCount)-offset, offset >= currentOffset+currentBytes,
                  try n(o,"block_input_byte_offset",1...offset) < offset else { throw Self.refused() }
            let k = try optionalBool(o,"keyframe"), d = try optionalBool(o,"discardable")
            guard (k == nil) == (d == nil) else { throw Self.refused() }; _ = try optionalNumber(o,"duration_ns")
            currentPTS = try JSON.signed(o,"pts_ns"); currentOffset = offset; currentBytes = size; nal = nil
            let digest = try JSON.digest(o,"sha256")
            sequence.update(data: DolbyInspection.proofRecord(pts:currentPTS,bytes:Int64(size),digest:try DolbyInspection.hash(digest))); packets += 1
        case "rpu":
            guard began, packets > 0, records < 2_000_000,
                  Set(o.keys) == ["kind","index","packet_index","nal_index","pts_ns","input_byte_offset","encoded_bytes","sha256","metadata"],
                  try n(o,"index") == UInt64(records), try n(o,"packet_index") == UInt64(packets-1), try JSON.signed(o,"pts_ns") == currentPTS else { throw Self.refused() }
            let ordinal = try n(o,"nal_index",0...(16 << 20)), size = try n(o,"encoded_bytes",25...65536), offset = try n(o,"input_byte_offset")
            guard nal.map({ ordinal > $0 }) ?? true, offset >= currentOffset+2, offset <= currentOffset+currentBytes,
                  size <= currentOffset+currentBytes-offset else { throw Self.refused() }
            _ = try JSON.digest(o,"sha256")
            guard records == packets-1, nal == nil else { throw Self.refused() }
            let raw = try DolbyP81Metadata.object(o["metadata"])
            do {
                let normalized = try DolbyP81Metadata.normalized(raw,source:sourceRole)
                metadata.update(data:DolbyCopyTiming.integers([records,packets-1,currentPTS]))
                DolbyP81Metadata.append(normalized,to:&metadata)
            } catch { supported = false } // Unsupported metadata never authorizes P8.1; wire checks still finish.
            nal = ordinal; records += 1; peak = max(peak,Int(size))
        case "resources":
            guard began, packets > 0, records == packets, !resources, Set(o.keys) == ["kind","heap_limit","peak_heap_bytes"],
                  try n(o,"heap_limit") == 67_108_864 else { throw Self.refused() }
            heap = Int(try n(o,"peak_heap_bytes",1...67_108_864)); resources = true
        case "complete":
            guard resources, Set(o.keys) == ["kind","version","packets","records","enhancement_nals","input_bytes","input_sha256","peak_record_bytes","source_recheck","packet_sequence_sha256"],
                  try n(o,"version") == 2, try n(o,"packets") == UInt64(packets), try n(o,"records") == UInt64(records),
                  try n(o,"input_bytes") == UInt64(source.byteCount), try JSON.digest(o,"input_sha256") == source.sha256,
                  try n(o,"peak_record_bytes") == UInt64(peak), try JSON.digest(o,"packet_sequence_sha256") == DolbyInspection.hex(sequence.finalize()) else { throw Self.refused() }
            try JSON.bool(o,"source_recheck",true)
            complete = .init(source:source,packets:packets,records:records,enhancementNALs:Int64(try n(o,"enhancement_nals",0...4_000_000_000_000)),
                             packetSequenceSHA256:try JSON.digest(o,"packet_sequence_sha256"),peakRecordBytes:peak,peakTrackedHeap:heap,expectedOutputMetadataSHA256:supported ? DolbyInspection.hex(metadata.finalize()) : nil)
        default: throw Self.refused()
        }
    }
}
