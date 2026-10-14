import AppKit
import Combine
import Foundation

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
            var hasActions = false
            do {
                let text = try await self.sst.finish().trimmingCharacters(in: .whitespacesAndNewlines)
                guard self.sessionID == id else { return }
                if !text.isEmpty {
                    self.prompt = text
                    self.phase = .processing
                    hasActions = try await self.execute(prompt: text)
                }
            } catch {
                guard self.sessionID == id else { return }
                print("Assistant: \(error.localizedDescription)")
                self.speechDisplay = .message(error.localizedDescription)
                await self.sst.cancel()
            }
            self.complete(id, hasActions: hasActions)
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
            var hasActions = false
            do { hasActions = try await self.execute(prompt: text) }
            catch { print("Assistant: \(error.localizedDescription)") }
            self.complete(id, hasActions: hasActions)
        }
    }

    private func complete(_ id: UUID, hasActions: Bool = false) {
        guard sessionID == id else { return }
        sessionID = nil
        if speechDisplay == .active {
            speechDisplay = hasActions ? .completed : .hidden
        }
        if hasActions { NSSound(named: "Purr")?.play() }
        phase = .idle
        task = nil
    }

    private func execute(prompt: String) async throws -> Bool {
        let state = SettingsState(
            wifi: wifiManager.isEnabled,
            bluetooth: bluetoothManager.isEnabled,
            darkMode: appearanceManager.isDarkMode,
            audio: .init(devices: audioManager.devices, selectedDeviceID: audioManager.selectedDeviceID,
                         isMuted: audioManager.isMuted),
            focus: .init(modes: focusManager.modes, isActive: focusManager.isActive,
                         currentModeID: focusManager.currentModeID),
            apps: appsManager.installed,
            vpns: vpnManager.connections
        )

        let response = try await jev.evaluate(prompt: prompt, state: state)

        guard response.wifi != state.wifi
            || response.bluetooth != state.bluetooth
            || response.darkMode != state.darkMode
            || response.audioMute != .unchanged
            || response.audioDeviceID != nil
            || response.playback != .unchanged
            || response.focus != .unchanged
            || response.appID != nil
            || !response.vpnChanges.isEmpty else { return false }

        try wifiManager.apply(response.wifi)
        bluetoothManager.apply(response.bluetooth)
        try appearanceManager.apply(response.darkMode)
        try audioManager.apply(deviceID: response.audioDeviceID, mute: response.audioMute)
        playbackManager.apply(response.playback)
        try await focusManager.apply(response.focus)
        try await appsManager.apply(response.appID)
        vpnManager.apply(response.vpnChanges)

        return true
    }
}
