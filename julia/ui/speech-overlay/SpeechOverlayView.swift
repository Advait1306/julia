import SwiftUI

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
