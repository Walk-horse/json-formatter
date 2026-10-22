import AppKit
import SwiftUI

/// 桥接 NSTextView，让外部（查找栏/命令）可以滚动、选中、替换并保留撤销栈。
@MainActor
final class EditorController: ObservableObject {
    weak var textView: NSTextView?

    func focus() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }

    func scroll(to range: NSRange) {
        guard let textView else { return }
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        textView.showFindIndicator(for: range)
    }

    @discardableResult
    func replace(range: NSRange, with newText: String) -> Bool {
        guard let textView, let storage = textView.textStorage,
              NSMaxRange(range) <= storage.length else { return false }
        guard textView.shouldChangeText(in: range, replacementString: newText) else { return false }
        storage.replaceCharacters(in: range, with: newText)
        textView.didChangeText()
        return true
    }

    var hasEditor: Bool { textView != nil }
}
