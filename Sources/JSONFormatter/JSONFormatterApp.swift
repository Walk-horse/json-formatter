import SwiftUI

/// 命令行直接启动时应用不会被激活，窗口不显示，SwiftUI 也不会渲染（onAppear 不触发），
/// 导致 JF_SNAPSHOT 钩子失效。这里在启动完成时强制激活。
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["JF_SNAPSHOT"] != nil else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct JSONFormatterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @StateObject private var find = FindState()

    init() {
        SelfTest.runIfRequested()
    }

    var body: some Scene {
        WindowGroup("JSON格式化工具") {
            ContentView(model: model, find: find)
                .frame(minWidth: 760, minHeight: 480)
        }
        .defaultSize(width: 900, height: 780)
        .commands {
            AppCommands(model: model, find: find)
        }
    }
}

struct AppCommands: Commands {
    @ObservedObject var model: AppModel
    @ObservedObject var find: FindState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("导入 JSON 文件…") { model.importFile() }
                .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {
            Button("导出…") { model.exportFile() }
                .keyboardShortcut("s", modifiers: .command)
            Button("复制全部内容") { model.copyToPasteboard() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
        }

        CommandMenu("JSON") {
            Button("格式化") { model.format() }
                .keyboardShortcut("f", modifiers: [.command, .option])
            Button("压缩为单行") { model.minify() }
                .keyboardShortcut("m", modifiers: [.command, .option])
            Divider()
            Button("查找与替换") {
                find.isVisible = true
                find.focusRequest += 1
            }
            .keyboardShortcut("f", modifiers: .command)
            Button("查找下一个") { find.next() }
                .keyboardShortcut("g", modifiers: .command)
            Button("查找上一个") { find.previous() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Divider()
            Button("一键修复异常 JSON") { model.repair() }
                .keyboardShortcut("r", modifiers: [.command, .option])
            Divider()
            Button("文本视图") { model.mode = .text }
                .keyboardShortcut("1", modifiers: .command)
            Button("树状视图") { model.mode = .tree }
                .keyboardShortcut("2", modifiers: .command)
            Divider()
            Button(model.theme.isDark ? "切换到浅色主题" : "切换到深色主题") {
                model.toggleTheme()
            }
            .keyboardShortcut("t", modifiers: [.command, .option])
        }
    }
}
