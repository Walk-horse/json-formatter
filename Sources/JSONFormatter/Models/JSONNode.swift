import Foundation

struct JSONMember {
    var key: String
    var value: JSONNode
}

indirect enum JSONNode {
    case object([JSONMember])
    case array([JSONNode])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    var isContainer: Bool {
        switch self {
        case .object, .array: return true
        default: return false
        }
    }

    var childCount: Int {
        switch self {
        case .object(let members): return members.count
        case .array(let items): return items.count
        default: return 0
        }
    }

    /// 序列化为文本。compact = true 输出单行。
    func serialized(indent: Int = 2, compact: Bool = false) -> String {
        var out = ""
        append(to: &out, level: 0, indent: indent, compact: compact)
        return out
    }

    private func append(to out: inout String, level: Int, indent: Int, compact: Bool) {
        switch self {
        case .null:
            out += "null"
        case .bool(let value):
            out += value ? "true" : "false"
        case .number(let raw):
            out += raw
        case .string(let value):
            out += JSONNode.escape(value)
        case .object(let members):
            if members.isEmpty {
                out += compact ? "{}" : "{}"
                return
            }
            let inner = String(repeating: " ", count: (level + 1) * indent)
            let outer = String(repeating: " ", count: level * indent)
            out += "{"
            if !compact { out += "\n" }
            for (index, member) in members.enumerated() {
                if !compact { out += inner }
                out += JSONNode.escape(member.key)
                out += compact ? ":" : ": "
                member.value.append(to: &out, level: level + 1, indent: indent, compact: compact)
                if index < members.count - 1 { out += "," }
                if !compact { out += "\n" }
            }
            if !compact { out += outer }
            out += "}"
        case .array(let items):
            if items.isEmpty {
                out += "[]"
                return
            }
            let inner = String(repeating: " ", count: (level + 1) * indent)
            let outer = String(repeating: " ", count: level * indent)
            out += "["
            if !compact { out += "\n" }
            for (index, item) in items.enumerated() {
                if !compact { out += inner }
                item.append(to: &out, level: level + 1, indent: indent, compact: compact)
                if index < items.count - 1 { out += "," }
                if !compact { out += "\n" }
            }
            if !compact { out += outer }
            out += "]"
        }
    }

    static func escape(_ string: String) -> String {
        var out = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
        return out
    }
}

struct JSONParseFailure: LocalizedError {
    let message: String
    let line: Int
    let column: Int

    var errorDescription: String? {
        "第 \(line) 行 第 \(column) 列：\(message)"
    }
}

struct JSONParser {
    private let chars: [Character]
    private var index = 0
    private var line = 1
    private var column = 1

    private init(_ source: String) {
        chars = Array(source)
    }

