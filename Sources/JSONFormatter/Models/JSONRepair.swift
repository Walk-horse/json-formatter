import Foundation

/// 一键修复：把常见「非标准 JSON」改写成可被解析器接受的文本。
///
/// 覆盖范围：
/// - BOM 头、`//` 与 `/* */` 注释
/// - 单引号字符串 → 双引号；中文引号 `“”` / `‘’` 包裹的键与字符串 → 双引号
/// - 未加引号的键（含中文键）与未加引号的值
/// - 尾随逗号、成员之间缺失的逗号
/// - **键与值之间缺失的 `:`**（删除冒号）、**中文冒号 `：` 当作分隔符**
/// - **转义引号 `\"`**（整段被反斜杠转义的引号）还原为正常引号
/// - Python 字面量 `True / False / None`、`undefined / NaN / Infinity`
/// - 字符串内的裸换行 / 制表符
///
/// 实现采用「上下文感知」单遍扫描：维护一个容器栈，
/// 区分当前是在对象里「期待键」还是「期待值」，从而能正确地：
///   1. 把裸词 / 引号串判定为键还是值；
///   2. 在「键之后缺少冒号」时自动补 `:`；
///   3. 在「值之后缺少逗号」时自动补 `,`。
enum JSONRepair {
    struct Outcome {
        let text: String
        let fixes: [String]
    }

    /// 容器栈帧：isObject 表示当前容器是对象（需要 key:value）；
    /// expectKey 表示在当前对象内正等待一个新的键。
    private struct Frame {
        var isObject: Bool
        var expectKey: Bool
    }

    // 中文标点
    private static let chineseColon: Character = "："
    private static let ldq: Character = "\u{201C}" // “
    private static let rdq: Character = "\u{201D}" // ”
    private static let lsq: Character = "\u{2018}" // ‘
    private static let rsq: Character = "\u{2019}" // ’

