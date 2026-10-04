import Foundation

/// Single-owner pipe parser only. The future controller must own/settle the process,
/// verify actual files and original semantics, and establish fixed tool provenance.
final class CompanionWriterProtocol {
    typealias Transaction = OriginalCompanionTransaction
    struct Receipt: Sendable {
        let contents: Transaction.Contents
        let peakTrackedHeap: Int
    }
    enum Event { case ready, staged }
    private enum State { case waiting, ready, started, staged, finished, refused }
    private var state = State.waiting
    private var line = Data()
    private var receipt: Receipt?
    private let operation: String
    private let retention: Transaction.Retention
    private let sourceID, stageID: Transaction.FileID
    private let sourceBytes: Int64
    private var mode: String { retention == .metadataOnly ? "metadata" : "full" }
    private static func failure() -> NativeExportError { .invalid("Companion writer protocol refused. No successful receipt.") }
    private static func hex(_ value: String, length: Int) -> Bool {
        value.utf8.count == length && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    init(operation: String, retention: Transaction.Retention, sourceID: Transaction.FileID,
         stageID: Transaction.FileID, sourceBytes: Int64) throws {
        guard Self.hex(operation, length: 32), (1...Int64(1 << 40)).contains(sourceBytes) else { throw Self.failure() }
        self.operation = operation; self.retention = retention; self.sourceID = sourceID
        self.stageID = stageID; self.sourceBytes = sourceBytes
    }
    /// Accept only the small ASCII subset emitted by the fixed Rust writer, not
    /// arbitrary JSON documents. Duplicate keys are rejected before schema checks.
    func accept(_ data: Data) throws -> [Event] {
        do {
            var events: [Event] = []
            for byte in data {
                guard state != .staged && state != .finished && state != .refused else { throw Self.failure() }
                if byte == 10 {
                    guard !line.isEmpty else { throw Self.failure() }
                    let object = try ASCIIJSON.object(line)
                    events.append(try consume(object)); line.removeAll(keepingCapacity: true)
                } else {
                    // 16 KiB including LF, matching the writer's emitted row bound.
                    guard line.count < 16_383 else { throw Self.failure() }
                    line.append(byte)
                }
            }
            return events
        } catch { state = .refused; receipt = nil; line.removeAll(); throw Self.failure() }
    }
    func authorizeStart() throws -> Data {
        guard state == .ready, line.isEmpty else { state = .refused; receipt = nil; throw Self.failure() }
        state = .started
        return Data("start \(operation)\n".utf8)
    }
    /// Status alone cannot replace complete stdout EOF. Controller calls this only
    /// after its child/pipe workers settle; this parser cannot prove that ownership.
    func finish(status: Int32) throws -> Receipt {
        guard state == .staged, line.isEmpty, status == 0, let receipt else {
            state = .refused; self.receipt = nil; throw Self.failure()
        }
        state = .finished; self.receipt = nil; return receipt
    }
    private func consume(_ o: [String: ASCIIJSON.Value]) throws -> Event {
        func string(_ key: String) throws -> String { guard case .string(let s)? = o[key] else { throw Self.failure() }; return s }
        func number(_ key: String, _ range: ClosedRange<UInt64>) throws -> UInt64 {
            guard case .number(let n)? = o[key], range.contains(n) else { throw Self.failure() }; return n
        }
        func id(_ key: String, _ expected: Transaction.FileID) throws {
            guard case .array(let v)? = o[key], v.count == 2,
                  case .number(let dev) = v[0], case .number(let ino) = v[1],
                  dev == expected.device, ino == expected.inode else { throw Self.failure() }
        }
        guard try number("protocol", 1...1) == 1, try string("operation") == operation else { throw Self.failure() }
        if state == .waiting {
            guard Set(o.keys) == ["kind", "protocol", "operation"], try string("kind") == "ready" else { throw Self.failure() }
            state = .ready; return .ready
        }
        let keys: Set<String> = ["kind", "protocol", "operation", "retention", "source_file_id", "stage_file_id",
            "source_bytes", "source_sha256", "packets", "records", "enhancement_nals", "components",
            "heap_limit", "peak_heap_bytes", "semantic_verification"]
        guard state == .started, Set(o.keys) == keys, try string("kind") == "staged",
              try string("retention") == mode, case .bool(false)? = o["semantic_verification"] else { throw Self.failure() }
        try id("source_file_id", sourceID); try id("stage_file_id", stageID)
        let bytes = try number("source_bytes", 1...UInt64(1 << 40))
        guard bytes == UInt64(sourceBytes) else { throw Self.failure() }
        let digest = try string("source_sha256")
        guard Self.hex(digest, length: 64) else { throw Self.failure() }
        let packets = try number("packets", 1...2_000_000), records = try number("records", 1...2_000_000)
        let enhancement = try number("enhancement_nals", 0...4_000_000_000_000)
        _ = try number("heap_limit", 67_108_864...67_108_864)
        let peak = try number("peak_heap_bytes", 1...67_108_864)
        let limits = retention.limits
        guard case .array(let components)? = o["components"], components.count == limits.count else { throw Self.failure() }
        var members: [ResultSetStaging.Member] = [], names: Set<String> = []
        for component in components {
            guard case .object(let m) = component, Set(m.keys) == ["name", "bytes", "sha256"],
                  case .string(let name)? = m["name"], let maximum = limits[name], names.insert(name).inserted,
                  case .number(let size)? = m["bytes"], (1...UInt64(maximum)).contains(size),
                  case .string(let sha)? = m["sha256"], Self.hex(sha, length: 64) else { throw Self.failure() }
            members.append(.init(name: name, byteCount: Int64(size), sha256: sha))
        }
        guard names == Set(limits.keys) else { throw Self.failure() }
        receipt = .init(contents: .init(retention: retention, sourceID: sourceID, stageID: stageID,
            sourceBytes: sourceBytes, sourceSHA256: digest, packets: Int64(packets), records: Int64(records),
            enhancementNALs: Int64(enhancement), members: members), peakTrackedHeap: Int(peak))
        state = .staged; return .staged
    }
}

/// Private bounded protocol grammar. All current Rust fields are printable ASCII
/// without escapes, positive/zero unsigned decimal integers, arrays or booleans.
/// Rejecting escapes, signed/fraction/exponent numbers and null is deliberate.
private struct ASCIIJSON {
    indirect enum Value { case object([String: Value]), array([Value]), string(String), number(UInt64), bool(Bool) }
    let bytes: [UInt8]
    var position = 0
    static func object(_ data: Data) throws -> [String: Value] {
        var reader = Self(bytes: Array(data)); let value = try reader.value(depth: 0); reader.space()
        guard reader.position == reader.bytes.count, case .object(let object) = value else { throw refused() }; return object
    }
    private static func refused() -> NativeExportError { .invalid("Companion writer protocol refused. No successful receipt.") }
    private mutating func space() { while position < bytes.count && [9, 13, 32].contains(bytes[position]) { position += 1 } }
    private mutating func take(_ b: UInt8) -> Bool { space(); guard position < bytes.count, bytes[position] == b else { return false }; position += 1; return true }
    private mutating func text() throws -> String {
        guard take(34) else { throw Self.refused() }; let start = position
        while position < bytes.count && bytes[position] != 34 {
            guard (32...126).contains(bytes[position]), bytes[position] != 92, position - start < 128 else { throw Self.refused() }; position += 1
        }
        guard position < bytes.count else { throw Self.refused() }
        let result = String(decoding: bytes[start..<position], as: UTF8.self); position += 1; return result
    }
    private mutating func value(depth: Int) throws -> Value {
        space(); guard depth <= 4, position < bytes.count else { throw Self.refused() }
        if bytes[position] == 123 {
            position += 1; var object: [String: Value] = [:]
            if take(125) { return .object(object) }
            repeat {
                guard object.count < 20 else { throw Self.refused() }
                let key = try text(); guard object[key] == nil, take(58) else { throw Self.refused() }
                object[key] = try value(depth: depth + 1)
                if take(125) { return .object(object) }
                guard take(44) else { throw Self.refused() }
            } while true
        }
        if bytes[position] == 91 {
            position += 1; var array: [Value] = []
            if take(93) { return .array(array) }
            repeat {
                guard array.count < 16 else { throw Self.refused() }
                array.append(try value(depth: depth + 1))
                if take(93) { return .array(array) }
                guard take(44) else { throw Self.refused() }
            } while true
        }
        if bytes[position] == 34 { return .string(try text()) }
        for (word, b) in [(Array("true".utf8), true), (Array("false".utf8), false)] {
            if bytes[position...].starts(with: word) { position += word.count; return .bool(b) }
        }
        let start = position
        while position < bytes.count && (48...57).contains(bytes[position]) {
            guard position - start < 20 else { throw Self.refused() }; position += 1
        }
        guard position > start, !(position - start > 1 && bytes[start] == 48),
              let number = UInt64(String(decoding: bytes[start..<position], as: UTF8.self)) else { throw Self.refused() }
        return .number(number)
    }
}
