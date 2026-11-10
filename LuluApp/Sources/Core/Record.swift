import Foundation

enum JSONValue: Codable, Equatable {
    case string(String), number(Double), bool(Bool), array([JSONValue]), object([String: JSONValue]), null

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let item = try? value.decode(Bool.self) { self = .bool(item) }
        else if let item = try? value.decode(Double.self) { self = .number(item) }
        else if let item = try? value.decode(String.self) { self = .string(item) }
        else if let item = try? value.decode([JSONValue].self) { self = .array(item) }
        else { self = .object(try value.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .string(let item): try value.encode(item)
        case .number(let item): try value.encode(item)
        case .bool(let item): try value.encode(item)
        case .array(let item): try value.encode(item)
        case .object(let item): try value.encode(item)
        case .null: try value.encodeNil()
        }
    }

    var string: String { if case .string(let item) = self { return item }; return "" }
    var number: Double { if case .number(let item) = self { return item }; return 0 }
    var bool: Bool { if case .bool(let item) = self { return item }; return false }
    var array: [JSONValue] { if case .array(let item) = self { return item }; return [] }
    var object: [String: JSONValue] { if case .object(let item) = self { return item }; return [:] }
}

struct Record: Codable, Equatable, Identifiable {
    var values: [String: JSONValue]
    init(_ values: [String: JSONValue] = [:]) { self.values = values }
    init(from decoder: Decoder) throws { values = try [String: JSONValue](from: decoder) }
    func encode(to encoder: Encoder) throws { try values.encode(to: encoder) }
    var id: String { string("id") }
    subscript(_ key: String) -> JSONValue {
        get { values[key] ?? .null }
        set { values[key] = newValue }
    }
    func string(_ key: String, fallback: String = "") -> String {
        let result = self[key].string
        return result.isEmpty ? fallback : result
    }
    func number(_ key: String) -> Double { self[key].number }
    func int(_ key: String) -> Int {
        let value = number(key)
        guard value.isFinite, value >= Double(Int.min), value < Double(Int.max) else { return 0 }
        return Int(value)
    }
    func bool(_ key: String) -> Bool { self[key].bool }
    func records(_ key: String) -> [Record] { self[key].array.map { Record($0.object) } }
    func strings(_ key: String) -> [String] { self[key].array.map(\.string) }
    func record(_ key: String) -> Record { Record(self[key].object) }
    var json: JSONValue { .object(values) }
}
