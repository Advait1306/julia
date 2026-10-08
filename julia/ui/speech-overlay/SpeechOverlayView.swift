import QuartzCore
import SwiftUI

enum SpeechOverlayLayout {
    static let textSize = CGSize(width: 520, height: 320)
    static let blurSize = CGSize(width: 680, height: 440)
}

struct SpeechOverlayView: View {
    @ObservedObject var assistant: Assistant
    @ObservedObject var sst: SST

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var timeline = KeyframeTimeline(initialValue: Presentation()) {
        KeyframeTrack(\.blurRadius) { MoveKeyframe(CGFloat(0)) }
        KeyframeTrack(\.textOpacity) { MoveKeyframe(0.0) }
    }
    @State private var startedAt = CACurrentMediaTime()
    @State private var frames: [Date] = [.now]

    var body: some View {
        TimelineView(.explicit(frames)) { _ in
            let values = timeline.value(time: max(0, CACurrentMediaTime() - startedAt))
            GeometryReader { geometry in
                ZStack(alignment: .topTrailing) {
                    BackgroundBlur(radius: values.blurRadius)
                    // TODO: Check if component in variable is an antipattern
                    transcript
                        .frame(width: min(SpeechOverlayLayout.textSize.width, geometry.size.width),
                               height: min(SpeechOverlayLayout.textSize.height, geometry.size.height))
                        .opacity(values.textOpacity)
                }
            }
        }
        .onReceive(assistant.$speechDisplay, perform: update)
    }

    private func update(_ display: Assistant.SpeechDisplay) {
        let time = CACurrentMediaTime()
        let current = timeline.value(time: max(0, time - startedAt))
        let showing = display == .active

        let delay: TimeInterval = switch display {
        case .completed: 1.4
        case .message: 6
        case .active, .hidden: 0
        }

        let radius: CGFloat = showing ? 18 : 0
        let opacity: Double = showing ? 1 : 0
        let blurDuration = reduceMotion || abs(current.blurRadius - radius) < 0.001 ? 0.0 : 0.24
        let textDuration = reduceMotion || abs(current.textOpacity - opacity) < 0.001 ? 0.0 : 0.12
        let blurDelay = showing ? 0 : delay + textDuration
        let textDelay = showing ? blurDuration : delay

        timeline = KeyframeTimeline(initialValue: current) {
            KeyframeTrack(\.blurRadius) {
                if blurDelay > 0 {
                    LinearKeyframe(current.blurRadius, duration: blurDelay)
                } else {
                    MoveKeyframe(current.blurRadius)
                }
                if blurDuration > 0 {
                    CubicKeyframe(radius, duration: blurDuration, startVelocity: 0, endVelocity: 0)
                } else {
                    MoveKeyframe(radius)
                }
            }
            KeyframeTrack(\.textOpacity) {
                if textDelay > 0 {
                    LinearKeyframe(current.textOpacity, duration: textDelay)
                } else {
                    MoveKeyframe(current.textOpacity)
                }
                if textDuration > 0 {
                    CubicKeyframe(opacity, duration: textDuration, startVelocity: 0, endVelocity: 0)
                } else {
                    MoveKeyframe(opacity)
                }
            }
        }

        startedAt = time
        let now = Date.now
        // Schedule only the fade frames, then stop; a delayed dismissal needs no timer task.
        let fadeStart = showing ? 0 : delay
        let end = now.addingTimeInterval(timeline.duration)
        frames = [now] + stride(from: fadeStart, to: timeline.duration, by: 1.0 / 60)
            .map { now.addingTimeInterval($0) }
        // A trailing entry lets TimelineView render the endpoint before its schedule ends.
        frames += [end, end.addingTimeInterval(1.0 / 60)]
    }

    private struct Presentation {
        var blurRadius: CGFloat = 0
        var textOpacity: Double = 0
    }

    private var transcript: some View {
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
