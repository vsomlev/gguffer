import AppKit

/// A read-only, monospaced log view that follows the tail unless you scroll up,
/// interprets carriage returns as "rewrite the current line" (llama.cpp's
/// loading progress), and caps how much scrollback it keeps.
final class LogView: NSScrollView {

    private let textView = NSTextView()
    private let maxCharacters = 400_000
    private let trimTo = 300_000

    override init(frame: NSRect) {
        super.init(frame: frame)

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .textColor
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        hasVerticalScroller = true
        autohidesScrollers = false
        // No frame: the log runs to the window's own edges.
        borderType = .noBorder
        documentView = textView
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    var text: String { textView.string }

    func clear() {
        textView.string = ""
    }

    /// Appends server output, or an italicised note from gguffer itself.
    func append(_ chunk: String, isNote: Bool = false) {
        let wasAtBottom = isScrolledToBottom
        guard let storage = textView.textStorage else { return }

        storage.beginEditing()
        if isNote {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            storage.append(NSAttributedString(string: chunk, attributes: attributes))
        } else {
            appendHandlingCarriageReturns(chunk, into: storage)
        }
        storage.endEditing()

        trimIfNeeded()
        if wasAtBottom { textView.scrollToEndOfDocument(nil) }
    }

    private func appendHandlingCarriageReturns(_ chunk: String, into storage: NSTextStorage) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.textColor,
        ]
        var pending = ""

        func flush() {
            guard !pending.isEmpty else { return }
            storage.append(NSAttributedString(string: pending, attributes: attributes))
            pending = ""
        }

        var index = chunk.startIndex
        while index < chunk.endIndex {
            let character = chunk[index]
            let next = chunk.index(after: index)
            if character == "\r" {
                // CRLF is just a newline; a bare CR rewrites the current line.
                if next < chunk.endIndex, chunk[next] == "\n" {
                    index = next
                    continue
                }
                flush()
                eraseCurrentLine(in: storage)
            } else {
                pending.append(character)
            }
            index = next
        }
        flush()
    }

    private func eraseCurrentLine(in storage: NSTextStorage) {
        let string = storage.string as NSString
        guard string.length > 0 else { return }
        let lineStart = string.range(of: "\n", options: .backwards).location
        let start = (lineStart == NSNotFound) ? 0 : lineStart + 1
        storage.deleteCharacters(in: NSRange(location: start, length: string.length - start))
    }

    private func trimIfNeeded() {
        guard let storage = textView.textStorage, storage.length > maxCharacters else { return }
        storage.deleteCharacters(in: NSRange(location: 0, length: storage.length - trimTo))
    }

    private var isScrolledToBottom: Bool {
        let visible = contentView.documentVisibleRect
        let height = documentView?.bounds.height ?? 0
        return visible.maxY >= height - 24
    }
}
