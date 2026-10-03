import Foundation
import Darwin

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
