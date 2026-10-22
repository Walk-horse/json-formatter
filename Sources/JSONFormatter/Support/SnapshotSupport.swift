import AppKit

/// 调试用：设置环境变量 JF_SNAPSHOT=/path.png 启动时，把窗口内容渲染成 PNG 后退出。
/// 用于无屏幕录制权限时校验界面。
enum SnapshotSupport {
    /// 调试用：JF_SNAPSHOT_MODE=tree 切到树状视图，JF_SNAPSHOT_QUERY=xxx 打开查找栏并预填关键词。
    @MainActor
    static func applyDebugPreset(model: AppModel, find: FindState) {
        let env = ProcessInfo.processInfo.environment
        if let file = env["JF_SNAPSHOT_FILE"] {
            model.load(url: URL(fileURLWithPath: file))
        }
        if let mode = env["JF_SNAPSHOT_MODE"], mode == "tree" {
            model.mode = .tree
        }
        if let theme = env["JF_SNAPSHOT_THEME"], let parsed = AppTheme(rawValue: theme) {
            model.theme = parsed
        }
        if let query = env["JF_SNAPSHOT_QUERY"] {
            find.isVisible = true
            find.query = query
        }
    }

    @MainActor
    static func captureIfNeeded() {
        guard let path = ProcessInfo.processInfo.environment["JF_SNAPSHOT"] else { return }
        // 直接从命令行启动时应用不会被激活，窗口不可见，需要显式提到前台
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            window.makeKeyAndOrderFront(nil)
        }
        let delay = Double(ProcessInfo.processInfo.environment["JF_SNAPSHOT_DELAY"] ?? "") ?? 1.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) else {
                FileHandle.standardError.write("snapshot: no window\n".data(using: .utf8)!)
                exit(1)
            }
            // 连同标题栏一起截取
            let target = window.contentView?.superview ?? window.contentView!
            target.layoutSubtreeIfNeeded()
            guard let rep = target.bitmapImageRepForCachingDisplay(in: target.bounds) else {
                exit(2)
            }
            target.cacheDisplay(in: target.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: path))
                print("snapshot: \(path) \(Int(rep.size.width))x\(Int(rep.size.height))")
            }
            if ProcessInfo.processInfo.environment["JF_SNAPSHOT_EXIT"] != nil {
                exit(0)
            }
        }
    }
}
