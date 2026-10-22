import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

enum ViewMode: String, CaseIterable, Identifiable {
    case text = "文本视图"
    case tree = "树状视图"

    var id: String { rawValue }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var text: String = AppModel.sampleJSON
    @Published var mode: ViewMode = .text
    @Published var fontSize: Double = 13
    @Published var indent: Int = 2
    @Published var errorMessage: String?
    @Published var currentFileName: String?
    /// 修复成功等正向提示（与 errorMessage 互斥展示）。
    @Published var noticeMessage: String?

    @Published var theme: AppTheme = AppTheme.stored() {
        didSet {
            AppTheme.applyAppearance(theme)
            AppTheme.persist(theme)
        }
    }

    /// 是否显示行号栏，选择写入 UserDefaults。
    @Published var showLineNumbers: Bool {
        didSet { UserDefaults.standard.set(showLineNumbers, forKey: AppModel.lineNumbersKey) }
    }

    private static let lineNumbersKey = "JSONFormatter.showLineNumbers"

    init() {
        showLineNumbers = UserDefaults.standard.object(forKey: AppModel.lineNumbersKey) as? Bool ?? true
        AppTheme.applyAppearance(theme)
        format(silentOnEmpty: true)
    }

    func toggleTheme() {
        theme = theme.next
    }

    // MARK: - 格式化

    func format(silentOnEmpty: Bool = false) {
        noticeMessage = nil
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if !silentOnEmpty { errorMessage = "内容为空，先导入或粘贴 JSON" }
            return
        }
        do {
            let node = try JSONParser.parse(text)
            let pretty = node.serialized(indent: indent)
            if pretty != text { text = pretty }
            errorMessage = nil
        } catch {
            errorMessage = (error as? JSONParseFailure)?.errorDescription ?? error.localizedDescription
        }
    }

    func minify() {
        noticeMessage = nil
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            let node = try JSONParser.parse(text)
            text = node.serialized(compact: true)
            errorMessage = nil
        } catch {
            errorMessage = (error as? JSONParseFailure)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 一键修复：解析失败时修补常见非标准写法，成功后再美化。
    /// 通过 NSTextView 撤销栈写入，⌘Z 可回退。
    func repair(editor: EditorController? = nil) {
        noticeMessage = nil
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "内容为空，先导入或粘贴 JSON"
            return
        }
        if (try? JSONParser.parse(text)) != nil {
            format()
            noticeMessage = "内容已是合法 JSON，已重新格式化"
            return
        }
        let outcome = JSONRepair.repair(text)
        do {
            let node = try JSONParser.parse(outcome.text)
            applyWholeText(node.serialized(indent: indent), editor: editor)
            errorMessage = nil
            noticeMessage = outcome.fixes.isEmpty
                ? "已修复并格式化"
                : "已修复：" + outcome.fixes.joined(separator: "、")
        } catch {
            errorMessage = "无法自动修复：" + ((error as? JSONParseFailure)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func applyWholeText(_ newText: String, editor: EditorController?) {
        guard let editor, editor.hasEditor else {
            text = newText
            return
        }
        let full = NSRange(location: 0, length: (text as NSString).length)
        if !editor.replace(range: full, with: newText) {
            text = newText
        }
    }

    func parseTree() -> JSONNode? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return try? JSONParser.parse(text)
    }

    // MARK: - 文件

    func importFile() {
        let panel = NSOpenPanel()
        panel.title = "导入 JSON 文件"
        panel.allowedContentTypes = [.json, .plainText, .text]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url: url)
    }

    func load(url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            text = content
            currentFileName = url.lastPathComponent
            format()
        } catch {
            errorMessage = "读取失败：\(error.localizedDescription)"
        }
    }

    func load(text newText: String) {
        text = newText
        currentFileName = nil
        format()
    }

    func exportFile() {
        let panel = NSSavePanel()
        panel.title = "导出 JSON"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = exportFileName()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            currentFileName = url.lastPathComponent
            errorMessage = nil
        } catch {
            errorMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    func copyToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func exportFileName() -> String {
        guard let name = currentFileName else { return "formatted.json" }
        let base = (name as NSString).deletingPathExtension
        return base.isEmpty ? "formatted.json" : "\(base).json"
    }

    // MARK: - 查找替换

    func replaceCurrent(find: FindState, editor: EditorController) {
        guard let range = find.currentRange else { return }
        let index = find.current
        let newText = find.replacementText(for: range)
        let replaced = editor.replace(range: range, with: newText)
        if !replaced {
            let buffer = NSMutableString(string: text)
            guard NSMaxRange(range) <= buffer.length else { return }
            buffer.replaceCharacters(in: range, with: newText)
            text = buffer as String
        }
        find.refresh(with: text)
        find.current = min(index, max(0, find.matches.count - 1))
        if !find.matches.isEmpty {
            editor.scroll(to: find.matches[find.current])
        }
        validateAfterEdit()
    }

    func replaceAll(find: FindState, editor: EditorController) {
        guard !find.matches.isEmpty else { return }
        if let replaced = find.replacingAll(in: text), find.useRegex {
            replaceWholeText(with: replaced, editor: editor)
        } else {
            for range in find.matches.reversed() where NSMaxRange(range) <= (text as NSString).length {
                _ = editor.replace(range: range, with: find.replacement)
            }
        }
        find.refresh(with: text)
        find.current = 0
        validateAfterEdit()
    }

    private func replaceWholeText(with newText: String, editor: EditorController) {
        let full = NSRange(location: 0, length: (text as NSString).length)
        if !editor.replace(range: full, with: newText) {
            text = newText
        }
    }

    /// 替换后如果是合法 JSON，顺手规范化缩进；不合法则保留原文并提示。
    private func validateAfterEdit() {
        guard let node = try? JSONParser.parse(text) else {
            errorMessage = "替换后已不是合法 JSON（文本保留原样）"
            return
        }
        errorMessage = nil
        _ = node
    }
}

extension AppModel {
    static let sampleJSON = """
    {
      "realTradeInAmt": 0,
      "residualValue": 35.0,
      "tradeInAmt": 0,
      "tradeInId": "394475761902583808",
      "tradeInValuationDetail": {
        "defaultAttr": {
          "类型": ""
        },
        "evaluationDetail": [
          {
            "规格": "19寸及以上",
            "类型": "液晶",
            "品牌": "海尔"
          }
        ],
        "evaluationPrice": "35.00",
        "hxid": "394475761902583808",
        "industryCode": "_DS_",
        "industryName": "电视",
        "sourceSystem": "162",
        "userId": "2021947158",
        "userName": "156****6212",
        "userPhone": "15688896212"
      },
      "userPhone": "15688896212"
    }
    """
}
