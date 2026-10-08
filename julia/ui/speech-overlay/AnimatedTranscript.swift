import Foundation
import QuartzCore
import SwiftUI

// TODO: deslop required

struct AnimatedTranscript: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var words: [TranscriptWord] = []
    @State private var isAnimating = false
    @State private var fadeDeadline: TimeInterval = 0

    var body: some View {
        let renderedText = words.enumerated().reduce(Text("")) { result, item in
            let separator = item.offset == 0 ? "" : " "
            let word = Text(separator + item.element.text)
                .customAttribute(WordArrival(time: item.element.arrivedAt))
            return Text("\(result)\(word)")
        }

        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !isAnimating || reduceMotion)) { _ in
            renderedText.textRenderer(WordFadeRenderer(time: CACurrentMediaTime(), reduceMotion: reduceMotion))
        }
        .onChange(of: text, initial: true) { _, value in
            let now = CACurrentMediaTime()
            words = TranscriptWord.updating(words, with: value, at: now)
            fadeDeadline = words.map(\.arrivedAt).max().map { $0 + WordArrival.duration } ?? 0
            isAnimating = !reduceMotion && now < fadeDeadline
        }
        .onChange(of: reduceMotion) { _, enabled in
            isAnimating = !enabled && CACurrentMediaTime() < fadeDeadline
        }
        .task(id: isAnimating ? fadeDeadline : 0) {
            guard isAnimating else { return }
            let remaining = max(0, fadeDeadline - CACurrentMediaTime())
            do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
            isAnimating = false
        }
        .accessibilityLabel(text)
    }
}

nonisolated struct TranscriptWord {
    let text: String
    let arrivedAt: TimeInterval

    private var matchKey: String {
        let key = text.trimmingCharacters(in: .punctuationCharacters).lowercased()
        return key.isEmpty ? text : key
    }

    static func updating(_ previous: [Self], with text: String, at time: TimeInterval) -> [Self] {
        let incoming = text.split(whereSeparator: \.isWhitespace).map {
            Self(text: String($0), arrivedAt: time)
        }
        let changes = incoming.map(\.matchKey).difference(from: previous.map(\.matchKey))
        var inserted = Set<Int>()
        var removed = Set<Int>()
        for change in changes {
            switch change {
            case .insert(let offset, _, _): inserted.insert(offset)
            case .remove(let offset, _, _): removed.insert(offset)
            }
        }
        var retained = previous.enumerated().filter { !removed.contains($0.offset) }.map(\.element).makeIterator()
        return incoming.enumerated().map { offset, word in
            if inserted.contains(offset) { return word }
            return Self(text: word.text, arrivedAt: retained.next()!.arrivedAt)
        }
    }
}

nonisolated struct WordArrival: TextAttribute {
    static let duration: TimeInterval = 0.12
    let time: TimeInterval

    func opacity(at now: TimeInterval) -> Double {
        let progress = min(1, max(0, (now - time) / Self.duration))
        return progress * progress * (3 - 2 * progress)
    }
}

nonisolated struct WordFadeRenderer: TextRenderer {
    let time: TimeInterval
    let reduceMotion: Bool

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                var wordContext = context
                if !reduceMotion, let arrival = run[WordArrival.self] {
                    wordContext.opacity *= arrival.opacity(at: time)
                }
                wordContext.draw(run)
            }
        }
    }
}
