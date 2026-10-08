import AppKit
import QuartzCore
import SwiftUI

struct SpeechBlur: NSViewRepresentable {
    let radius: CGFloat

    func makeNSView(context: Context) -> FeatheredBlurView {
        FeatheredBlurView()
    }

    func updateNSView(_ view: FeatheredBlurView, context: Context) {
        view.setRadius(radius)
    }
}

/// A variable-radius backdrop preserves the colors behind it and gradually reaches
/// zero blur at its interior edges. The mask controls radius, not layer opacity.
/// CABackdropLayer and CAFilter are private Core Animation APIs, resolved at
/// runtime; if unavailable, the view stays transparent rather than adding a fill.
final class FeatheredBlurView: NSView {
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

    var radius: CGFloat {
        CGFloat((backdrop?.value(forKeyPath: "filters.variableBlur.inputRadius") as? NSNumber)?.doubleValue ?? 0)
    }

    func setRadius(_ radius: CGFloat) {
        guard let backdrop else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.setValue(radius, forKeyPath: "filters.variableBlur.inputRadius")
        CATransaction.commit()
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