    static func repair(_ input: String) -> Outcome {
        let chars = Array(input)
        let n = chars.count
        var out = ""
        out.reserveCapacity(n)
        var fixes: [String] = []
        var i = 0

        /// 容器栈：栈底为顶层（视作数组，只放值）。
        var stack: [Frame] = [Frame(isObject: false, expectKey: false)]
        /// 上一个 token 是完整值，接下来应当是 `,` 或闭合符。
        var valueDone = false
        /// 上一个 token 是键，接下来应当是 `:`（若缺失则修复时补上）。
        var pendingColon = false

        func note(_ label: String) {
            if !fixes.contains(label) { fixes.append(label) }
        }
        func isWordStart(_ c: Character) -> Bool {
            if c == "_" || c == "$" { return true }
            guard let scalar = c.unicodeScalars.first else { return false }
            return CharacterSet.letters.contains(scalar)
        }
        func isWordChar(_ c: Character) -> Bool {
            isWordStart(c) || c.isNumber
        }
        func nextNonSpace(from index: Int) -> Int {
            var k = index
            while k < n, chars[k].isWhitespace { k += 1 }
            return k
        }

        /// 在输出一个值之前补充分隔符：缺冒号补 `:`，否则缺逗号补 `,`。
        func emitValueSeparator() {
            if pendingColon {
                out.append(":")
                note("缺失的冒号")
                pendingColon = false
            } else if valueDone {
                out.append(",")
                note("缺失的逗号")
            }
        }

        /// 把字符串正文重新包成合法的双引号字符串（统一转义）。
        func escapeBody(_ body: String) -> String {
            var s = "\""
            for scalar in body.unicodeScalars {
                switch scalar {
                case "\"": s += "\\\""
                case "\\": s += "\\\\"
                case "\n": s += "\\n"
                case "\r": s += "\\r"
                case "\t": s += "\\t"
                case "\u{08}": s += "\\b"
                case "\u{0C}": s += "\\f"
                default:
                    if scalar.value < 0x20 {
                        s += String(format: "\\u%04x", scalar.value)
                    } else {
                        s.unicodeScalars.append(scalar)
                    }
                }
            }
            s += "\""
            return s
        }

        /// 输出一个字符串 token（键或值由上下文决定）。
        func emitString(_ body: String) {
            let idx = stack.count - 1
            if stack[idx].isObject && stack[idx].expectKey {
                // 作为键
                if valueDone { out.append(","); note("缺失的逗号") }
                out.append(escapeBody(body))
                pendingColon = true
                stack[idx].expectKey = false
                valueDone = false
            } else {
                // 作为值
                emitValueSeparator()
                out.append(escapeBody(body))
                valueDone = true
                pendingColon = false
            }
        }

        /// 读取被（中文/英文）引号包裹的字符串，正文解码后交给 emitString。
        func readString(open: Character, close: Character, noteLabel: String? = nil) {
            if let label = noteLabel { note(label) }
            i += 1
            var body = ""
            while i < n {
                let ch = chars[i]
                if ch == "\\" {
                    if i + 1 < n {
                        let nx = chars[i + 1]
                        if nx == "\\" { body.append("\\"); i += 2; continue }
                        if nx == "\"" { body.append("\""); i += 2; continue }
                        if nx == "'" { body.append("'"); i += 2; continue }
                        if nx == "n" { body.append("\n"); i += 2; continue }
                        if nx == "t" { body.append("\t"); i += 2; continue }
                        if nx == "r" { body.append("\r"); i += 2; continue }
                        // 其它转义按原样保留反斜杠
                        body.append("\\"); i += 1; continue
                    }
                    body.append("\\"); i += 1; continue
                }
                if ch == close { i += 1; emitString(body); return }
                body.append(ch); i += 1
            }
            // 未闭合：尽力输出
            emitString(body)
        }

        /// 读取被转义引号 `\"` 包裹的字符串（常见于整体被转义的 JSON）。
        func readEscapedString() {
            note("转义引号")
            i += 2 // 跳过 \"
            var body = ""
            while i < n {
                let ch = chars[i]
                if ch == "\\" && i + 1 < n && chars[i + 1] == "\\" {
                    body.append("\\"); i += 2; continue
                }
                if ch == "\\" && i + 1 < n && chars[i + 1] == "\"" {
                    i += 2; emitString(body); return
                }
                body.append(ch); i += 1
            }
            emitString(body)
        }

        if i < n, chars[i] == "\u{FEFF}" {
            i += 1
            note("BOM 头")
        }

        while i < n {
            let c = chars[i]

            if c.isWhitespace { out.append(c); i += 1; continue }

            // 转义引号：\" 在结构位置上当作正常引号的开头
            if c == "\\", i + 1 < n, chars[i + 1] == "\"" {
                readEscapedString()
                continue
            }

            // 中文引号包裹的键 / 字符串
            if c == ldq { readString(open: ldq, close: rdq, noteLabel: "中文引号"); continue }
            if c == rdq { readString(open: rdq, close: ldq, noteLabel: "中文引号"); continue }
            if c == lsq { readString(open: lsq, close: rsq, noteLabel: "中文引号"); continue }
            if c == rsq { readString(open: rsq, close: lsq, noteLabel: "中文引号"); continue }

            // 注释
            if c == "/", i + 1 < n {
                let next = chars[i + 1]
                if next == "/" {
                    note("注释")
                    i += 2
                    while i < n, chars[i] != "\n" { i += 1 }
                    continue
                }
                if next == "*" {
                    note("注释")
                    i += 2
                    while i + 1 < n, !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                    i = min(i + 2, n)
                    continue
                }
            }

            // 双引号字符串
            if c == "\"" {
                readString(open: "\"", close: "\"")
                continue
            }

            // 单引号字符串 → 双引号
            if c == "'" {
                readString(open: "'", close: "'", noteLabel: "单引号")
                continue
            }

            // 中文冒号当作分隔符
            if c == chineseColon {
                if pendingColon {
                    out.append(":")
                    note("中文冒号")
                    pendingColon = false
                } else {
                    out.append(":")
                    note("中文冒号")
                }
                valueDone = false
                i += 1
                continue
            }

            if c == "{" {
                emitValueSeparator()
                out.append("{")
                stack.append(Frame(isObject: true, expectKey: true))
                valueDone = false
                pendingColon = false
                i += 1
                continue
            }

            if c == "[" {
                emitValueSeparator()
                out.append("[")
                stack.append(Frame(isObject: false, expectKey: false))
                valueDone = false
                pendingColon = false
                i += 1
                continue
            }

            if c == "}" || c == "]" {
                if stack.count > 1 { stack.removeLast() }
                out.append(c)
                valueDone = true
                pendingColon = false
                i += 1
                continue
            }

            if c == "," {
                let lookahead = nextNonSpace(from: i + 1)
                if lookahead < n, chars[lookahead] == "}" || chars[lookahead] == "]" {
                    note("尾随逗号")
                    i = lookahead
                    continue
                }
                if stack.last?.isObject == true {
                    stack[stack.count - 1].expectKey = true
                }
                out.append(",")
                valueDone = false
                pendingColon = false
                i += 1
                continue
            }

            if c == ":" {
                if pendingColon {
                    out.append(":")
                    pendingColon = false
                } else {
                    out.append(":")
                }
                valueDone = false
                i += 1
                continue
            }

            // -Infinity 优先于数字分支
            if c == "-", i + 1 < n, isWordStart(chars[i + 1]) {
                var t = i + 1
                while t < n, isWordChar(chars[t]) { t += 1 }
                if String(chars[(i + 1)..<t]) == "Infinity" {
                    emitValueSeparator()
                    out.append("null")
                    note("非法字面量")
                    i = t
                    valueDone = true
                    pendingColon = false
                    continue
                }
            }

            // 数字（顺带去掉前导 +）
            if c == "-" || c == "+" || c.isNumber {
                emitValueSeparator()
                var j = i
                if chars[j] == "-" {
                    out.append("-")
                    j += 1
                } else if chars[j] == "+" {
                    note("前导 +")
                    j += 1
                }
                while j < n, chars[j].isNumber {
                    out.append(chars[j])
                    j += 1
                }
                if j < n, chars[j] == "." {
                    out.append(".")
                    j += 1
                    while j < n, chars[j].isNumber {
                        out.append(chars[j])
                        j += 1
                    }
                }
                if j < n, chars[j] == "e" || chars[j] == "E" {
                    out.append(chars[j])
                    j += 1
                    if j < n, chars[j] == "+" || chars[j] == "-" {
                        out.append(chars[j])
                        j += 1
                    }
                    while j < n, chars[j].isNumber {
                        out.append(chars[j])
                        j += 1
                    }
                }
                i = j
                valueDone = true
                pendingColon = false
                continue
            }

            // 裸词
            if isWordStart(c) {
                var j = i
                while j < n, isWordChar(chars[j]) { j += 1 }
                let word = String(chars[i..<j])
                i = j

                let idx = stack.count - 1
                if stack[idx].isObject && stack[idx].expectKey {
                    // 未加引号的键
                    if valueDone { out.append(","); note("缺失的逗号") }
                    out.append(escapeBody(word))
                    note("未加引号的键")
                    pendingColon = true
                    stack[idx].expectKey = false
                    valueDone = false
                    continue
                }

                emitValueSeparator()
                switch word {
                case "true", "false", "null":
                    out.append(word)
                case "True", "False", "None":
                    out.append(word == "True" ? "true" : (word == "False" ? "false" : "null"))
                    note("Python 字面量")
                case "undefined", "NaN", "Infinity":
                    out.append("null")
                    note("非法字面量")
                default:
                    out.append(escapeBody(word))
                    note("未加引号的值")
                }
                valueDone = true
                pendingColon = false
                continue
            }

            out.append(c)
            i += 1
        }

        // 顶层若仍有未闭合的容器，补上闭合符，提高可解析概率。
        while stack.count > 1 {
            let frame = stack.removeLast()
            out.append(frame.isObject ? "}" : "]")
            note("缺失的闭合符")
        }

        return Outcome(text: out, fixes: fixes)
    }
}
