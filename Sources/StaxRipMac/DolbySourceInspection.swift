import Foundation
import CryptoKit

struct DolbyActiveArea: Hashable, Sendable {
    let left: Int, right: Int, top: Int, bottom: Int
    init(_ offsets: [Int]) throws {
        guard offsets.count == 4, offsets.allSatisfy({ (0...8191).contains($0) }) else {
            throw DolbyInspection.failure("Invalid active-area declaration.")
        }
        (left, right, top, bottom) = (offsets[0], offsets[1], offsets[2], offsets[3])
    }
}

struct DolbySourceReport: Sendable {
    let header: DolbyInspectionHeader
    let packets: Int, records: Int, sceneRefreshes: Int, enhancementNALs: Int
    let packetsWithoutRPU: Int, packetsWithMultipleRPUs: Int
    let mappings: [String: Int], activeAreas: [DolbyActiveArea: Int]
    let cmv29Records: Int, cmv40Records: Int
    let source: SourceFingerprint
    let packetSequenceSHA256: String
    let peakTrackedHeap: Int
}

struct DolbyInspectionHeader: Decodable, Sendable {
    let version: Int, inputType: String, parser: String, trackNumber: Int64
    let declaredPixelWidth: Int, declaredPixelHeight: Int
    let declaredCropLeftRightTopBottom: [Int]
    let declaredDisplayWidthHeight: [Int?], declaredDisplayUnit: Int
    let timestampScaleNs: Int64, configurationSha256: String, configurationBytes: Int
}

enum DolbyInspection {
    static let maximumPackets = 2_000_000
    static let maximumFileBytes: Int64 = 1_099_511_627_776
    static let maximumPacketBytes: Int64 = 16 * 1024 * 1024
    static func failure(_ reason: String) -> NativeExportError { .invalid("Dolby Vision inspection: " + reason) }
    static func hash(_ value: String) throws -> Data { try VideoCopyPacket.hash("SHA256:" + value) }
    static func hex(_ digest: SHA256.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }
    static func proofRecord(pts: Int64, bytes: Int64, digest: Data) -> Data {
        var result = Data()
        for value in [pts, bytes] {
            var number = value.littleEndian
            withUnsafeBytes(of: &number) { result.append(contentsOf: $0) }
        }
        result.append(digest); return result
    }
    static func bundledHelper() -> URL? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/staxrip-dolby-metadata-audit")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }
    static func eligible(_ probe: MediaProbe) -> Bool {
        probe.video?.codec_name == "hevc" &&
            (probe.format?.format_name?.split(separator: ",").contains("matroska") ?? false)
    }

