import AppKit
import AVFoundation
import FluidAudio
@testable import julia

@MainActor
private final class FakeSpeech: SpeechTranscribing {
    var isReady = true
    var text = "  mute audio  \n"
    var starts = 0
    var finishes = 0
    var cancellations = 0
    var startDelay: Duration = .zero
    var finishDelay: Duration = .zero
    var failsFinish = false

    func start() async throws {
        starts += 1
        try await Task.sleep(for: startDelay)
    }
    func finish() async throws -> String {
        finishes += 1
        try await Task.sleep(for: finishDelay)
        if failsFinish { throw SpeechError.noAudio }
        return text
    }
    func cancel() async { cancellations += 1 }
}

@main
struct SSTSmoke {
    @MainActor
    static func eventually(_ predicate: () -> Bool) async throws {
        for _ in 0..<500 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        fatalError("Timed out waiting for state")
    }

    @MainActor
    static func main() async throws {
        let speech = FakeSpeech()
        var sent: [String] = []
        let assistant = Assistant(speech: speech) { text in
            sent.append(text)
            try await Task.sleep(for: .milliseconds(20))
        }
        let keys = assistant.hotkeys
        let right: UInt64 = 0x10 | UInt64(NSEvent.ModifierFlags.command.rawValue)
        func down(_ flags: UInt64 = 0x10 | UInt64(NSEvent.ModifierFlags.command.rawValue)) {
            keys.handle(type: .flagsChanged, keyCode: 54, flags: flags)
        }
        func up(_ flags: UInt64 = 0) {
            keys.handle(type: .flagsChanged, keyCode: 54, flags: flags)
        }

        down(); down()
        try await eventually { assistant.phase == .listening }
        assert(speech.starts == 1)
        up(); up()
        assert(assistant.phase == .finishing)
        try await eventually { assistant.phase == .idle }
        assert(sent == ["mute audio"] && speech.finishes == 1)
        assert(assistant.prompt == "mute audio")

        // Releasing right Command must work even while left Command stays down.
        down(right | 0x08)
        try await eventually { assistant.phase == .listening }
        up(UInt64(NSEvent.ModifierFlags.command.rawValue) | 0x08)
        try await eventually { assistant.phase == .idle }
        assert(sent.count == 2)

        for key: UInt16 in [53, 8] { // Escape and Command-C
            down()
            try await eventually { assistant.phase == .listening }
            keys.handle(type: .keyDown, keyCode: key, flags: right)
            down(); up()
            try await eventually { assistant.phase == .idle }
            assert(sent.count == 2)
        }
        down(right | UInt64(NSEvent.ModifierFlags.shift.rawValue)); up()
        assert(assistant.phase == .idle && sent.count == 2)

        speech.startDelay = .milliseconds(80)
        down(); up()
        try await eventually { assistant.phase == .idle }
        assert(sent.count == 2)
        speech.startDelay = .zero

        // A release that is still flushing can be cancelled without submitting.
        speech.finishDelay = .milliseconds(80)
        down()
        try await eventually { assistant.phase == .listening }
        up(); assistant.cancel()
        try await eventually { assistant.phase == .idle }
        assert(sent.count == 2)
        speech.finishDelay = .zero

        speech.text = "  \n"
        down()
        try await eventually { assistant.phase == .listening }
        up()
        try await eventually { assistant.phase == .idle }
        assert(sent.count == 2)

        speech.failsFinish = true
        down()
        try await eventually { assistant.phase == .listening }
        up()
        try await eventually { assistant.phase == .idle }
        assert(assistant.errorMessage != nil && sent.count == 2)
        speech.failsFinish = false

        let failingSpeech = FakeSpeech()
        let failingAssistant = Assistant(speech: failingSpeech) { _ in throw SpeechError.noAudio }
        failingAssistant.pressed()
        try await eventually { failingAssistant.phase == .listening }
        failingAssistant.released()
        try await eventually { failingAssistant.phase == .idle }
        assert(failingAssistant.prompt == "mute audio" && failingAssistant.errorMessage != nil)
        print("PASS: right/left Command, repeats, shortcuts, early release, cancellation, empty audio and errors")

        try await checkCapturePipe()
        if let fixture = CommandLine.arguments.dropFirst().first {
            try await checkStreaming(URL(fileURLWithPath: fixture))
        }
    }

