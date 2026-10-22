import AppKit

/// 编辑器行号栏。
///
/// 作为 NSScrollView 的纵向标尺存在，因此滚动、换行、字号变化都会自动对齐：
/// - 行号按「软换行的第一个片段」绘制，折行后续行不重复编号（与 VS Code 一致）
/// - 当前光标所在行用高亮前景色
/// - 宽度随行数位数与字号自适应
final class LineNumberRulerView: NSRulerView {
    private static let leftPadding: CGFloat = 4
    private static let rightPadding: CGFloat = 10

    var theme: AppTheme {
        didSet {
            needsDisplay = true
            updateThickness(force: true)
        }
    }

    private var cachedStarts: [Int]?
    private var cachedLength = -1
    private var lastLineCount = 0
    private var thicknessUpdateScheduled = false

    init(textView: NSTextView, theme: AppTheme) {
        self.theme = theme
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        lastLineCount = Self.lineCount(of: textView.string)
        ruleThickness = Self.preferredThickness(lineCount: lastLineCount,
                                                font: Self.numberFont(of: textView))
        observeScrolling()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// 统一为「自上而下」坐标系，便于在片段顶部直接绘制文字。
    override var isFlipped: Bool { true }

    override var isOpaque: Bool { true }

    // MARK: - 尺寸

    override var requiredThickness: CGFloat {
        Self.preferredThickness(lineCount: max(1, lastLineCount), font: numberFont)
    }

    /// 行数位数或字号变化时刷新栏宽；设置 ruleThickness 会触发外层滚动视图重新布局。
    private func updateThickness(force: Bool = false) {
        let preferred = requiredThickness
        guard force || abs(ruleThickness - preferred) >= 1 else { return }
        ruleThickness = preferred
        scrollView?.tile()
    }

    /// 绘制过程中不能重新布局，推迟到下一个 runloop 再改栏宽。
    private func scheduleThicknessUpdate() {
        guard !thicknessUpdateScheduled else { return }
        thicknessUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.thicknessUpdateScheduled = false
            self.updateThickness()
        }
    }

    private static func preferredThickness(lineCount: Int, font: NSFont) -> CGFloat {
        let digits = max(2, String(lineCount).count)
        let digitWidth = ("8" as NSString).size(withAttributes: [.font: font]).width
        return ceil(digitWidth * CGFloat(digits)) + leftPadding + rightPadding
    }

    private var numberFont: NSFont {
        Self.numberFont(of: clientView as? NSTextView)
    }

    private static func numberFont(of textView: NSTextView?) -> NSFont {
        guard let font = textView?.font else {
            return NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        }
        return font
    }

    // MARK: - 失效与同步

    /// 文本被改写后调用：清掉行首缓存，行数与栏宽在下次绘制时按需重算。
    func invalidateAfterTextChange() {
        cachedStarts = nil
        cachedLength = -1
        needsDisplay = true
    }

    /// 字号变化后调用：栏宽依赖字号，需要重新量。
    func invalidateAfterMetricsChange() {
        invalidateAfterTextChange()
    }

    private func observeScrolling() {
        let center = NotificationCenter.default
        center.addObserver(self,
                           selector: #selector(contentDidScroll),
                           name: NSView.boundsDidChangeNotification,
                           object: scrollView?.contentView)
        center.addObserver(self,
                           selector: #selector(clientDidResize),
                           name: NSView.frameDidChangeNotification,
                           object: clientView)
        // 光标换行时高亮当前行号
        center.addObserver(self,
                           selector: #selector(selectionDidChange),
                           name: NSTextView.didChangeSelectionNotification,
                           object: clientView)
    }

    @objc private func selectionDidChange() {
        needsDisplay = true
    }

    @objc private func contentDidScroll() {
        needsDisplay = true
    }

    @objc private func clientDidResize() {
        updateThickness()
        needsDisplay = true
    }

    // MARK: - 绘制

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = clientView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let thickness = ruleThickness

