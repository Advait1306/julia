import Foundation

public enum JSONValue: Codable, Sendable, Equatable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public var string: String? { if case .string(let v) = self { return v }; return nil }
    public var object: [String: JSONValue]? { if case .object(let v) = self { return v }; return nil }
    public var array: [JSONValue]? { if case .array(let v) = self { return v }; return nil }
    public var integer: Int? {
        if case .number(let v) = self, v.isFinite, v.rounded() == v, v > Double(Int.min), v < Double(Int.max) { return Int(v) }
        return nil
    }
    public var boolean: Bool? { if case .bool(let v) = self { return v }; return nil }
    public subscript(_ key: String) -> JSONValue { object?[key] ?? .null }
    public var json: String {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? String(decoding: e.encode(self), as: UTF8.self)) ?? "null"
    }
    public init(any: Any) throws {
        let data = try JSONSerialization.data(withJSONObject: any, options: [.fragmentsAllowed])
        self = try JSONDecoder().decode(Self.self, from: data)
    }
    public static func parse(_ text: String) throws -> Self {
        try JSONDecoder().decode(Self.self, from: Data(text.utf8))
    }
}

public struct JuliaError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

extension Dictionary where Key == String, Value == JSONValue {
    func string(_ key: String) throws -> String {
        guard let v = self[key]?.string else { throw JuliaError("Missing string argument: \(key)") }; return v
    }
    func int(_ key: String) throws -> Int {
        guard let v = self[key]?.integer else { throw JuliaError("Missing integer argument: \(key)") }; return v
    }
}