    static func read(source: URL, probe: MediaProbe, helper: URL, tools: FFmpegTools,
                     copyVerification: Bool = false, copyRole: DolbyCopyNative.Role = .source, progress: @escaping @Sendable (String) -> Void = { _ in }) async throws -> DolbySourceReport {
        guard copyRole == .source || (copyVerification && copyRole == .p81Output),
              source.isFileURL, !source.path.utf8.contains(0), eligible(probe), let video = probe.video,
              let base = video.time_base else { throw failure("Full inspection currently requires Matroska HEVC with reported timing.") }
        let parts = base.split(separator: "/")
        guard parts.count == 2, let numerator = Int64(parts[0]), let denominator = Int64(parts[1]),
              numerator > 0, numerator <= 1_000_000, denominator > 0 else { throw failure("Unsupported packet time base.") }
        let scaled = numerator.multipliedReportingOverflow(by: 1_000_000_000)
        guard !scaled.overflow, scaled.partialValue % denominator == 0 else { throw failure("The independent packet timestamps cannot be expressed exactly in nanoseconds.") }
        let tick = scaled.partialValue / denominator
        // Copy execution owns source access outside this helper through all
        // uncertainty; this optional inner scope belongs only to legacy inspection.
        let checkedReaders = copyVerification
        let scoped = copyVerification ? false : source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        progress("Reading Dolby metadata and checking source integrity…")
        let runner = ToolRunner(checkedReaders: checkedReaders)
        let stream = DolbyInspectionStream(failed: { runner.cancel() })
        let result: ToolResult
        do {
            result = try await runner.run(executable: helper, arguments: ["mkv-summary", source.path], stdoutLimit: 0) { stream.accept($0) }
        } catch var error as ToolRunner.ReaderCloseFailure {
            error.consumerCause = stream.error; throw error
        } catch {
            if error is any CompanionUnsettledOwnership { throw error }
            try Task.checkCancellation()
            if let error = stream.error { throw error }
            throw error
        }
        try Task.checkCancellation()
        let observed = try stream.finish(status: result.status)
        guard video.extradata_size == observed.header.configurationBytes,
              video.extradata_hash == "SHA256:" + observed.header.configurationSha256 else {
            throw failure("The selected stream configuration changed or disagrees with the source reader.")
        }
        progress("Checking video packets independently…")
        let referenceRunner = ToolRunner(checkedReaders: checkedReaders)
        let reference = DolbyPacketProof(tick: tick)
        let referenceStream = VideoCopyPacketStream(failed: { referenceRunner.cancel() }) { try reference.accept($0) }
        let independent: ToolResult
        do {
            independent = try await referenceRunner.run(executable: tools.ffprobe,
                arguments: ["-v", "error", "-protocol_whitelist", "file,pipe", "-select_streams", String(video.index),
                    "-show_packets", "-show_entries", "packet=pts,duration,size,data_hash", "-show_data_hash", "sha256",
                    "-of", "compact=p=0:nk=0", source.path], stdoutLimit: 0) { referenceStream.accept($0) }
        } catch var error as ToolRunner.ReaderCloseFailure {
            error.consumerCause = referenceStream.error; throw error
        } catch {
            if error is any CompanionUnsettledOwnership { throw error }
            try Task.checkCancellation()
            if let error = referenceStream.error { throw error }
            throw error
        }
        try Task.checkCancellation()
        try referenceStream.finish()
        guard independent.status == 0, reference.count == observed.packets,
              reference.digest == observed.packetSequenceSHA256 else {
            throw failure("Independent video packet payloads or timestamps disagree. The source is not qualified.")
        }
        progress("Rechecking source content…")
        let final: SourceFingerprint
        if checkedReaders { final = try await ExportSourceFingerprint.readCopy(source, role: copyRole, timeBase: HDRFraction(base)).0 }
        else { final = try await ExportSourceFingerprint.read(source) }
        try Task.checkCancellation()
        guard final == observed.source else { throw failure("Source content changed during independent inspection.") }
        return observed
    }
}

