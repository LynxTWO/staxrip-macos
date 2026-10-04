import Foundation

/// Bounded grammar for fixed version-zero index/manifest fields emitted by the
/// trusted producer. This is deliberately not a general JSON/session importer.
/// No escaped/non-ASCII strings, floating numbers, exponents, negative zero or null outside the audit-only nullable grammar.
/// Signed integer PTS are distinct from booleans and preserve Int64.min exactly.
struct CompanionArchiveJSON {
    indirect enum Value: Equatable { case object([String: Value]), array([Value]), string(String), unsigned(UInt64), signed(Int64), bool(Bool), null }
    typealias Object = [String: Value]
    private let bytes: [UInt8]
    private var auditNullable = false
    private var position = 0, nodes = 0
    static func refused() -> NativeExportError { .invalid("Original index/manifest JSON refused. No complete semantic receipt.") }
    static func object(_ data: Data, maximum: Int, auditNullable: Bool = false) throws -> Object {
        guard !data.isEmpty, data.count <= maximum, maximum <= 1 << 20 else { throw refused() }
        var reader = Self(bytes: Array(data), auditNullable: auditNullable); let value = try reader.value(depth: 0); reader.space()
        guard reader.position == reader.bytes.count, case .object(let object) = value else { throw refused() }; return object
    }
    static func string(_ object: Object, _ key: String) throws -> String {
        guard case .string(let s)? = object[key] else { throw refused() }; return s
    }
    static func unsigned(_ object: Object, _ key: String, _ range: ClosedRange<UInt64>) throws -> UInt64 {
        guard case .unsigned(let n)? = object[key], range.contains(n) else { throw refused() }; return n
    }
    static func signed(_ object: Object, _ key: String) throws -> Int64 {
        switch object[key] {
        case .signed(let n)?: return n
        case .unsigned(let n)?: guard n <= UInt64(Int64.max) else { throw refused() }; return Int64(n)
        default: throw refused()
        }
    }
    static func bool(_ object: Object, _ key: String, _ expected: Bool) throws {
        guard case .bool(let b)? = object[key], b == expected else { throw refused() }
    }
    static func digest(_ object: Object, _ key: String) throws -> String {
        let s = try string(object, key)
        guard s.utf8.count == 64, s.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw refused() }; return s
    }
    private mutating func space() { while position < bytes.count && [9,10,13,32].contains(bytes[position]) { position += 1 } }
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
        space(); guard depth <= 4, nodes < 256, position < bytes.count else { throw Self.refused() }; nodes += 1
        if bytes[position] == 123 {
            position += 1; var object: Object = [:]
            if take(125) { return .object(object) }
            repeat {
                guard object.count < 20 else { throw Self.refused() }
                let key = try text(); guard object[key] == nil, take(58) else { throw Self.refused() }
                object[key] = try value(depth: depth + 1)
                if take(125) { return .object(object) }; guard take(44) else { throw Self.refused() }
            } while true
        }
        if bytes[position] == 91 {
            position += 1; var array: [Value] = []
            if take(93) { return .array(array) }
            repeat {
                guard array.count < 16 else { throw Self.refused() }; array.append(try value(depth: depth + 1))
                if take(93) { return .array(array) }; guard take(44) else { throw Self.refused() }
            } while true
        }
        if bytes[position] == 34 { return .string(try text()) }
        for (word, b) in [(Array("true".utf8), true), (Array("false".utf8), false)] {
            if bytes[position...].starts(with: word) { position += word.count; return .bool(b) }
        }
        if auditNullable, bytes[position...].starts(with: Array("null".utf8)) { position += 4; return .null }
        let negative = bytes[position] == 45
        if negative { position += 1 }
        let start = position
        while position < bytes.count && (48...57).contains(bytes[position]) {
            guard position - start < 20 else { throw Self.refused() }; position += 1
        }
        guard position > start, !(position - start > 1 && bytes[start] == 48),
              let magnitude = UInt64(String(decoding: bytes[start..<position], as: UTF8.self)) else { throw Self.refused() }
        if negative {
            guard magnitude > 0, magnitude <= UInt64(Int64.max) + 1 else { throw Self.refused() }
            return .signed(magnitude == UInt64(Int64.max) + 1 ? Int64.min : -Int64(magnitude))
        }
        return .unsigned(magnitude)
    }
}
