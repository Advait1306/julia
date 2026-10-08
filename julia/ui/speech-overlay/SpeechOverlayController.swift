import AppKit
import Combine

@MainActor
final class SpeechOverlayController {
    private let panel: NSPanel
    private let content: SpeechOverlayContentView
    private var subscription: AnyCancellable?
    private var screenObserver: NSObjectProtocol?

    init(assistant: Assistant) {
        content = SpeechOverlayContentView(assistant: assistant)
        panel = SpeechPanel(contentView: content)
        position(on: NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main)
        panel.orderFrontRegardless()
        content.layoutSubtreeIfNeeded()

        subscription = assistant.$speechDisplay.sink { [weak self] display in
            self?.update(display)
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.position(on: NSScreen.screens.first(where: { $0.frame.contains(self.panel.frame.origin) })
                              ?? NSScreen.main)
            }
        }
    }

    private func update(_ display: Assistant.SpeechDisplay) {
        switch display {
        case .hidden:
            hide()
        case .active:
            show()
        case .completed:
            hide(after: 1.4)
        case .message:
            hide(after: 6)
        }
    }

    private func show() {
        content.cancelAnimations()
        // The pointer selects the display on every new session, including while idle.
        position(on: NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main)
        content.layoutSubtreeIfNeeded()
        let blurDuration = content.blurView.radius == 18 ? 0 : blurTransitionDuration
        let textDuration = content.textView.layer?.opacity == 1 ? 0 : textTransitionDuration
        content.blurView.setRadius(18, duration: blurDuration)
        content.setTextOpacity(1, duration: textDuration, delay: blurDuration)
    }

    private func position(on screen: NSScreen?) {
        guard let screen else { return }
        let bounds = screen.visibleFrame
        let size = NSSize(width: min(SpeechOverlayLayout.blurSize.width, bounds.width),
                          height: min(SpeechOverlayLayout.blurSize.height, bounds.height))
        panel.setFrame(NSRect(x: bounds.maxX - size.width, y: bounds.maxY - size.height,
                              width: size.width, height: size.height), display: true)
    }

    private func hide(after delay: TimeInterval = 0) {
        content.cancelAnimations()
        let textDuration = content.textView.layer?.opacity == 0 ? 0 : textTransitionDuration
        let blurDuration = content.blurView.radius == 0 ? 0 : blurTransitionDuration
        content.setTextOpacity(0, duration: textDuration, delay: delay)
        content.blurView.setRadius(0, duration: blurDuration, delay: delay + textDuration)
    }

    private var blurTransitionDuration: TimeInterval {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.24
    }

    private var textTransitionDuration: TimeInterval {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12
    }

    isolated deinit {
        content.cancelAnimations()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        panel.orderOut(nil)
    }
}
