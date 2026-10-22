import AppKit
import SwiftUI

/// 编辑器主题。配色参考 VS Code 的 Dark+ / Light+ 方案。
enum AppTheme: String, CaseIterable, Identifiable {
    case dark
    case light

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dark: return "深色"
        case .light: return "浅色"
        }
    }

    var isDark: Bool { self == .dark }

    var next: AppTheme { isDark ? .light : .dark }

    var iconName: String { isDark ? "sun.max.fill" : "moon.fill" }

    var toggleHelp: String { isDark ? "切换到浅色主题" : "切换到深色主题" }

    // MARK: - 界面底色

    var editorBackground: NSColor {
        isDark ? NSColor(hex: 0x1E1E1E) : NSColor(hex: 0xFFFFFF)
    }

    var barBackground: NSColor {
        isDark ? NSColor(hex: 0x252526) : NSColor(hex: 0xF3F3F3)
    }

    var secondaryBarBackground: NSColor {
        isDark ? NSColor(hex: 0x2D2D2D) : NSColor(hex: 0xE4E4E4)
    }

    var textColor: NSColor {
        isDark ? NSColor(hex: 0xD4D4D4) : NSColor(hex: 0x1E1E1E)
    }

    var secondaryTextColor: NSColor {
        isDark ? NSColor(hex: 0x9A9A9A) : NSColor(hex: 0x6C6C6C)
    }

    var separatorColor: NSColor {
        isDark ? NSColor(hex: 0x3C3C3C) : NSColor(hex: 0xDDDDDD)
    }

    var accentColor: NSColor {
        isDark ? NSColor(hex: 0x0A84FF) : NSColor(hex: 0x0078D4)
    }

    // MARK: - 命中高亮

    var matchBackground: NSColor {
        NSColor.systemYellow.withAlphaComponent(isDark ? 0.40 : 0.38)
    }

    var currentMatchBackground: NSColor {
        NSColor.systemOrange.withAlphaComponent(isDark ? 0.68 : 0.55)
    }

    // MARK: - 语法配色（对齐 VS Code 的 key / string / number / keyword）

    var syntaxKey: NSColor { isDark ? NSColor(hex: 0x9CDCFE) : NSColor(hex: 0x0451A5) }
    var syntaxString: NSColor { isDark ? NSColor(hex: 0xCE9178) : NSColor(hex: 0xA31515) }
    var syntaxNumber: NSColor { isDark ? NSColor(hex: 0xB5CEA8) : NSColor(hex: 0x098658) }
    var syntaxKeyword: NSColor { isDark ? NSColor(hex: 0x569CD6) : NSColor(hex: 0x0000FF) }
    var syntaxPunctuation: NSColor { isDark ? NSColor(hex: 0xD4D4D4) : NSColor(hex: 0x383838) }

    // MARK: - 外观与持久化

    var nsAppearance: NSAppearance? {
        NSAppearance(named: isDark ? .darkAqua : .aqua)
    }

    private static let defaultsKey = "JSONFormatter.theme"

    static func stored() -> AppTheme {
        let raw = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
        return AppTheme(rawValue: raw) ?? .dark
    }

    static func persist(_ theme: AppTheme) {
        UserDefaults.standard.set(theme.rawValue, forKey: defaultsKey)
    }

    /// 切换 NSApp 外观，让滚动条、文本框等原生控件一并跟随主题。
    static func applyAppearance(_ theme: AppTheme) {
        NSApp.appearance = theme.nsAppearance
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}
