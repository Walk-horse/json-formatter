import AppKit
import Foundation

/// 生成应用图标：VS Code 风格的代码块（{ "key": "value" ... }）。
/// 用法：swift tools/make_icon.swift [输出PNG路径]
let canvas: CGFloat = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets/AppIcon.png"

let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

// 圆角轮廓（macOS Big Sur 图标形状）
let radius = canvas * 0.225
let rounded = CGPath(roundedRect: CGRect(x: 0, y: 0, width: canvas, height: canvas),
                     cornerWidth: radius, cornerHeight: radius, transform: nil)
ctx.addPath(rounded)
ctx.clip()

// 背景渐变：右上角偏亮，左下角偏暗
let bgColors = [
    CGColor(red: 0.157, green: 0.169, blue: 0.196, alpha: 1),   // #282b32
    CGColor(red: 0.082, green: 0.090, blue: 0.110, alpha: 1)    // #15171c
] as CFArray
let bgGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                            colors: bgColors, locations: [0, 1])!
ctx.drawLinearGradient(bgGradient,
                       start: CGPoint(x: canvas, y: canvas),
                       end: CGPoint(x: 0, y: 0),
                       options: [])

// 顶部冷色高光，增加质感
let glowColors = [
    CGColor(red: 0.145, green: 0.353, blue: 0.541, alpha: 0.55),
    CGColor(red: 0.145, green: 0.353, blue: 0.541, alpha: 0)
] as CFArray
let glowGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: glowColors, locations: [0, 1])!
ctx.drawLinearGradient(glowGradient,
                       start: CGPoint(x: canvas * 0.5, y: canvas),
                       end: CGPoint(x: canvas * 0.5, y: canvas * 0.52),
                       options: [])

// MARK: - 代码块内容（VS Code 语法配色）

func color(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
    NSColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
}

let fontSize: CGFloat = 100
let codeFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium)
let braceFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)

func part(_ s: String, _ c: NSColor, _ f: NSFont) -> NSAttributedString {
    NSAttributedString(string: s, attributes: [.foregroundColor: c, .font: f])
}

let plain = color(0xD4, 0xD4, 0xD4)
let key = color(0x9C, 0xDC, 0xFE)
let str = color(0xCE, 0x91, 0x78)
let num = color(0xB5, 0xCE, 0xA8)
let kw = color(0x56, 0x9C, 0xD6)

let code = NSMutableAttributedString()
code.append(part("{\n", plain, braceFont))
code.append(part("  \"key\"", key, codeFont))
code.append(part(": ", plain, codeFont))
code.append(part("\"value\"", str, codeFont))
code.append(part("\n  \"num\"", key, codeFont))
code.append(part(": ", plain, codeFont))
code.append(part("42", num, codeFont))
code.append(part("\n  \"ok\"", key, codeFont))
code.append(part(": ", plain, codeFont))
code.append(part("true", kw, codeFont))
code.append(part("\n}", plain, braceFont))

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
paragraph.lineSpacing = 8
code.addAttributes([.paragraphStyle: paragraph], range: NSRange(location: 0, length: code.length))

let bounding = code.boundingRect(with: NSSize(width: canvas, height: canvas),
                                 options: [.usesLineFragmentOrigin])
let drawHeight = ceil(bounding.height)
let drawRect = NSRect(x: 0, y: (canvas - drawHeight) / 2, width: canvas, height: drawHeight)
code.draw(in: drawRect)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(2) }

do {
    try png.write(to: URL(fileURLWithPath: output))
    print("icon -> \(output) \(Int(canvas))x\(Int(canvas))")
} catch {
    FileHandle.standardError.write("write failed: \(error)\n".data(using: .utf8)!)
    exit(3)
}
