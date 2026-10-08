import AppKit

final class SpeechPanel: NSPanel {
    init(contentView: NSView) {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        isMovable = false
        self.contentView = contentView
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