        theme.editorBackground.setFill()
        NSRect(x: bounds.minX, y: rect.minY, width: thickness, height: rect.height).fill()
        theme.separatorColor.setFill()
        NSRect(x: thickness - 1, y: rect.minY, width: 1, height: rect.height).fill()

        let storage = textView.string as NSString
        let starts = lineStarts(of: storage)
        let font = numberFont
        let trailingNewline = Self.endsWithNewline(storage)

        let countedLines = starts.count + (trailingNewline ? 1 : 0)
        if countedLines != lastLineCount {
            lastLineCount = countedLines
            scheduleThicknessUpdate()
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        paragraph.tabStops = []
        var baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: theme.secondaryTextColor,
            .paragraphStyle: paragraph
        ]
        let activeAttributes: [NSAttributedString.Key: Any] = {
            var attributes = baseAttributes
            attributes[.foregroundColor] = theme.textColor
            return attributes
        }()

        let origin = textView.textContainerOrigin
        let visible = textView.visibleRect
        let queryRect = NSRect(x: visible.minX - origin.x,
                               y: visible.minY - origin.y,
                               width: max(visible.width, textContainer.size.width),
                               height: visible.height)
        var glyphRange = layoutManager.glyphRange(forBoundingRect: queryRect, in: textContainer)
        if glyphRange.location == NSNotFound {
            glyphRange = layoutManager.glyphRange(for: textContainer)
        }

        let currentLine = lineNumber(of: textView.selectedRange().location, in: starts)
        let numberWidth = max(8, thickness - Self.rightPadding)

        // 图层的 masksToBounds 默认关闭，出界的行号会溢到工具栏上，这里显式裁剪。
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: bounds).addClip()

        var glyphIndex = glyphRange.location
        var lastDrawnLine = -1
        while glyphIndex < NSMaxRange(glyphRange) {
            var fragmentRange = NSRange()
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &fragmentRange)
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            var line = lineNumber(of: charIndex, in: starts)
            if trailingNewline && charIndex >= storage.length {
                line = starts.count + 1
            }
            if line != lastDrawnLine {
                lastDrawnLine = line
                let top = textView.convert(NSPoint(x: 0, y: fragment.minY + origin.y), to: self).y
                let numberRect = NSRect(x: 0,
                                        y: top,
                                        width: numberWidth,
                                        height: max(fragment.height, font.pointSize + 2))
                if numberRect.maxY > bounds.minY && numberRect.minY < bounds.maxY {
                    ("\(line)" as NSString).draw(in: numberRect,
                                                 withAttributes: line == currentLine ? activeAttributes : baseAttributes)
                }
            }
            glyphIndex = NSMaxRange(fragmentRange)
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: - 行号计算

    private func lineStarts(of string: NSString) -> [Int] {
        if let cachedStarts, cachedLength == string.length { return cachedStarts }
        var starts: [Int] = []
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length),
                                   options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            starts.append(range.location)
        }
        if starts.isEmpty { starts = [0] }
        cachedStarts = starts
        cachedLength = string.length
        return starts
    }

    private func lineNumber(of charIndex: Int, in starts: [Int]) -> Int {
        var low = 0
        var high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= charIndex {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low + 1
    }

    private static func lineCount(of string: String?) -> Int {
        guard let string, !string.isEmpty else { return 1 }
        let storage = string as NSString
        var count = 0
        storage.enumerateSubstrings(in: NSRange(location: 0, length: storage.length),
                                    options: [.byLines, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        if count == 0 { return 1 }
        if endsWithNewline(storage) { count += 1 }
        return count
    }

    private static func endsWithNewline(_ storage: NSString) -> Bool {
        guard storage.length > 0 else { return false }
        let last = storage.character(at: storage.length - 1)
        guard let scalar = UnicodeScalar(last) else { return false }
        return CharacterSet.newlines.contains(scalar)
    }
}
