import Foundation
import QuartzCore

/// Cancellation freezes the displayed value before another animation takes over.
@MainActor
final class OverlayAnimation {
    private weak var layer: CALayer?
    private let keyPath: String
    private let key: String

    init(layer: CALayer, keyPath: String, key: String, to value: Any,
         duration: TimeInterval, delay: TimeInterval = 0) {
        self.layer = layer
        self.keyPath = keyPath
        self.key = key

        // The previous animation's cancellation already froze its displayed value.
        let current = layer.value(forKeyPath: keyPath)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setValue(value, forKeyPath: keyPath)
        if duration > 0 {
            let animation = CABasicAnimation(keyPath: keyPath)
            animation.fromValue = current
            animation.toValue = value
            animation.duration = duration
            animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + delay
            animation.fillMode = .backwards
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(animation, forKey: key)
        } else if delay > 0 {
            // Reduce Motion keeps the delay, then changes the value instantly.
            let hold = CAKeyframeAnimation(keyPath: keyPath)
            hold.values = [current ?? value, value]
            hold.keyTimes = [0, 1]
            hold.calculationMode = .discrete
            hold.duration = delay
            hold.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil)
            hold.fillMode = .backwards
            layer.add(hold, forKey: key)
        }
        CATransaction.commit()
    }

    func cancel() {
        guard let layer, let animation = layer.animation(forKey: key) else { return }
        let initialValue = (animation as? CABasicAnimation)?.fromValue
            ?? (animation as? CAKeyframeAnimation)?.values?.first
        let time = layer.convertTime(CACurrentMediaTime(), from: nil)
        let current: Any?
        if animation is CAKeyframeAnimation {
            current = time < animation.beginTime + animation.duration
                ? initialValue : layer.value(forKeyPath: keyPath)
        } else if time < animation.beginTime {
            current = initialValue
        } else {
            current = layer.presentation()?.value(forKeyPath: keyPath)
                ?? layer.value(forKeyPath: keyPath)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setValue(current, forKeyPath: keyPath)
        layer.removeAnimation(forKey: key)
        CATransaction.commit()
    }
}
