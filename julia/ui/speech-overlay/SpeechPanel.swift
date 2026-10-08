import AppKit
import Combine
import SwiftUI

final class SpeechPanel: NSPanel {
    private var subscriptions = Set<AnyCancellable>()

    init(assistant: Assistant) {
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

        let hostingView = NSHostingView(rootView: SpeechOverlayView(assistant: assistant, sst: assistant.sst))
        hostingView.sizingOptions = []
        contentView = hostingView
        position(on: pointerScreen)
        orderFrontRegardless()

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.position(on: NSScreen.screens.first(where: { $0.frame.contains(self.frame.origin) })
                              ?? NSScreen.main)
            }
            .store(in: &subscriptions)

        assistant.$speechDisplay
            .filter { $0 == .active }
            .sink { [weak self] _ in
                guard let self else { return }
                self.position(on: self.pointerScreen)
            }
            .store(in: &subscriptions)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private var pointerScreen: NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
    }

    private func position(on screen: NSScreen?) {
        guard let screen else { return }
        let bounds = screen.visibleFrame
        let size = NSSize(width: min(SpeechOverlayLayout.blurSize.width, bounds.width),
                          height: min(SpeechOverlayLayout.blurSize.height, bounds.height))
        setFrame(NSRect(x: bounds.maxX - size.width, y: bounds.maxY - size.height,
                        width: size.width, height: size.height), display: true)
    }

    isolated deinit {
        orderOut(nil)
    }
}
