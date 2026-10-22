import AppKit
import SwiftUI

struct JSONTextView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var theme: AppTheme
    var matches: [NSRange]
    var currentMatch: Int
    var showLineNumbers: Bool
    var controller: EditorController

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = theme.editorBackground
        (scrollView.contentView as? NSClipView)?.backgroundColor = theme.editorBackground

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsDocumentBackgroundColorChange = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.usesFindBar = false
        textView.drawsBackground = true
        textView.backgroundColor = theme.editorBackground
        textView.insertionPointColor = theme.textColor
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        Self.applyStyle(to: textView, fontSize: fontSize, theme: theme)
        Self.applyInset(to: textView, showLineNumbers: showLineNumbers)
        if showLineNumbers {
            Self.installRuler(in: scrollView, textView: textView, theme: theme)
        }
        controller.textView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        controller.textView = textView

        syncRuler(in: scrollView, textView: textView)

        if context.coordinator.lastTheme != theme {
            context.coordinator.lastTheme = theme
            applyTheme(to: textView, scrollView: scrollView)
        }

        if !textView.hasMarkedText(), textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            let length = (textView.string as NSString).length
            textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
            Self.applyStyle(to: textView, fontSize: fontSize, theme: theme)
            Self.ruler(in: scrollView)?.invalidateAfterTextChange()
        }

        if textView.font?.pointSize != fontSize {
            Self.applyStyle(to: textView, fontSize: fontSize, theme: theme)
            Self.ruler(in: scrollView)?.invalidateAfterMetricsChange()
        }

        applyHighlights(to: textView)

        if context.coordinator.lastCurrent != currentMatch || context.coordinator.lastMatchCount != matches.count {
            context.coordinator.lastCurrent = currentMatch
            context.coordinator.lastMatchCount = matches.count
            if let range = matches.indices.contains(currentMatch) ? matches[currentMatch] : nil {
                textView.scrollRangeToVisible(range)
            }
        }
    }

    private func applyTheme(to textView: NSTextView, scrollView: NSScrollView) {
        scrollView.backgroundColor = theme.editorBackground
        (scrollView.contentView as? NSClipView)?.backgroundColor = theme.editorBackground
        textView.backgroundColor = theme.editorBackground
        textView.insertionPointColor = theme.textColor
        Self.applyStyle(to: textView, fontSize: fontSize, theme: theme)
        Self.ruler(in: scrollView)?.theme = theme
    }

    // MARK: - 行号栏

    private static func ruler(in scrollView: NSScrollView) -> LineNumberRulerView? {
        scrollView.verticalRulerView as? LineNumberRulerView
    }

    private static func installRuler(in scrollView: NSScrollView, textView: NSTextView, theme: AppTheme) {
        let ruler = LineNumberRulerView(textView: textView, theme: theme)
        scrollView.hasVerticalRuler = true
        scrollView.verticalRulerView = ruler
        scrollView.rulersVisible = true
    }

    private func syncRuler(in scrollView: NSScrollView, textView: NSTextView) {
        if showLineNumbers {
            if scrollView.verticalRulerView == nil {
                Self.installRuler(in: scrollView, textView: textView, theme: theme)
                Self.applyInset(to: textView, showLineNumbers: true)
            }
        } else if scrollView.verticalRulerView != nil {
            scrollView.verticalRulerView = nil
            scrollView.hasVerticalRuler = false
            Self.applyInset(to: textView, showLineNumbers: false)
        }
    }

    private static func applyInset(to textView: NSTextView, showLineNumbers: Bool) {
        textView.textContainerInset = NSSize(width: showLineNumbers ? 8 : 18, height: 16)
    }

    // MARK: - Styling

    static func applyStyle(to textView: NSTextView, fontSize: CGFloat, theme: AppTheme) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 1.5
        paragraph.tabStops = []
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: theme.textColor,
            .paragraphStyle: paragraph
        ]
        textView.typingAttributes = attributes
        textView.defaultParagraphStyle = paragraph
        textView.font = font
        textView.textColor = theme.textColor
    }

    private func applyHighlights(to textView: NSTextView) {
        guard let layoutManager = textView.layoutManager, let storage = textView.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
        layoutManager.removeTemporaryAttribute(.underlineColor, forCharacterRange: full)
        layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: full)

        guard !matches.isEmpty else { return }
        for (index, range) in matches.enumerated() where NSMaxRange(range) <= storage.length {
            if index == currentMatch {
                layoutManager.addTemporaryAttribute(.backgroundColor,
                                                    value: theme.currentMatchBackground,
                                                    forCharacterRange: range)
            } else {
                layoutManager.addTemporaryAttribute(.backgroundColor,
                                                    value: theme.matchBackground,
                                                    forCharacterRange: range)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: JSONTextView
        var lastCurrent = -1
        var lastMatchCount = -1
        var lastTheme: AppTheme?

        init(_ parent: JSONTextView) {
            self.parent = parent
            self.lastTheme = parent.theme
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard !textView.hasMarkedText() else { return }
            if parent.text != textView.string {
                parent.text = textView.string
            }
            if let ruler = textView.enclosingScrollView?.verticalRulerView as? LineNumberRulerView {
                ruler.invalidateAfterTextChange()
            }
        }
    }
}
