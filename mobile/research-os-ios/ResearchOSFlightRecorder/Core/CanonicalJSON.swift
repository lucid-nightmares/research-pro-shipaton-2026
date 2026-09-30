import CryptoKit
import CoreFoundation
import Foundation

/// JSON with an explicit value algebra so hashing never depends on dictionary order.
///
/// Integer payloads have exact Python `json.dumps(..., sort_keys=True,
/// separators=(",", ":"), ensure_ascii=False)` parity. Decimal values are supported,
/// but cross-runtime fixtures should prefer integer or string representations when
/// a scientific value has a required lexical form.
enum CanonicalJSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([CanonicalJSONValue])
    case object([String: CanonicalJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            guard value.isFinite else { throw CanonicalJSONError.nonFiniteNumber }
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([CanonicalJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: CanonicalJSONValue].self) {
            self = .object(value)
        } else {
            throw CanonicalJSONError.unsupportedValue
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .integer(value): try container.encode(value)
        case let .number(value):
            guard value.isFinite else { throw CanonicalJSONError.nonFiniteNumber }
            try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    init(jsonObject value: Any) throws {
        switch value {
        case is NSNull:
            self = .null
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else {
                let type = String(cString: value.objCType)
                if !type.contains("f") && !type.contains("d") {
                    self = .integer(value.int64Value)
                } else {
                    guard value.doubleValue.isFinite else { throw CanonicalJSONError.nonFiniteNumber }
                    self = .number(value.doubleValue)
                }
            }
        case let value as String:
            self = .string(value)
        case let value as [Any]:
            self = .array(try value.map(CanonicalJSONValue.init(jsonObject:)))
        case let value as [String: Any]:
            self = .object(try value.mapValues(CanonicalJSONValue.init(jsonObject:)))
        default:
            throw CanonicalJSONError.unsupportedValue
        }
    }

    var jsonObject: Any {
        switch self {
        case .null: return NSNull()
        case let .bool(value): return value
        case let .integer(value): return value
        case let .number(value): return value
        case let .string(value): return value
        case let .array(value): return value.map(\.jsonObject)
        case let .object(value): return value.mapValues(\.jsonObject)
        }
    }

    subscript(key: String) -> CanonicalJSONValue? {
        guard case let .object(value) = self else { return nil }
        return value[key]
    }

    var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    var integerValue: Int64? {
        guard case let .integer(value) = self else { return nil }
        return value
    }
}

enum CanonicalJSON {
    static func value<T: Encodable>(from value: T) throws -> CanonicalJSONValue {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        return try decodeValue(data)
    }

    static func decodeValue(_ data: Data) throws -> CanonicalJSONValue {
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try CanonicalJSONValue(jsonObject: object)
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encode(Self.value(from: value))
    }

    static func encode(_ value: CanonicalJSONValue) throws -> Data {
        Data(try render(value).utf8)
    }

    static func string<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try encode(value), as: UTF8.self)
    }

    static func digest<T: Encodable>(_ value: T) throws -> String {
        sha256(try encode(value))
    }

    static func digest(_ value: CanonicalJSONValue) throws -> String {
        sha256(try encode(value))
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func render(_ value: CanonicalJSONValue) throws -> String {
        switch value {
        case .null:
            return "null"
        case let .bool(value):
            return value ? "true" : "false"
        case let .integer(value):
            return String(value)
        case let .number(value):
            guard value.isFinite else { throw CanonicalJSONError.nonFiniteNumber }
            let data = try JSONSerialization.data(withJSONObject: [value], options: [.withoutEscapingSlashes])
            let wrapped = String(decoding: data, as: UTF8.self)
            return String(wrapped.dropFirst().dropLast())
        case let .string(value):
            return quote(value)
        case let .array(values):
            return "[" + (try values.map(render).joined(separator: ",")) + "]"
        case let .object(values):
            let fields = try values.keys.sorted().map { key in
                quote(key) + ":" + (try render(values[key]!))
            }
            return "{" + fields.joined(separator: ",") + "}"
        }
    }

    /// Matches Python's compact `ensure_ascii=False` escaping for valid Swift strings.
    private static func quote(_ value: String) -> String {
        var output = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x08: output += "\\b"
            case 0x09: output += "\\t"
            case 0x0A: output += "\\n"
            case 0x0C: output += "\\f"
            case 0x0D: output += "\\r"
            case 0x22: output += "\\\""
            case 0x5C: output += "\\\\"
            case 0x00 ... 0x1F: output += String(format: "\\u%04x", scalar.value)
            default: output.unicodeScalars.append(scalar)
            }
        }
        output += "\""
        return output
    }
}

enum CanonicalJSONError: LocalizedError {
    case nonFiniteNumber
    case unsupportedValue

    var errorDescription: String? {
        switch self {
        case .nonFiniteNumber: "Canonical JSON cannot contain NaN or infinity."
        case .unsupportedValue: "The value is not representable as strict JSON."
        }
    }
}
