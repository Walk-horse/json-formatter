import AppKit
import Foundation

/// 调试用：JF_SELFTEST=1 时跑一遍解析/序列化/查找的核心断言，然后退出。
@MainActor
enum SelfTest {
    static func runIfRequested() {
        guard ProcessInfo.processInfo.environment["JF_SELFTEST"] != nil else { return }
        var failures = 0

        func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
            if condition {
                print("PASS  \(name)")
            } else {
                failures += 1
                print("FAIL  \(name) \(detail())")
            }
        }

        // 1. 基础美化
        if let node = try? JSONParser.parse(#"{"a":1}"#) {
            check("pretty basic", node.serialized() == "{\n  \"a\": 1\n}", node.serialized())
        } else {
            check("pretty basic parse", false)
        }

        // 2. 压缩
        if let node = try? JSONParser.parse("  { \"a\" : [1, 2] , \"b\": { } } ") {
            check("minify", node.serialized(compact: true) == #"{"a":[1,2],"b":{}}"#, node.serialized(compact: true))
        } else {
            check("minify parse", false)
        }

        // 3. 键顺序保留
        if let node = try? JSONParser.parse(#"{"b":1,"a":2,"c":3}"#),
           case .object(let members) = node {
            check("order preserved", members.map(\.key) == ["b", "a", "c"], "\(members.map(\.key))")
        } else {
            check("order preserved parse", false)
        }

        // 4. 数字原样保留
        if let node = try? JSONParser.parse(#"[35.0, 1e10, -0.5, 15688896212]"#),
           case .array(let items) = node {
            let raw = items.map { item -> String in
                if case .number(let text) = item { return text }
                return "?"
            }
            check("numbers raw", raw == ["35.0", "1e10", "-0.5", "15688896212"], "\(raw)")
        } else {
            check("numbers parse", false)
        }

        // 5. 转义与中文
        if let node = try? JSONParser.parse(#"{"s":"a\u00e9\n\t\"q\"","cn":"电视"}"#),
           case .object(let members) = node,
           case .string(let str) = members[0].value,
           case .string(let cn) = members[1].value {
            check("escape decode", str == "aé\n\t\"q\"", str.debugDescription)
            check("unicode key value", cn == "电视")
        } else {
            check("escape parse", false)
        }

        // 6. 错误定位
        do {
            _ = try JSONParser.parse("{\n  \"a\": ,\n}")
            check("error thrown", false)
        } catch let error as JSONParseFailure {
            check("error line", error.line == 2, "line=\(error.line)")
            check("error column", error.column == 8, "col=\(error.column)")
            print("      ↳ \(error.errorDescription ?? "")")
        } catch {
            check("error type", false)
        }

        // 7. 空容器
        check("empty object", (try? JSONParser.parse("{}"))?.serialized() == "{}")
        check("empty array compact", (try? JSONParser.parse("[ ]"))?.serialized(compact: true) == "[]")

        // 8. 样例 roundtrip 稳定
        if let first = try? JSONParser.parse(AppModel.sampleJSON) {
            let once = first.serialized()
            let twice = (try? JSONParser.parse(once))?.serialized()
            check("roundtrip stable", once == twice)
            check("nested array survived", once.contains("\"evaluationDetail\": ["))
        } else {
            check("sample parse", false)
        }

        // 9. 查找计数
        let find = FindState()
        find.query = "userPhone"
        find.refresh(with: AppModel.sampleJSON)
        check("find count", find.matches.count == 2, "\(find.matches.count)")

        find.useRegex = true
        find.query = "user(Id|Name)"
        find.refresh(with: AppModel.sampleJSON)
        check("regex count", find.matches.count == 2, "\(find.matches.count)")
        check("regex replacement template", find.replacement == "")

        find.replacement = "$1_edit"
        if let range = find.matches.first {
            check("regex template expand",
                  find.replacementText(for: range) == "Id_edit",
                  find.replacementText(for: range))
        }

        find.useRegex = false
        find.query = "userPhone"
        find.refresh(with: AppModel.sampleJSON)
        check("literal count off-regex", find.matches.count == 2, "\(find.matches.count)")

        // 10. 一键修复异常 JSON
        func repairOK(_ name: String, _ broken: String, _ expectContains: String? = nil) {
            let outcome = JSONRepair.repair(broken)
            guard let node = try? JSONParser.parse(outcome.text) else {
                check("repair \(name)", false, "unparsable: \(outcome.text)")
                return
            }
            let pretty = node.serialized()
            if let needle = expectContains, !pretty.contains(needle) {
                check("repair \(name)", false, "缺少 \(needle)，实际 \(pretty)")
            } else {
                check("repair \(name)", true)
            }
        }

        repairOK("尾随逗号", "{a:1,}", "\"a\": 1")
        repairOK("单引号", "{'a':'b'}", "\"a\": \"b\"")
        repairOK("未加引号键", "{name: \"x\", age: 3}", "\"name\": \"x\"")
        repairOK("注释", "{\n // hi\n \"a\": 1 /* tail */\n}", "\"a\": 1")
        repairOK("缺失逗号", "{\n \"a\": 1\n \"b\": 2\n}", "\"b\": 2")
        repairOK("Python 字面量", "{'a': True, 'b': None}", "\"a\": true")
        repairOK("裸词值", "{a: hello}", "\"a\": \"hello\"")
        repairOK("NaN/Infinity", "{a: NaN, b: -Infinity}", "\"a\": null")
        repairOK("字符串内换行", "{\"a\": \"x\ny\"}", "x\\ny")
        repairOK("中文键", "{类型: \"液晶\"}", "\"类型\"")

        // 11. 用户报告的破损场景
        repairOK("删除冒号", #"{"a" 1, "b" 2}"#, #""a": 1"#)
        repairOK("删除冒号(裸词)", "{a 1, b 2}", "\"a\": 1")
        repairOK("中文冒号", #"{"a"：1}"#, #""a": 1"#)
        repairOK("中文冒号(裸词)", "{a：1}", "\"a\": 1")
        repairOK("中文引号", #"{"a"："b"}"#, #""a": "b""#)
        repairOK("中文引号包裹", #"{"a"："液晶"}"#, #""液晶""#)
        repairOK("转义引号", #"{"a": \"x\"}"#, #""x""#)
        repairOK("转义引号(整体)", #"{\"a\": 1}"#, #""a": 1"#)
        repairOK("复合破坏", #"{"a" 1, "b"："c"}"#, #""a": 1"#)

        let valid = #"{"a": 1, "b": [1, 2]}"#
        check("repair 不破坏合法 JSON",
              (try? JSONParser.parse(JSONRepair.repair(valid).text))?.serialized(compact: true)
                == #"{"a":1,"b":[1,2]}"#)

        print(failures == 0 ? "ALL PASS" : "\(failures) FAILURE(S)")
        exit(failures == 0 ? 0 : 1)
    }
}
