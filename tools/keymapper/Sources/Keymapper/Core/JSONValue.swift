import Foundation

/// A lossless JSON value that preserves object key order and all keys, including unknown ones (D24).
/// Backed by a hand-rolled parser/serializer (Foundation's JSONSerialization does not preserve key order).
indirect enum JSONValue: Equatable {
    case object([(String, JSONValue)])
    case array([JSONValue])
    case string(String)
    case number(String)   // kept as the original literal text so numeric formatting is preserved
    case bool(Bool)
    case null

    // MARK: Equatable
    static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.object(let l), .object(let r)):
            guard l.count == r.count else { return false }
            for (a, b) in zip(l, r) where a.0 != b.0 || a.1 != b.1 { return false }
            return true
        case (.array(let l), .array(let r)): return l == r
        case (.string(let l), .string(let r)): return l == r
        case (.number(let l), .number(let r)): return l == r
        case (.bool(let l), .bool(let r)): return l == r
        case (.null, .null): return true
        default: return false
        }
    }

    // MARK: Accessors
    subscript(_ key: String) -> JSONValue? {
        if case .object(let pairs) = self { return pairs.first(where: { $0.0 == key })?.1 }
        return nil
    }
    subscript(_ index: Int) -> JSONValue? {
        if case .array(let items) = self, items.indices.contains(index) { return items[index] }
        return nil
    }
    var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }

    // MARK: Parsing
    static func parse(_ text: String) throws -> JSONValue {
        var parser = Parser(Array(text.unicodeScalars))
        let v = try parser.parseValue()
        parser.skipWhitespace()
        guard parser.isAtEnd else { throw JSONError.trailingGarbage(parser.index) }
        return v
    }

    // MARK: Serializing
    /// `indent == nil` -> compact. `indent == n` -> pretty, n spaces per level, matching Karabiner's style.
    func serialized(indent: Int?) -> String {
        var out = ""
        write(into: &out, indent: indent, level: 0)
        return out
    }

    private func write(into out: inout String, indent: Int?, level: Int) {
        let nl = indent == nil ? "" : "\n"
        let pad = indent == nil ? "" : String(repeating: " ", count: indent! * (level + 1))
        let closePad = indent == nil ? "" : String(repeating: " ", count: indent! * level)
        let colon = indent == nil ? ":" : ": "
        switch self {
        case .object(let pairs):
            if pairs.isEmpty { out += "{}"; return }
            out += "{" + nl
            for (i, (k, v)) in pairs.enumerated() {
                out += pad + JSONValue.encodeString(k) + colon
                v.write(into: &out, indent: indent, level: level + 1)
                out += (i == pairs.count - 1 ? "" : ",") + nl
            }
            out += closePad + "}"
        case .array(let items):
            if items.isEmpty { out += "[]"; return }
            out += "[" + nl
            for (i, v) in items.enumerated() {
                out += pad
                v.write(into: &out, indent: indent, level: level + 1)
                out += (i == items.count - 1 ? "" : ",") + nl
            }
            out += closePad + "]"
        case .string(let s): out += JSONValue.encodeString(s)
        case .number(let n): out += n
        case .bool(let b): out += b ? "true" : "false"
        case .null: out += "null"
        }
    }

    static func encodeString(_ s: String) -> String {
        var r = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": r += "\\\""
            case "\\": r += "\\\\"
            case "\n": r += "\\n"
            case "\t": r += "\\t"
            case "\r": r += "\\r"
            default:
                if scalar.value < 0x20 { r += String(format: "\\u%04x", scalar.value) }
                else { r.unicodeScalars.append(scalar) }
            }
        }
        return r + "\""
    }

    // MARK: Parser
    private struct Parser {
        let scalars: [Unicode.Scalar]
        var index = 0
        init(_ s: [Unicode.Scalar]) { scalars = s }
        var isAtEnd: Bool { index >= scalars.count }
        mutating func skipWhitespace() {
            while index < scalars.count, " \t\n\r".unicodeScalars.contains(scalars[index]) { index += 1 }
        }
        mutating func parseValue() throws -> JSONValue {
            skipWhitespace()
            guard index < scalars.count else { throw JSONError.unexpectedEnd }
            switch scalars[index] {
            case "{": return try parseObject()
            case "[": return try parseArray()
            case "\"": return .string(try parseString())
            case "t", "f": return try parseBool()
            case "n": try expect("null"); return .null
            default: return .number(try parseNumber())
            }
        }
        mutating func parseObject() throws -> JSONValue {
            index += 1 // {
            var pairs: [(String, JSONValue)] = []
            skipWhitespace()
            if index < scalars.count, scalars[index] == "}" { index += 1; return .object(pairs) }
            while true {
                skipWhitespace()
                let key = try parseString()
                skipWhitespace()
                guard index < scalars.count, scalars[index] == ":" else { throw JSONError.expectedColon(index) }
                index += 1
                let value = try parseValue()
                pairs.append((key, value))
                skipWhitespace()
                guard index < scalars.count else { throw JSONError.unexpectedEnd }
                if scalars[index] == "," { index += 1; continue }
                if scalars[index] == "}" { index += 1; break }
                throw JSONError.expectedCommaOrClose(index)
            }
            return .object(pairs)
        }
        mutating func parseArray() throws -> JSONValue {
            index += 1 // [
            var items: [JSONValue] = []
            skipWhitespace()
            if index < scalars.count, scalars[index] == "]" { index += 1; return .array(items) }
            while true {
                items.append(try parseValue())
                skipWhitespace()
                guard index < scalars.count else { throw JSONError.unexpectedEnd }
                if scalars[index] == "," { index += 1; continue }
                if scalars[index] == "]" { index += 1; break }
                throw JSONError.expectedCommaOrClose(index)
            }
            return .array(items)
        }
        mutating func parseString() throws -> String {
            guard index < scalars.count, scalars[index] == "\"" else { throw JSONError.expectedString(index) }
            index += 1
            var s = String.UnicodeScalarView()
            while index < scalars.count {
                let c = scalars[index]; index += 1
                if c == "\"" { return String(s) }
                if c == "\\" {
                    guard index < scalars.count else { throw JSONError.unexpectedEnd }
                    let e = scalars[index]; index += 1
                    switch e {
                    case "\"": s.append("\"")
                    case "\\": s.append("\\")
                    case "/": s.append("/")
                    case "n": s.append("\n")
                    case "t": s.append("\t")
                    case "r": s.append("\r")
                    case "b": s.append(Unicode.Scalar(8))
                    case "f": s.append(Unicode.Scalar(12))
                    case "u":
                        let hex = String(String.UnicodeScalarView(scalars[index..<min(index+4, scalars.count)]))
                        guard hex.count == 4, let code = UInt32(hex, radix: 16),
                              let scalar = Unicode.Scalar(code) else { throw JSONError.badEscape(index) }
                        s.append(scalar); index += 4
                    default: throw JSONError.badEscape(index)
                    }
                } else { s.append(c) }
            }
            throw JSONError.unexpectedEnd
        }
        mutating func parseNumber() throws -> String {
            let start = index
            while index < scalars.count, "+-0123456789.eE".unicodeScalars.contains(scalars[index]) { index += 1 }
            guard index > start else { throw JSONError.invalidNumber(index) }
            return String(String.UnicodeScalarView(scalars[start..<index]))
        }
        mutating func parseBool() throws -> JSONValue {
            if scalars[index] == "t" { try expect("true"); return .bool(true) }
            try expect("false"); return .bool(false)
        }
        mutating func expect(_ word: String) throws {
            for ch in word.unicodeScalars {
                guard index < scalars.count, scalars[index] == ch else { throw JSONError.invalidLiteral(index) }
                index += 1
            }
        }
    }
}

enum JSONError: Error, Equatable {
    case unexpectedEnd, trailingGarbage(Int), expectedColon(Int), expectedCommaOrClose(Int)
    case expectedString(Int), badEscape(Int), invalidNumber(Int), invalidLiteral(Int)
}
