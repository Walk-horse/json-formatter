import SwiftUI

struct JSONRow: Identifiable {
    let id: String
    let depth: Int
    let key: String?
    let node: JSONNode
    let hasChildren: Bool
}

struct JSONTreeView: View {
    let node: JSONNode
    let query: String
    let caseSensitive: Bool
    let theme: AppTheme

    @State private var collapsed: Set<String> = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    JSONTreeRow(
                        row: row,
                        isCollapsed: collapsed.contains(row.id),
                        query: query,
                        caseSensitive: caseSensitive,
                        theme: theme,
                        onToggle: { toggle(row.id) }
                    )
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: theme.editorBackground))
    }

    private func toggle(_ id: String) {
        if collapsed.contains(id) {
            collapsed.remove(id)
        } else {
            collapsed.insert(id)
        }
    }

    private var rows: [JSONRow] {
        var result: [JSONRow] = []
        flatten(node, key: nil, path: "root", depth: 0, into: &result)
        return result
    }

    private func flatten(_ node: JSONNode, key: String?, path: String, depth: Int, into result: inout [JSONRow]) {
        let hasChildren = node.isContainer && node.childCount > 0
        result.append(JSONRow(id: path, depth: depth, key: key, node: node, hasChildren: hasChildren))
        guard hasChildren, !collapsed.contains(path) else { return }
        switch node {
        case .object(let members):
            for (index, member) in members.enumerated() {
                flatten(member.value,
                        key: member.key,
                        path: "\(path)/\(member.key)#\(index)",
                        depth: depth + 1,
                        into: &result)
            }
        case .array(let items):
            for (index, item) in items.enumerated() {
                flatten(item, key: "[\(index)]", path: "\(path)/[\(index)]", depth: depth + 1, into: &result)
            }
        default:
            break
        }
    }
}

struct JSONTreeRow: View {
    let row: JSONRow
    let isCollapsed: Bool
    let query: String
    let caseSensitive: Bool
    let theme: AppTheme
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            if row.hasChildren {
                Button(action: onToggle) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color(nsColor: theme.secondaryTextColor))
                        .frame(width: 12, height: 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 12, height: 12)
            }

            if let key = row.key {
                highlighted(key, color: Color(nsColor: theme.syntaxKey), weight: .medium)
                Text(":")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color(nsColor: theme.syntaxPunctuation))
            }

            valueView

            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(row.depth) * 16 + 14)
        .frame(height: 21)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var valueView: some View {
        switch row.node {
        case .object:
            Text(row.node.childCount == 0 ? "{}" : "{ \(row.node.childCount) }")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color(nsColor: theme.syntaxPunctuation))
        case .array:
            Text(row.node.childCount == 0 ? "[]" : "[ \(row.node.childCount) ]")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color(nsColor: theme.syntaxPunctuation))
        case .string(let value):
            highlighted("\"\(value)\"", color: Color(nsColor: theme.syntaxString))
        case .number(let raw):
            highlighted(raw, color: Color(nsColor: theme.syntaxNumber))
        case .bool(let flag):
            Text(flag ? "true" : "false")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color(nsColor: theme.syntaxKeyword))
        case .null:
            Text("null")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color(nsColor: theme.syntaxKeyword))
        }
    }

    /// 命中词高亮：用 AttributedString 保持颜色分段正确。
    private func highlighted(_ string: String, color: Color, weight: Font.Weight = .regular) -> Text {
        var attributed = AttributedString(string)
        attributed.font = Font.system(size: 12, weight: weight, design: .monospaced)
        attributed.foregroundColor = color
        guard !query.isEmpty else { return Text(attributed) }

        let options: String.CompareOptions = caseSensitive ? [.literal] : [.caseInsensitive, .literal]
        var cursor = string.startIndex
        while cursor < string.endIndex,
              let match = string.range(of: query, options: options, range: cursor..<string.endIndex) {
            if let lower = AttributedString.Index(match.lowerBound, within: attributed),
               let upper = AttributedString.Index(match.upperBound, within: attributed) {
                attributed[lower..<upper].backgroundColor = Color(nsColor: theme.matchBackground)
                attributed[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
            }
            cursor = match.upperBound
        }
        return Text(attributed)
    }
}