    static func checkCapturePipe() async throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160)!
        buffer.frameLength = 160
        buffer.floatChannelData![0][0] = 0.25
        let (stream, continuation) = AsyncThrowingStream<AudioChunk, Error>.makeStream(bufferingPolicy: .bufferingOldest(2))
        let pipe = CapturePipe(continuation: continuation)
        pipe.push(buffer)
        buffer.floatChannelData![0][0] = 0.5
        pipe.push(buffer)
        pipe.finish()
        pipe.push(buffer)
        var values: [Float] = []
        for try await chunk in stream { values.append(chunk.buffer.floatChannelData![0][0]) }
        assert(values == [0.25, 0.5] && pipe.receivedAudio)

        let (overflow, limited) = AsyncThrowingStream<AudioChunk, Error>.makeStream(bufferingPolicy: .bufferingOldest(1))
        let bounded = CapturePipe(continuation: limited)
        bounded.push(buffer); bounded.push(buffer)
        do {
            for try await _ in overflow {}
            fatalError("Overflow silently lost audio")
        } catch SpeechError.audioOverflow {}
        print("PASS: tap copies, queued audio drains on release, overflow surfaces an error")
    }

    @MainActor
    static func checkStreaming(_ fixture: URL) async throws {
        ModelHub.offlineMode = true
        let manager = StreamingUnifiedAsrManager(config: UnifiedConfig(leftFrames: 70, chunkFrames: 7, rightFrames: 1))
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Julia/Models").appendingPathComponent(Repo.parakeetUnified.folderName)
        try await manager.loadModels(from: root)
        let file = try AVAudioFile(forReading: fixture)
        let (stream, continuation) = AsyncThrowingStream<AudioChunk, Error>.makeStream(bufferingPolicy: .bufferingOldest(64))
        let pipe = CapturePipe(continuation: continuation)
        while file.framePosition < file.length {
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8192)!
            try file.read(into: buffer)
            pipe.push(buffer)
        }
        pipe.finish()
        var sawPartial = false
        for try await chunk in stream {
            try await manager.appendAudio(chunk.buffer)
            try await manager.processBufferedAudio()
            if !(await manager.getPartialTranscript()).isEmpty { sawPartial = true }
        }
        let text = try await manager.finish()
        assert(sawPartial && text.lowercased().contains("country"))
        print("PASS: real model streams partials and flushes the fixture's final word: \(text)")

        if let key = ProcessInfo.processInfo.environment["JEV_API_KEY"], !key.isEmpty {
            let speech = FakeSpeech()
            speech.text = text
            var submitted = false
            let assistant = Assistant(speech: speech) { transcript in
                assert(transcript == text)
                let response = try await Jev(apiKey: key).evaluate(prompt: transcript, state: .init(
                    wifi: true, bluetooth: false,
                    audio: .init(devices: [], selectedDeviceID: nil, isMuted: false),
                    focus: .init(modes: [], isActive: false, currentModeID: nil)
                ))
                // Public JFK speech requests no settings changes; never apply changes during the test.
                assert(response.wifi && !response.bluetooth && response.audioDeviceID == nil)
                assert(response.audioMute == .unchanged && response.playback == .unchanged)
                guard case .unchanged = response.focus else { fatalError("Unexpected Focus decision") }
                submitted = true
            }
            assistant.pressed()
            try await eventually { assistant.phase == .listening }
            assistant.released()
            // Network completion has a longer deadline than local state transitions.
            for _ in 0..<600 {
                if assistant.phase == .idle { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            assert(submitted && assistant.errorMessage == nil && assistant.phase == .idle)
            print("PASS: released transcript reached the real Jev API; unchanged settings returned")
        }
        try await manager.reset()
        let empty = try await manager.finish()
        assert(empty == "")
        print("PASS: fresh empty session has no stale transcript")
    }
}
