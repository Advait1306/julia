import AppKit
import SwiftUI

enum SpeechOverlayLayout {
    static let textSize = NSSize(width: 520, height: 320)
    // Extra space lets the blur reach zero outside the text instead of ending at its edge.
    static let blurSize = NSSize(width: 680, height: 440)
}

final class SpeechOverlayContentView: NSView {
    let blurView = FeatheredBlurView()
    let textView: NSHostingView<SpeechOverlayView>
    private var textAnimation: OverlayAnimation?

    init(assistant: Assistant) {
        textView = NSHostingView(rootView: SpeechOverlayView(assistant: assistant, sst: assistant.sst))
        super.init(frame: .zero)
        textView.wantsLayer = true
        textView.layer?.opacity = 0
        addSubview(blurView)
        addSubview(textView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setTextOpacity(_ opacity: Float, duration: TimeInterval = 0, delay: TimeInterval = 0) {
        textAnimation?.cancel()
        textAnimation = nil
        guard let layer = textView.layer else { return }
        textAnimation = OverlayAnimation(layer: layer, keyPath: "opacity", key: "textOpacity",
                                         to: opacity, duration: duration, delay: delay)
    }

    func cancelAnimations() {
        textAnimation?.cancel()
        textAnimation = nil
        blurView.cancelAnimation()
    }

    override func layout() {
        super.layout()
        blurView.frame = bounds
        let size = NSSize(width: min(SpeechOverlayLayout.textSize.width, bounds.width),
                          height: min(SpeechOverlayLayout.textSize.height, bounds.height))
        textView.frame = NSRect(x: bounds.maxX - size.width, y: bounds.maxY - size.height,
                               width: size.width, height: size.height)
    }
}
