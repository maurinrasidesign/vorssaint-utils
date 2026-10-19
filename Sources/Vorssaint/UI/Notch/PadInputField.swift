// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Maurin Rasi

import AppKit
import SwiftUI

/// The Pad's prompt field: a plain text view where Return sends, Shift-Return
/// or Option-Return adds a line, and Escape hands the keyboard back. Dropped
/// files land as attachments rather than as text.
struct PadInputField: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 13
    var onSend: () -> Void
    var onEscape: () -> Void = {}
    var onDropFiles: ([URL]) -> Void = { _ in }
    /// Handed the text view once, so the page can focus it later.
    var onCreate: ((NSTextView) -> Void)?

    static let inset = NSSize(width: 6, height: 6)
    static let lineFragmentPadding: CGFloat = 4

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // TextKit 1 by hand: the subclass needs its own container, and the
        // storage must be held somewhere, which the coordinator does.
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = Self.lineFragmentPadding
        layout.addTextContainer(container)
        context.coordinator.storage = storage

        let view = PadTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 24), textContainer: container)
        view.minSize = NSSize(width: 0, height: 0)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.drawsBackground = false
        view.font = .systemFont(ofSize: fontSize)
        view.textColor = .white
        view.insertionPointColor = .white
        view.textContainerInset = Self.inset
        view.allowsUndo = true
        view.isRichText = false
        view.importsGraphics = false
        view.usesFontPanel = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticDataDetectionEnabled = false
        view.smartInsertDeleteEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.delegate = context.coordinator
        view.coordinator = context.coordinator
        view.registerForDraggedTypes([.fileURL])
        view.string = text
        context.coordinator.view = view

        let scroll = NSScrollView()
        scroll.documentView = view
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        onCreate?(view)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView else { return }
        if view.string != text {
            let selected = view.selectedRange()
            view.string = text
            let end = (text as NSString).length
            let location = min(selected.location, end)
            view.setSelectedRange(NSRange(location: location, length: 0))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PadInputField
        weak var view: NSTextView?
        var storage: NSTextStorage?

        init(_ parent: PadInputField) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view else { return }
            parent.text = view.string
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                if flags.contains(.shift) || flags.contains(.option) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                } else {
                    parent.onSend()
                }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEscape()
                return true
            default:
                return false
            }
        }
    }

    /// Takes dropped files as attachments instead of pasting their paths.
    final class PadTextView: NSTextView {
        weak var coordinator: Coordinator?

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            fileURLs(in: sender).isEmpty ? super.draggingEntered(sender) : .copy
        }

        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            fileURLs(in: sender).isEmpty ? super.draggingUpdated(sender) : .copy
        }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            let urls = fileURLs(in: sender)
            guard !urls.isEmpty else { return super.performDragOperation(sender) }
            coordinator?.parent.onDropFiles(urls)
            return true
        }

        private func fileURLs(in info: NSDraggingInfo) -> [URL] {
            let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
            return info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
        }
    }
}
