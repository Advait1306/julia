import AppKit
import SwiftUI

/// Keeps one native control and field editor in place. Only its idle cell is
/// secure; AppKit handles cursor placement, selection, and horizontal scrolling.
struct NativeAPIKeyField: NSViewRepresentable {
    @Binding var text: String
    let onCommit: () -> Void

    func makeNSView(context: Context) -> APIKeyTextField {
        let field = APIKeyTextField(frame: .zero)
        field.stringValue = text
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Jev API key")
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: APIKeyTextField, context: Context) {
        context.coordinator.parent = self
        // Don't reset the editor's selection or scroll position after keystrokes.
        if field.stringValue != text { field.stringValue = text }
    }

    static func dismantleNSView(_ field: APIKeyTextField, coordinator: Coordinator) {
        field.stopObserving()
        field.delegate = nil
        field.window?.endEditing(for: field)
        field.stringValue = ""
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NativeAPIKeyField
        init(_ parent: NativeAPIKeyField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? APIKeyTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? APIKeyTextField else { return }
            parent.text = field.stringValue
            field.mask()
            parent.onCommit()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            control.window?.makeFirstResponder(nil)
            return true
        }
    }
}

final class APIKeyTextField: NSSecureTextField {
    private var mouseMonitor: Any?
    private var windowObserver: NSObjectProtocol?
    private var revealed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureCell()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureCell()
    }

    override func mouseDown(with event: NSEvent) {
        // Reveal before AppKit calculates the caret position from the click.
        reveal()
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        reveal()
        let accepted = super.becomeFirstResponder()
        if !accepted { mask() }
        return accepted
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObserving()
        guard let window else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.currentEditor() != nil else { return event }
            if event.window !== self.window || !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) {
                self.window?.makeFirstResponder(nil)
            }
            return event
        }
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.window?.makeFirstResponder(nil)
                self.mask()
            }
        }
    }

    func mask() {
        guard revealed else { return }
        replaceCell(with: NSSecureTextFieldCell(textCell: stringValue))
        revealed = false
    }

    private func reveal() {
        guard !revealed else { return }
        replaceCell(with: NSTextFieldCell(textCell: stringValue))
        revealed = true
    }

    private func replaceCell(with newCell: NSTextFieldCell) {
        cell = newCell
        configureCell()
        needsDisplay = true
    }

    private func configureCell() {
        isEditable = true
        isSelectable = true
        isBordered = false
        isBezeled = false
        drawsBackground = false
        font = .systemFont(ofSize: NSFont.systemFontSize)
        textColor = .labelColor
        alignment = .left
        placeholderString = "API key"
        usesSingleLineMode = true
        maximumNumberOfLines = 1
        lineBreakMode = .byClipping
        allowsWritingTools = false
        (cell as? NSTextFieldCell)?.isScrollable = true
    }

    func stopObserving() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        mouseMonitor = nil
        windowObserver = nil
    }

    isolated deinit { stopObserving() }
}
