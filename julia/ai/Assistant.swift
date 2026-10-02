import AppKit
import Combine
import Foundation

@MainActor
final class Assistant: ObservableObject {
    enum Phase: Equatable {
        case idle, starting, listening, finishing, processing
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var errorMessage: String?
    @Published var prompt = ""

    let sst: SST
    let hotkeys = HotkeyManager()
    let wifiManager = Wifi()
    let bluetoothManager = Bluetooth()
    let playbackManager = Playback()
    let focusManager = Focus()
    let audioManager = Audio()

    private let speech: any SpeechTranscribing
    private let commandHandler: ((String) async throws -> Void)?
    private let jev: Jev?
    private var started = false
    private var sessionID: UUID?
    private var task: Task<Void, Never>?

    init(sst: SST? = nil, speech: (any SpeechTranscribing)? = nil,
         commandHandler: ((String) async throws -> Void)? = nil) {
        let sst = sst ?? SST()
        self.sst = sst
        self.speech = speech ?? sst
        self.commandHandler = commandHandler
        if let key = ProcessInfo.processInfo.environment["JEV_API_KEY"], !key.isEmpty {
            jev = Jev(apiKey: key)
        } else {
            jev = nil
        }
        hotkeys.onPress = { [weak self] in self?.pressed() }
        hotkeys.onRelease = { [weak self] in self?.released() }
        hotkeys.onCancel = { [weak self] in self?.cancel() }
        sst.onCaptureFailure = { [weak self] error in self?.cancel(error: error) }
    }

    func activate() async {
        guard !started else { return }
        started = true
        hotkeys.start()
        await sst.restoreModelIfAvailable()
    }

    func pressed() {
        guard phase == .idle else { return }
        guard speech.isReady else {
            errorMessage = SpeechError.notReady.localizedDescription
            return
        }
        let id = UUID()
        sessionID = id
        errorMessage = nil
        phase = .starting
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.speech.start()
                guard self.sessionID == id else { return }
                self.phase = .listening
            } catch {
                guard self.sessionID == id else { return }
                self.errorMessage = error.localizedDescription
                self.complete(id)
            }
        }
    }

    func released() {
        if phase == .starting { cancel(); return }
        guard phase == .listening, let id = sessionID else { return }
        phase = .finishing
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await self.speech.finish().trimmingCharacters(in: .whitespacesAndNewlines)
                guard self.sessionID == id else { return }
                if !text.isEmpty {
                    self.prompt = text
                    self.phase = .processing
                    try await self.runJev(prompt: text)
                }
            } catch {
                guard self.sessionID == id else { return }
                self.errorMessage = error.localizedDescription
                await self.speech.cancel()
            }
            self.complete(id)
        }
    }

    func cancel(error: Error? = nil) {
        guard sessionID != nil else { return }
        guard phase == .starting || phase == .listening || phase == .finishing else { return }
        sessionID = nil
        task?.cancel()
        let previousTask = task
        phase = .finishing
        if let error { errorMessage = error.localizedDescription }
        task = Task { [weak self] in
            guard let self else { return }
            await self.speech.cancel()
            await previousTask?.value
            self.phase = .idle
            self.task = nil
        }
    }

    func submitPrompt() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard phase == .idle, !text.isEmpty else { return }
        let id = UUID()
        sessionID = id
        errorMessage = nil
        phase = .processing
        task = Task { [weak self] in
            guard let self else { return }
            do { try await self.runJev(prompt: text) }
            catch { self.errorMessage = error.localizedDescription }
            self.complete(id)
        }
    }

    private func complete(_ id: UUID) {
        guard sessionID == id else { return }
        sessionID = nil
        phase = .idle
        task = nil
    }

    private func runJev(prompt: String) async throws {
        if let commandHandler { try await commandHandler(prompt); return }
        guard let jev else {
            throw NSError(domain: "Julia", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "JEV_API_KEY is missing. Launch Julia with its configured Xcode scheme."
            ])
        }
        let response = try await jev.evaluate(prompt: prompt, state: SettingsState(
            wifi: wifiManager.isEnabled,
            bluetooth: bluetoothManager.isEnabled,
            audio: .init(devices: audioManager.devices, selectedDeviceID: audioManager.selectedDeviceID,
                         isMuted: audioManager.isMuted),
            focus: .init(modes: focusManager.modes, isActive: focusManager.isActive,
                         currentModeID: focusManager.currentModeID)
        ))
        if response.wifi != wifiManager.isEnabled {
            if response.wifi { try wifiManager.enable() } else { try wifiManager.disable() }
        }
        if response.bluetooth != bluetoothManager.isEnabled {
            if response.bluetooth { bluetoothManager.enable() } else { bluetoothManager.disable() }
        }
        if let id = response.audioDeviceID, id != audioManager.selectedDeviceID {
            try audioManager.switchDevice(to: id)
        }
        switch response.audioMute {
        case .unchanged: break
        case .mute: audioManager.mute()
        case .unmute: audioManager.unmute()
        }
        switch response.playback {
        case .unchanged: break
        case .play: playbackManager.play()
        case .pause: playbackManager.pause()
        }
        switch response.focus {
        case .unchanged: break
        case .off: try await focusManager.disable()
        case .mode(let id): try await focusManager.switchMode(to: id)
        }
        NSSound(named: "Purr")?.play()
    }
}
