import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var find: FindState
    @StateObject private var editor = EditorController()

    @State private var tree: JSONNode?
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            separator

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if isDropTargeted {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color(nsColor: model.theme.accentColor), lineWidth: 2)
                            .background(Color(nsColor: model.theme.accentColor).opacity(0.06))
                            .allowsHitTesting(false)
                    }
                }

            if let notice = model.noticeMessage {
                separator
                noticeBar(notice)
            } else if let message = model.errorMessage {
                separator
                errorBar(message)
            }

            // 查找替换栏常驻底部
            if find.isVisible {
                separator
                FindBar(model: model, find: find, editor: editor, theme: model.theme)
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .background(Color(nsColor: model.theme.editorBackground))
        .onDrop(of: [.fileURL, .plainText, .utf8PlainText], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
            return true
        }
        .onChange(of: model.text) { newValue in
            find.refresh(with: newValue)
            if model.mode == .tree {
                tree = model.parseTree()
            }
        }
        .onChange(of: model.mode) { newValue in
            if newValue == .tree {
                tree = model.parseTree()
            }
        }
        .onChange(of: find.current) { _ in
            guard model.mode == .text, let range = find.currentRange else { return }
            editor.scroll(to: range)
        }
        .onAppear {
            find.refresh(with: model.text)
            tree = model.parseTree()
            SnapshotSupport.applyDebugPreset(model: model, find: find)
            SnapshotSupport.captureIfNeeded()
        }
        .onExitCommand {
            if find.isVisible { find.isVisible = false }
        }
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack(spacing: 10) {
            // 左侧：字号 + 主题 + 行号
            HStack(spacing: 10) {
                fontControl
                themeButton
                lineNumberButton
            }

            Spacer(minLength: 8)

            // 中部：视图切换
            Picker("", selection: $model.mode) {
                ForEach(ViewMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 196)

            Spacer(minLength: 8)

            // 右侧：文件与修复操作
            HStack(spacing: 2) {
                actionButton("导入", systemImage: "square.and.arrow.down", help: "导入 JSON 文件 ⌘O") {
                    model.importFile()
                }
                actionButton("格式化", systemImage: "wand.and.stars", help: "格式化 ⌥⌘F") {
                    model.format()
                }
                actionButton("压缩", systemImage: "arrow.down.to.line", help: "压缩为单行 ⌥⌘M") {
                    model.minify()
                }
                actionButton("修复", systemImage: "wrench", help: "一键修复异常 JSON ⌥⌘R") {
                    model.repair(editor: editor)
                }
                actionButton("导出", systemImage: "square.and.arrow.up", help: "导出 JSON ⌘S") {
                    model.exportFile()
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(Color(nsColor: model.theme.barBackground))
    }

    private var fontControl: some View {
        HStack(spacing: 8) {
            Image(systemName: "textformat.size")
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: model.theme.secondaryTextColor))
            Slider(value: Binding(get: { model.fontSize },
                                  set: { model.fontSize = $0.rounded() }),
                   in: 9...28)
                .controlSize(.small)
                .frame(width: 100)
            Text("\(Int(model.fontSize))")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(Color(nsColor: model.theme.secondaryTextColor))
                .frame(width: 22, alignment: .leading)
        }
    }

    private var themeButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.12)) {
                model.toggleTheme()
            }
        } label: {
            Image(systemName: model.theme.iconName)
                .font(.system(size: 13))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Color(nsColor: model.theme.textColor))
        .help(model.theme.toggleHelp)
    }

    private var lineNumberButton: some View {
        Button {
            model.showLineNumbers.toggle()
        } label: {
            Image(systemName: "number")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(model.showLineNumbers
                         ? Color(nsColor: model.theme.textColor)
                         : Color(nsColor: model.theme.secondaryTextColor))
        .help(model.showLineNumbers ? "隐藏行号 ⌥⌘L" : "显示行号 ⌥⌘L")
        .keyboardShortcut("l", modifiers: [.command, .option])
    }

    private var separator: some View {
        Rectangle()
            .fill(Color(nsColor: model.theme.separatorColor))
            .frame(height: 1)
    }

    private func actionButton(_ title: String,
                              systemImage: String,
                              help: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 14))
                Text(title)
                    .font(.system(size: 10))
            }
            .frame(width: 54, height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Color(nsColor: model.theme.textColor))
        .help(help)
    }

    // MARK: - 内容区（文本 / 树状 二选一）

    @ViewBuilder
    private var content: some View {
        switch model.mode {
        case .text:
            ZStack {
                JSONTextView(
                    text: $model.text,
                    fontSize: CGFloat(model.fontSize),
                    theme: model.theme,
                    matches: find.matches,
                    currentMatch: find.current,
                    showLineNumbers: model.showLineNumbers,
                    controller: editor
                )
                if model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    placeholder
                }
            }
        case .tree:
            ZStack {
                if let tree {
                    JSONTreeView(node: tree,
                                 query: find.query,
                                 caseSensitive: find.caseSensitive,
                                 theme: model.theme)
                } else {
                    emptyTreeState
                }
                if model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    placeholder
                }
            }
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "curlybraces")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text("粘贴 JSON、拖入文件，或点击右上角「导入」")
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: model.theme.secondaryTextColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: model.theme.editorBackground))
    }

    private var emptyTreeState: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text("当前内容不是合法 JSON，可点右上角「修复」")
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: model.theme.secondaryTextColor))
            Button("切回文本视图") { model.mode = .text }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: model.theme.editorBackground))
    }

    private func noticeBar(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.green)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: model.theme.secondaryTextColor))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Button {
                model.noticeMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color(nsColor: model.theme.secondaryTextColor))
        }
        .padding(.horizontal, 14)
        .frame(height: 28)
        .background(Color(nsColor: model.theme.barBackground))
    }

    private func errorBar(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: model.theme.secondaryTextColor))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Button {
                model.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color(nsColor: model.theme.secondaryTextColor))
        }
        .padding(.horizontal, 14)
        .frame(height: 28)
        .background(Color(nsColor: model.theme.barBackground))
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let itemURL = item as? URL {
                    url = itemURL
                } else if let string = item as? String {
                    url = URL(string: string)
                }
                guard let url else { return }
                Task { @MainActor in
                    model.load(url: url)
                }
            }
        } else {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                var string: String?
                if let data = item as? Data {
                    string = String(data: data, encoding: .utf8)
                } else if let text = item as? String {
                    string = text
                }
                guard let string else { return }
                Task { @MainActor in
                    model.load(text: string)
                }
            }
        }
    }
}