// accept is called by one drained stdout reader; finish runs after process and
// readers have joined. No full metadata, packet array or raw payload is retained.
final class DolbyInspectionStream: @unchecked Sendable {
    private struct Kind: Decodable { let kind: String }
    private struct Packet: Decodable {
        let index: Int, ptsNs: Int64, encodedBytes: Int64, sha256: String, inputByteOffset: Int64
    }
    private struct Summary: Decodable {
        let mappingProfile: Int, enhancementType: String?, sceneRefresh: Bool?
        let activeAreasLeftRightTopBottom: [[Int]], cmv29Present: Bool, cmv40Present: Bool
    }
    private struct RPU: Decodable {
        let index: Int, packetIndex: Int, nalIndex: Int, ptsNs: Int64, encodedBytes: Int, sha256: String
        let summary: Summary
    }
    private struct Resources: Decodable { let heapLimit: Int, peakHeapBytes: Int }
    private struct Receipt: Decodable {
        let version: Int, packets: Int, records: Int, enhancementNals: Int
        let inputBytes: Int64, inputSha256: String, packetSequenceSha256: String
        let peakRecordBytes: Int, sourceRecheck: Bool
    }
    private let decoder: JSONDecoder = { let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d }()
    private let failed: () -> Void
    private var line = Data()
    private var header: DolbyInspectionHeader?, resources: Resources?, receipt: Receipt?
    private var packets = 0, records = 0, scenes = 0, cm29 = 0, cm40 = 0, missing = 0, multiple = 0
    private var current: Packet?, currentRecords = 0, previousNAL = -1, peakRecord = 0
    private var areas: [DolbyActiveArea: Int] = [:], mappings: [String: Int] = [:]
    private var hasher = SHA256()
    private(set) var error: Error?
    init(failed: @escaping () -> Void = {}) { self.failed = failed }
    func accept(_ data: Data) {
        guard error == nil else { return }
        do {
            for byte in data {
                if byte == 10 {
                    guard !line.isEmpty, receipt == nil else { throw DolbyInspection.failure("Unexpected or empty protocol record.") }
                    try consume(line); line.removeAll(keepingCapacity: true)
                } else {
                    guard line.count < 64 * 1024 else { throw DolbyInspection.failure("Inspection record exceeds its supported bound.") }
                    line.append(byte)
                }
            }
        } catch {
            // Decoder errors can contain source-derived details. Retain only the
            // explicit domain error or a generic invalid-protocol explanation.
            self.error = (error as? NativeExportError) ?? DolbyInspection.failure("Invalid inspection protocol.")
            failed()
        }
    }
    private func closePacket() {
        if current != nil {
            if currentRecords == 0 { missing += 1 }
            if currentRecords > 1 { multiple += 1 }
        }
        currentRecords = 0; previousNAL = -1
    }
    private func consume(_ data: Data) throws {
        let kind = try decoder.decode(Kind.self, from: data).kind
        if resources != nil, kind != "complete" { throw DolbyInspection.failure("Unexpected record after resource settlement.") }
        switch kind {
        case "begin":
            let h = try decoder.decode(DolbyInspectionHeader.self, from: data)
            guard header == nil, packets == 0, h.version == 3, h.inputType == "matroska-hevc-summary",
                  h.parser == "libdovi 3.3.2", h.trackNumber > 0,
                  (2...16384).contains(h.declaredPixelWidth), (2...16384).contains(h.declaredPixelHeight),
                  h.declaredCropLeftRightTopBottom.count == 4,
                  h.declaredCropLeftRightTopBottom.allSatisfy({ (0...16384).contains($0) }),
                  h.declaredCropLeftRightTopBottom[0] + h.declaredCropLeftRightTopBottom[1] < h.declaredPixelWidth,
                  h.declaredCropLeftRightTopBottom[2] + h.declaredCropLeftRightTopBottom[3] < h.declaredPixelHeight,
                  h.declaredDisplayWidthHeight.count == 2,
                  h.declaredDisplayWidthHeight.compactMap({ $0 }).allSatisfy({ (1...65536).contains($0) }),
                  (0...4).contains(h.declaredDisplayUnit), h.timestampScaleNs > 0,
                  (23...1_048_576).contains(h.configurationBytes) else { throw DolbyInspection.failure("Unsupported inspection header.") }
            _ = try DolbyInspection.hash(h.configurationSha256); header = h
        case "packet":
            let p = try decoder.decode(Packet.self, from: data)
            guard header != nil, p.index == packets, packets < DolbyInspection.maximumPackets,
                  p.encodedBytes > 0, p.encodedBytes <= DolbyInspection.maximumPacketBytes,
                  p.inputByteOffset > 0, p.inputByteOffset <= DolbyInspection.maximumFileBytes - p.encodedBytes,
                  current.map({ p.inputByteOffset > $0.inputByteOffset }) ?? true else { throw DolbyInspection.failure("Invalid or reordered video packet.") }
            let hash = try DolbyInspection.hash(p.sha256)
            closePacket(); current = p; packets += 1
            hasher.update(data: DolbyInspection.proofRecord(pts: p.ptsNs, bytes: p.encodedBytes, digest: hash))
        case "rpu-summary":
            let r = try decoder.decode(RPU.self, from: data)
            guard let current, r.index == records, records < DolbyInspection.maximumPackets,
                  r.packetIndex == current.index, r.ptsNs == current.ptsNs, r.nalIndex > previousNAL,
                  (25...65536).contains(r.encodedBytes), (0...10).contains(r.summary.mappingProfile),
                  r.summary.activeAreasLeftRightTopBottom.count <= 4,
                  r.summary.enhancementType == nil || ["MEL", "FEL"].contains(r.summary.enhancementType!) else {
                throw DolbyInspection.failure("Invalid metadata association or summary.")
            }
            _ = try DolbyInspection.hash(r.sha256)
            for offsets in r.summary.activeAreasLeftRightTopBottom {
                let area = try DolbyActiveArea(offsets)
                guard areas[area] != nil || areas.count < 256 else { throw DolbyInspection.failure("Too many distinct active-area declarations.") }
                areas[area, default: 0] += 1
            }
            let key = "\(r.summary.mappingProfile):\(r.summary.enhancementType ?? "none")"
            mappings[key, default: 0] += 1
            if r.summary.sceneRefresh == true { scenes += 1 }
            if r.summary.cmv29Present { cm29 += 1 }; if r.summary.cmv40Present { cm40 += 1 }
            currentRecords += 1; previousNAL = r.nalIndex; records += 1; peakRecord = max(peakRecord, r.encodedBytes)
        case "resources":
            let r = try decoder.decode(Resources.self, from: data)
            guard header != nil, packets > 0, resources == nil, r.heapLimit == 67_108_864,
                  (0...r.heapLimit).contains(r.peakHeapBytes) else { throw DolbyInspection.failure("Invalid resource receipt.") }
            resources = r
        case "complete":
            let r = try decoder.decode(Receipt.self, from: data)
            guard resources != nil, r.version == 3, r.packets == packets, r.records == records,
                  r.inputBytes > 0, r.inputBytes <= DolbyInspection.maximumFileBytes,
                  r.enhancementNals >= 0, r.enhancementNals <= 128_000_000,
                  r.peakRecordBytes == peakRecord, r.sourceRecheck,
                  r.packetSequenceSha256 == DolbyInspection.hex(hasher.finalize()) else {
                throw DolbyInspection.failure("Incomplete or inconsistent source receipt.")
            }
            _ = try DolbyInspection.hash(r.inputSha256); closePacket(); receipt = r
        default: throw DolbyInspection.failure("Unsupported inspection protocol record.")
        }
    }
    func finish(status: Int32) throws -> DolbySourceReport {
        if let error { throw error }
        guard status == 0, line.isEmpty, let header, let resources, let receipt else {
            throw DolbyInspection.failure("Inspection did not complete successfully. Partial records are not a result.")
        }
        return DolbySourceReport(header: header, packets: packets, records: records, sceneRefreshes: scenes,
            enhancementNALs: receipt.enhancementNals, packetsWithoutRPU: missing, packetsWithMultipleRPUs: multiple,
            mappings: mappings, activeAreas: areas, cmv29Records: cm29, cmv40Records: cm40,
            source: SourceFingerprint(sha256: receipt.inputSha256, byteCount: receipt.inputBytes),
            packetSequenceSHA256: receipt.packetSequenceSha256, peakTrackedHeap: resources.peakHeapBytes)
    }
}

// One independent stdout reader owns this incremental digest until it has joined.
final class DolbyPacketProof: @unchecked Sendable {
    private let tick: Int64
    private var hasher = SHA256()
    private(set) var count = 0
    var digest: String { DolbyInspection.hex(hasher.finalize()) }
    init(tick: Int64) { self.tick = tick }
    func accept(_ packet: VideoCopyPacket) throws {
        let pts = packet.pts.multipliedReportingOverflow(by: tick)
        guard !pts.overflow, count < DolbyInspection.maximumPackets,
              packet.size > 0, packet.size <= DolbyInspection.maximumPacketBytes else {
            throw DolbyInspection.failure("Unsupported independent packet bounds.")
        }
        hasher.update(data: DolbyInspection.proofRecord(pts: pts.partialValue, bytes: packet.size, digest: packet.digest)); count += 1
    }
}
