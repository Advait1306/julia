import AppKit
import Combine
import SwiftUI

private enum SpeechOverlayLayout {
    static let textSize = NSSize(width: 520, height: 320)
    // Extra space lets the blur reach zero outside the text instead of ending at its edge.
    static let blurSize = NSSize(width: 680, height: 440)
}

/// A nonactivating panel keeps the app beneath it focused, including in full screen.
@MainActor
final class SpeechOverlayController {
    private let panel: NSPanel
    private let content: SpeechOverlayContentView
    private var subscription: AnyCancellable?
    private var screenObserver: NSObjectProtocol?
    private var dismissTask: Task<Void, Never>?
    private var transitionID = UUID()
    private var isPresented = false

    init(assistant: Assistant) {
        content = SpeechOverlayContentView(assistant: assistant)
        panel = SpeechPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.contentView = content

        subscription = assistant.$speechDisplay.sink { [weak self] display in
            self?.update(display)
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isPresented else { return }
                self.position(on: NSScreen.screens.first(where: { $0.frame.contains(self.panel.frame.origin) })
                              ?? NSScreen.main)
            }
        }
    }

    private func update(_ display: Assistant.SpeechDisplay) {
        dismissTask?.cancel()
        dismissTask = nil
        switch display {
        case .hidden:
            hide()
        case .active:
            show()
        case .completed:
            show()
            dismiss(after: .seconds(1.4))
        case .message:
            show()
            dismiss(after: .seconds(6))
        }
    }

    private func show() {
        guard !isPresented else { return }
        let id = UUID()
        transitionID = id
        isPresented = true
        content.textView.isHidden = true
        content.setTextOpacity(0)
        if !panel.isVisible {
            // The pointer identifies the display the user is working on; main is the fallback.
            position(on: NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main)
            content.blurView.setRadius(0)
            panel.orderFrontRegardless()
            content.layoutSubtreeIfNeeded()
        }
        content.blurView.setRadius(18, duration: blurTransitionDuration) { [weak self] in
            guard let self, self.isPresented, self.transitionID == id else { return }
            self.content.textView.isHidden = false
            self.content.setTextOpacity(1, duration: self.textTransitionDuration)
        }
    }

    private func position(on screen: NSScreen?) {
        guard let screen else { return }
        let bounds = screen.visibleFrame
        let size = NSSize(width: min(SpeechOverlayLayout.blurSize.width, bounds.width),
                          height: min(SpeechOverlayLayout.blurSize.height, bounds.height))
        panel.setFrame(NSRect(x: bounds.maxX - size.width, y: bounds.maxY - size.height,
                              width: size.width, height: size.height), display: true)
    }

    private func dismiss(after delay: Duration) {
        dismissTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            self?.hide()
        }
    }

    private func hide() {
        guard isPresented else { return }
        let id = UUID()
        transitionID = id
        isPresented = false
        // If dismissed during blur-in, there is no visible text to fade out.
        let duration = content.textView.isHidden ? 0 : textTransitionDuration
        content.setTextOpacity(0, duration: duration) { [weak self] in
            guard let self, !self.isPresented, self.transitionID == id else { return }
            self.content.textView.isHidden = true
            self.content.blurView.setRadius(0, duration: self.blurTransitionDuration) { [weak self] in
                guard let self, !self.isPresented, self.transitionID == id else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    private var blurTransitionDuration: TimeInterval {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.24
    }

    private var textTransitionDuration: TimeInterval {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12
    }

    isolated deinit {
        dismissTask?.cancel()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        panel.orderOut(nil)
    }
}

private final class SpeechPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Text fades independently of the blur so their animations can run in sequence.
private final class SpeechOverlayContentView: NSView {
    let blurView = FeatheredBlurView()
    let textView: NSHostingView<SpeechOverlayView>

    init(assistant: Assistant) {
        textView = NSHostingView(rootView: SpeechOverlayView(assistant: assistant, sst: assistant.sst))
        super.init(frame: .zero)
        textView.wantsLayer = true
        textView.isHidden = true
        addSubview(blurView)
        addSubview(textView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setTextOpacity(_ opacity: Float, duration: TimeInterval = 0, completion: (() -> Void)? = nil) {
        guard let layer = textView.layer else { completion?(); return }
        let current = layer.presentation()?.opacity ?? layer.opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if duration > 0 {
            CATransaction.setCompletionBlock {
                Task { @MainActor in completion?() }
            }
        }
        layer.removeAnimation(forKey: "textOpacity")
        layer.opacity = opacity
        if duration > 0 {
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = current
            animation.toValue = opacity
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(animation, forKey: "textOpacity")
        }
        CATransaction.commit()
        if duration == 0 { completion?() }
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

struct SpeechOverlayView: View {
    @ObservedObject var assistant: Assistant
    @ObservedObject var sst: SST

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: statusSymbol)
                    .font(.system(size: 12, weight: .medium))
                Text(status)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(.secondary)

            ScrollView {
                Group {
                    if case .message = assistant.speechDisplay {
                        Text(text)
                    } else {
                        AnimatedTranscript(text: text)
                    }
                }
                .font(.system(size: 24, weight: .medium))
                .tracking(-0.4)
                .lineSpacing(5)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.bottom)
            .defaultScrollAnchor(.top, for: .alignment)
            .frame(maxHeight: .infinity)
        }
        .padding(.leading, 64)
        .padding(.trailing, 32)
        .padding(.top, 28)
        .padding(.bottom, 64)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Julia. \(status). \(text)")
    }

    private var text: String {
        if case .message(let message) = assistant.speechDisplay { return message }
        // The previous session's transcript may still exist until capture starts.
        if assistant.phase == .starting { return "" }
        return sst.transcript
    }

    private var status: String {
        if case .message = assistant.speechDisplay { return "Julia" }
        if assistant.speechDisplay == .completed { return "Done" }
        switch assistant.phase {
        case .idle: return "Julia"
        case .starting: return "Starting microphone…"
        case .listening: return "Listening"
        case .finishing: return "Finishing…"
        case .processing: return "Working…"
        }
    }

    private var statusSymbol: String {
        if case .message = assistant.speechDisplay { return "exclamationmark.circle" }
        if assistant.speechDisplay == .completed { return "checkmark" }
        return assistant.phase == .processing ? "ellipsis" : "waveform"
    }
}

/// A variable-radius backdrop preserves the colors behind it and gradually reaches
/// zero blur at its interior edges. The mask controls radius, not layer opacity.
/// CABackdropLayer and CAFilter are private Core Animation APIs, resolved at
/// runtime; if unavailable, the view stays transparent rather than adding a fill.
private final class FeatheredBlurView: NSView {
    private var backdrop: CALayer?
    private var maskSize = NSSize.zero
    private var maskScale: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerUsesCoreImageFilters = false

        let selector = NSSelectorFromString("filterWithType:")
        if let backdropClass = NSClassFromString("CABackdropLayer") as? CALayer.Type,
           let filterClass = NSClassFromString("CAFilter"),
           (filterClass as AnyObject).responds(to: selector),
           let blur = (filterClass as AnyObject).perform(selector, with: "variableBlur")?
            .takeUnretainedValue() as? NSObject {
            let backdrop = backdropClass.init()
            backdrop.setValue(true, forKey: "windowServerAware")
            backdrop.setValue(false, forKey: "allowsInPlaceFiltering")
            blur.setValue(0.0, forKey: "inputRadius")
            blur.setValue(true, forKey: "inputNormalizeEdges")
            backdrop.filters = [blur]
            self.backdrop = backdrop
            layer?.addSublayer(backdrop)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setRadius(_ radius: CGFloat, duration: TimeInterval = 0, completion: (() -> Void)? = nil) {
        guard let backdrop else { completion?(); return }
        let keyPath = "filters.variableBlur.inputRadius"
        // Reverse from the currently displayed radius if a new press interrupts blur-out.
        let current = backdrop.presentation()?.value(forKeyPath: keyPath)
            ?? backdrop.value(forKeyPath: keyPath)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if duration > 0 {
            CATransaction.setCompletionBlock {
                Task { @MainActor in completion?() }
            }
        }
        backdrop.removeAnimation(forKey: "blurRadius")
        backdrop.setValue(radius, forKeyPath: keyPath)
        if duration > 0 {
            let animation = CABasicAnimation(keyPath: keyPath)
            animation.fromValue = current
            animation.toValue = radius
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            backdrop.add(animation, forKey: "blurRadius")
        }
        CATransaction.commit()
        if duration == 0 { completion?() }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop?.frame = bounds
        let scale = window?.backingScaleFactor ?? 1
        if bounds.size != maskSize || scale != maskScale,
           let image = makeRadiusMask(size: bounds.size, scale: scale) {
            backdrop?.contentsScale = scale
            backdrop?.setValue(scale, forKey: "scale")
            backdrop?.setValue(image, forKeyPath: "filters.variableBlur.inputMaskImage")
            maskSize = bounds.size
            maskScale = scale
        }
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    private func makeRadiusMask(size: NSSize, scale: CGFloat) -> CGImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let width = Int(ceil(size.width * scale))
        let height = Int(ceil(size.height * scale))
        let fadeWidth = min(260, size.width)
        let fadeHeight = min(220, size.height)
        func smoothstep(_ value: CGFloat) -> CGFloat {
            let t = min(1, max(0, value))
            return t * t * (3 - 2 * t)
        }
        let horizontal = (0..<width).map { smoothstep(CGFloat($0) / scale / fadeWidth) }
        var pixels = Data(count: width * height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            let buffer = bytes.bindMemory(to: UInt8.self)
            for row in 0..<height {
                // CGImage rows start at the top; AppKit's interior edge is at the bottom.
                let vertical = smoothstep(CGFloat(height - 1 - row) / scale / fadeHeight)
                for column in 0..<width {
                    buffer[(row * width + column) * 4 + 3] = UInt8((255 * horizontal[column] * vertical).rounded())
                }
            }
        }
        guard let provider = CGDataProvider(data: pixels as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
