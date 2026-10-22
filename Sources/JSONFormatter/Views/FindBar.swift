import SwiftUI

struct FindBar: View {
    @ObservedObject var model: AppModel
    @ObservedObject var find: FindState
    @ObservedObject var editor: EditorController
    var theme: AppTheme

    private enum Field { case query, replacement }
    @FocusState private var focused: Field?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: theme.secondaryTextColor))

            TextField("查找", text: $find.query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .focused($focused, equals: .query)
                .onSubmit { jump(forward: true) }

            Text(model.mode == .text ? find.countText : (find.query.isEmpty ? "" : "树内高亮"))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(Color(nsColor: theme.secondaryTextColor))
                .frame(minWidth: 46, alignment: .leading)

            chip("Aa", isOn: $find.caseSensitive, help: "区分大小写")
            chip(".*", isOn: $find.useRegex, help: "使用正则表达式")

            Button { jump(forward: false) } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(find.matches.isEmpty)

            Button { jump(forward: true) } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(find.matches.isEmpty)

            Divider().frame(height: 18)

            TextField("替换为", text: $find.replacement)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
                .focused($focused, equals: .replacement)
                .onSubmit { replaceCurrent() }

            Button("替换") { replaceCurrent() }
                .disabled(find.currentRange == nil)

            Button("全部替换") { replaceAll() }
                .disabled(find.matches.isEmpty)

            Spacer(minLength: 4)

            Button {
                find.isVisible = false
                editor.focus()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color(nsColor: theme.secondaryTextColor))
            .help("关闭查找栏")
        }
        .controlSize(.small)
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(Color(nsColor: theme.barBackground))
        // 默认常显：不在 onAppear 抢焦点，否则启动后输入会落到搜索框
        .onChange(of: find.focusRequest) { _ in focused = .query }
        .onChange(of: find.isVisible) { visible in
            if visible { focused = .query }
        }
        .onExitCommand {
            find.isVisible = false
            editor.focus()
        }
    }

    private func chip(_ title: String, isOn: Binding<Bool>, help: String) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Text(verbatim: title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .frame(width: 30, height: 20)
                .foregroundStyle(isOn.wrappedValue
                                 ? Color(nsColor: theme.accentColor)
                                 : Color(nsColor: theme.secondaryTextColor))
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isOn.wrappedValue
                              ? Color(nsColor: theme.accentColor).opacity(0.18)
                              : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isOn.wrappedValue
                                ? Color(nsColor: theme.accentColor).opacity(0.85)
                                : Color(nsColor: theme.secondaryTextColor).opacity(0.3),
                                lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func jump(forward: Bool) {
        guard !find.matches.isEmpty else { return }
        if forward { find.next() } else { find.previous() }
        if let range = find.currentRange {
            editor.scroll(to: range)
        }
    }

    private func replaceCurrent() {
        model.replaceCurrent(find: find, editor: editor)
        if let range = find.currentRange, model.mode == .text {
            editor.scroll(to: range)
        }
    }

    private func replaceAll() {
        model.replaceAll(find: find, editor: editor)
    }
}
