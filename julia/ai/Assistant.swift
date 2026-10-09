import AppKit
import Combine
import Foundation

// TODO: deslop required

@MainActor
final class Assistant: ObservableObject {
    enum Phase: Equatable {
        case idle, starting, listening, finishing, processing
    }

    enum SpeechDisplay: Equatable {
        case hidden, active, completed
        case message(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var speechDisplay: SpeechDisplay = .hidden
    @Published var prompt = ""

    let sst = SST()
    let hotkeys = HotkeyManager()
    let wifiManager = Wifi()
    let bluetoothManager = Bluetooth()
    let appearanceManager = Appearance()
    let playbackManager = Playback()
    let focusManager = Focus()
    let audioManager = Audio()
    let appsManager = Apps()
    let vpnManager = VPN()

    private let jev = Jev()
    private var started = false
    private var sessionID: UUID?
    private var task: Task<Void, Never>?

    init() {
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
        sst.refreshMicrophonePermission()
        guard sst.isReady else {
            if !sst.microphoneEnabled {
                speechDisplay = .message("Enable the microphone from Julia in the menu bar.")
            } else if sst.isPreparingModel {
                speechDisplay = .message("The speech model is getting ready. Try again in a moment.")
            } else {
                speechDisplay = .message("Download the speech model from Julia in the menu bar.")
            }
            return
        }
        let id = UUID()
        sessionID = id
        phase = .starting
        speechDisplay = .active
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.sst.start()
                guard self.sessionID == id else { return }
                self.phase = .listening
            } catch {
                guard self.sessionID == id else { return }
                print("Assistant: \(error.localizedDescription)")
                self.speechDisplay = .message(error.localizedDescription)
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
                let text = try await self.sst.finish().trimmingCharacters(in: .whitespacesAndNewlines)
                guard self.sessionID == id else { return }
                if !text.isEmpty {
                    self.prompt = text
                    self.phase = .processing
                    try await self.runJev(prompt: text)
                }
            } catch {
                guard self.sessionID == id else { return }
                print("Assistant: \(error.localizedDescription)")
                self.speechDisplay = .message(error.localizedDescription)
                await self.sst.cancel()
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
        if let error {
            print("Assistant: \(error.localizedDescription)")
            speechDisplay = .message(error.localizedDescription)
        } else {
            speechDisplay = .hidden
        }
        task = Task { [weak self] in
            guard let self else { return }
            await self.sst.cancel()
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
        phase = .processing
        task = Task { [weak self] in
            guard let self else { return }
            do { try await self.runJev(prompt: text) }
            catch { print("Assistant: \(error.localizedDescription)") }
            self.complete(id)
        }
    }

    private func complete(_ id: UUID) {
        guard sessionID == id else { return }
        sessionID = nil
        if speechDisplay == .active {
            speechDisplay = phase == .processing ? .completed : .hidden
        }
        phase = .idle
        task = nil
    }

    private func runJev(prompt: String) async throws {
        let response = try await jev.evaluate(prompt: prompt, state: SettingsState(
            wifi: wifiManager.isEnabled,
            bluetooth: bluetoothManager.isEnabled,
            darkMode: appearanceManager.isDarkMode,
            audio: .init(devices: audioManager.devices, selectedDeviceID: audioManager.selectedDeviceID,
                         isMuted: audioManager.isMuted),
            focus: .init(modes: focusManager.modes, isActive: focusManager.isActive,
                         currentModeID: focusManager.currentModeID),
            apps: appsManager.installed,
            vpns: try vpnManager.readConnections()
        ))

        if response.wifi != wifiManager.isEnabled {
            if response.wifi { try wifiManager.enable() } else { try wifiManager.disable() }
        }

        if response.bluetooth != bluetoothManager.isEnabled {
            if response.bluetooth { bluetoothManager.enable() } else { bluetoothManager.disable() }
        }

        if response.darkMode != appearanceManager.isDarkMode {
            if response.darkMode {
                try appearanceManager.enableDarkMode()
            } else {
                try appearanceManager.enableLightMode()
            }
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

        if let id = response.appID {
            try await appsManager.openApp(id: id)
        }

        try vpnManager.apply(response.vpnChanges)

        NSSound(named: "Purr")?.play()
    }
}