    static func parse(_ source: String) throws -> JSONNode {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw JSONParseFailure(message: "内容为空", line: 1, column: 1)
        }
        var parser = JSONParser(source)
        return try parser.parseDocument()
    }

    // MARK: - Core

    private mutating func parseDocument() throws -> JSONNode {
        skipWhitespace()
        let value = try parseValue()
        skipWhitespace()
        if let extra = peek() {
            throw failure("JSON 结束后出现多余字符 '\(extra)'")
        }
        return value
    }

    private mutating func parseValue() throws -> JSONNode {
        skipWhitespace()
        guard let char = peek() else {
            throw failure("JSON 意外结束")
        }
        switch char {
        case "{": return try parseObject()
        case "[": return try parseArray()
        case "\"": return .string(try parseString())
        case "t", "f": return .bool(try parseBool())
        case "n": return try parseNull()
        case "-", "0"..."9": return .number(try parseNumber())
        default:
            throw failure("意外的字符 '\(char)'")
        }
    }

    private mutating func parseObject() throws -> JSONNode {
        advance() // {
        var members: [JSONMember] = []
        skipWhitespace()
        if peek() == "}" {
            advance()
            return .object(members)
        }
        while true {
            skipWhitespace()
            guard peek() == "\"" else {
                throw failure("对象的键必须是字符串")
            }
            let key = try parseString()
            skipWhitespace()
            guard peek() == ":" else {
                throw failure("键 \"\(key)\" 后缺少 ':'")
            }
            advance()
            let value = try parseValue()
            members.append(JSONMember(key: key, value: value))
            skipWhitespace()
            switch peek() {
            case ",":
                advance()
                continue
            case "}":
                advance()
                return .object(members)
            default:
                throw failure("对象未闭合，缺少 ',' 或 '}'")
            }
        }
    }

    private mutating func parseArray() throws -> JSONNode {
        advance() // [
        var items: [JSONNode] = []
        skipWhitespace()
        if peek() == "]" {
            advance()
            return .array(items)
        }
        while true {
            let value = try parseValue()
            items.append(value)
            skipWhitespace()
            switch peek() {
            case ",":
                advance()
                continue
            case "]":
                advance()
                return .array(items)
            default:
                throw failure("数组未闭合，缺少 ',' 或 ']'")
            }
        }
    }

    private mutating func parseString() throws -> String {
        advance() // opening quote
        var result = ""
        while true {
            guard let char = peek() else {
                throw failure("字符串未闭合")
            }
            advance()
            if char == "\"" {
                return result
            }
            if char == "\\" {
                guard let escaped = peek() else {
                    throw failure("转义字符不完整")
                }
                advance()
                switch escaped {
                case "\"": result += "\""
                case "\\": result += "\\"
                case "/": result += "/"
                case "b": result += "\u{08}"
                case "f": result += "\u{0C}"
                case "n": result += "\n"
                case "r": result += "\r"
                case "t": result += "\t"
                case "u":
                    let scalar = try parseUnicodeEscape()
                    if (0xD800...0xDBFF).contains(scalar),
                       peek() == "\\" {
                        let save = (index, line, column)
                        advance()
                        if peek() == "u" {
                            advance()
                            let low = try parseUnicodeEscape()
                            if (0xDC00...0xDFFF).contains(low) {
                                let combined = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00)
                                if let us = Unicode.Scalar(combined) {
                                    result.unicodeScalars.append(us)
                                    continue
                                }
                            }
                        }
                        (index, line, column) = save
                    }
                    if let us = Unicode.Scalar(scalar) {
                        result.unicodeScalars.append(us)
                    }
                default:
                    throw failure("无效的转义字符 '\\\(escaped)'")
                }
                continue
            }
            if char == "\n" {
                throw failure("字符串中包含未转义的换行")
            }
            result.append(char)
        }
    }

    private mutating func parseUnicodeEscape() throws -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<4 {
            guard let char = peek(), let digit = char.hexDigitValue else {
                throw failure("\\u 转义需要 4 位十六进制数字")
            }
            advance()
            value = value * 16 + UInt32(digit)
        }
        return value
    }

    private mutating func parseBool() throws -> Bool {
        if peek() == "t" {
            for expected in "true" {
                guard peek() == expected else { throw failure("无效的字面量，应为 true") }
                advance()
            }
            return true
        }
        for expected in "false" {
            guard peek() == expected else { throw failure("无效的字面量，应为 false") }
            advance()
        }
        return false
    }

    private mutating func parseNull() throws -> JSONNode {
        for expected in "null" {
            guard peek() == expected else { throw failure("无效的字面量，应为 null") }
            advance()
        }
        return .null
    }

    private mutating func parseNumber() throws -> String {
        var raw = ""
        while let char = peek(), "-+.eE0123456789".contains(char) {
            raw.append(char)
            advance()
        }
        guard let first = raw.first, first == "-" || first.isNumber else {
            throw failure("无效的数字 '\(raw)'")
        }
        guard raw.filter({ $0.isNumber }).isEmpty == false else {
            throw failure("无效的数字 '\(raw)'")
        }
        guard Double(raw) != nil else {
            throw failure("无效的数字 '\(raw)'")
        }
        return raw
    }

    // MARK: - Cursor

    private func peek() -> Character? {
        index < chars.count ? chars[index] : nil
    }

    private mutating func advance() {
        guard index < chars.count else { return }
        if chars[index] == "\n" {
            line += 1
            column = 1
        } else {
            column += 1
        }
        index += 1
    }

    private mutating func skipWhitespace() {
        while let char = peek(), char == " " || char == "\n" || char == "\t" || char == "\r" {
            advance()
        }
    }

    private func failure(_ message: String) -> JSONParseFailure {
        JSONParseFailure(message: message, line: line, column: column)
    }
}
