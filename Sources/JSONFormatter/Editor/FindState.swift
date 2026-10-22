import AppKit
import Combine
import Foundation

/// 查找/替换状态，同时负责匹配计算。
@MainActor
final class FindState: ObservableObject {
    @Published var isVisible = true
    @Published var query = "" { didSet { if query != oldValue { current = 0; refreshNow() } } }
    @Published var replacement = ""
    @Published var caseSensitive = false { didSet { if caseSensitive != oldValue { current = 0; refreshNow() } } }
    @Published var useRegex = false { didSet { if useRegex != oldValue { current = 0; refreshNow() } } }
    @Published var current = 0
    @Published private(set) var matches: [NSRange] = []
    @Published var focusRequest = 0

    private var source = ""
    private var compiled: NSRegularExpression?

    var countText: String {
        if query.isEmpty { return "" }
        if matches.isEmpty { return "0 项" }
        return "\(current + 1)/\(matches.count)"
    }

    var currentRange: NSRange? {
        guard matches.indices.contains(current) else { return nil }
        return matches[current]
    }

    func refresh(with text: String) {
        source = text
        compiled = nil
        var result: [NSRange] = []
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        if !query.isEmpty, full.length > 0 {
            if useRegex {
                var options: NSRegularExpression.Options = []
                if !caseSensitive { options.insert(.caseInsensitive) }
                if let regex = try? NSRegularExpression(pattern: query, options: options) {
                    compiled = regex
                    result = regex.matches(in: text, options: [], range: full).map(\.range)
                }
            } else {
                var options: NSString.CompareOptions = []
                if !caseSensitive { options.insert(.caseInsensitive) }
                var searchRange = full
                while searchRange.length > 0 || searchRange.location == 0 {
                    let found = ns.range(of: query, options: options, range: searchRange)
                    if found.location == NSNotFound { break }
                    result.append(found)
                    let next = NSMaxRange(found)
                    if next >= ns.length { break }
                    searchRange = NSRange(location: next, length: ns.length - next)
                }
            }
        }

        matches = result
        if current >= matches.count {
            current = max(0, matches.count - 1)
        }
        objectWillChange.send()
    }

    private func refreshNow() {
        refresh(with: source)
    }

    /// 文本被外部修改后同步（不改变当前命中序号逻辑由调用方控制）。
    func syncAfterEdit(text: String, keepIndex: Bool) {
        let index = current
        refresh(with: text)
        if keepIndex {
            current = min(index, max(0, matches.count - 1))
        }
    }

    func next() {
        guard !matches.isEmpty else { return }
        current = (current + 1) % matches.count
    }

    func previous() {
        guard !matches.isEmpty else { return }
        current = (current - 1 + matches.count) % matches.count
    }

    func replacementText(for range: NSRange) -> String {
        if useRegex, let regex = compiled,
           let match = regex.firstMatch(in: source, options: [], range: range) {
            return regex.replacementString(for: match, in: source, offset: 0, template: replacement)
        }
        return replacement
    }

    func replacingAll(in text: String) -> String? {
        guard useRegex, let regex = compiled else { return nil }
        let full = NSRange(location: 0, length: (text as NSString).length)
        return regex.stringByReplacingMatches(in: text, options: [], range: full, withTemplate: replacement)
    }
}
