import AppKit
import SwiftUI
import Playgrounds

struct ContentView: View {
    
    @EnvironmentObject private var assistant: Assistant
    @EnvironmentObject private var hotkeys: HotkeyManager
    @EnvironmentObject private var wifiManager: Wifi
    @EnvironmentObject private var bluetoothManager: Bluetooth
    @EnvironmentObject private var playbackManager: Playback
    @EnvironmentObject private var focusManager: Focus
    @EnvironmentObject private var audioManager: Audio
    @EnvironmentObject private var sst: SST
    
    var body: some View {
        VStack {
            Text("WiFi")
            Button(action: toggleWifi) {
                Text("\(wifiManager.isEnabled ? "Disable" : "Enable")")
            }
            Text("Bluetooth")
            Button(action: toggleBluetooth) {
                Text("\(bluetoothManager.isEnabled ? "Disable" : "Enable")")
            }
            Text("Playback")
            HStack {
                Button("Play", systemImage: "play.fill") {
                    playbackManager.play()
                }
                Button("Pause", systemImage: "pause.fill") {
                    playbackManager.pause()
                }
            }
            Text("Focus")
            Menu(currentFocusName) {
                Button("Off") { changeFocus(to: nil) }
                ForEach(focusManager.modes ?? []) { mode in
                    Button(mode.name) { changeFocus(to: mode.id) }
                }
            }
            .disabled(focusManager.isUpdating)
            Text("AI")
            speechModelControls
            speechInputControls
            TextField("Send a prompt to jev", text: $assistant.prompt)
                .disableAutocorrection(true)
                .border(.secondary)
                .onSubmit {
                    assistant.submitPrompt()
                }
                .disabled(assistant.phase != .idle)
            
            Button(action: {
                assistant.submitPrompt()
            }) {
                Text("Run Jev")
            }
            .disabled(assistant.phase != .idle || assistant.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            
        }
        .task {
            await assistant.activate()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            sst.refreshMicrophonePermission()
        }
        
    }

    private var speechInputControls: some View {
        VStack(spacing: 6) {
            HStack {
                Circle()
                    .fill(indicatorColor)
                    .frame(width: 10, height: 10)
                    .accessibilityLabel(phaseLabel)
                Text(phaseLabel)
            }
            if !sst.microphoneEnabled {
                Button("Enable microphone") { Task { await sst.enableMicrophone() } }
                Text("Allow microphone access in System Settings if it was previously denied.")
                    .font(.caption)
            }
            if !hotkeys.globalAccess {
                Button("Enable global hotkey") { hotkeys.requestGlobalAccess() }
                Text("The hotkey works while Julia is focused. Allow Input Monitoring to use it in other apps.")
                    .font(.caption)
            }
            if !sst.transcript.isEmpty {
                Text(sst.transcript)
                    .textSelection(.enabled)
                    .frame(maxWidth: 400, alignment: .leading)
            }
        }
    }

    private var indicatorColor: Color {
        switch assistant.phase {
        case .idle, .starting: .secondary
        case .listening: .green
        case .finishing, .processing: .yellow
        }
    }

    private var phaseLabel: String {
        switch assistant.phase {
        case .idle: "Hold right Command to speak"
        case .starting: "Starting microphone…"
        case .listening: "Listening… Release right Command to send"
        case .finishing: "Finishing transcript…"
        case .processing: "Processing with Jev…"
        }
    }

    @ViewBuilder
    private var speechModelControls: some View {
        VStack(spacing: 6) {
            Button("Download SST model") {
                Task { await sst.downloadModel() }
            }
            .disabled(sst.isPreparingModel || sst.modelState == .ready)

            switch sst.modelState {
            case .checking:
                Text("Checking speech model…")
            case .notDownloaded, .failed:
                Text("Parakeet Unified · English · Download from Hugging Face")
            case .downloading(let progress):
                ProgressView(value: progress)
                    .frame(maxWidth: 240)
                Text("Downloading… \(Int(progress * 100))%")
            case .preparing:
                ProgressView()
                    .controlSize(.small)
                Text("Preparing speech model…")
            case .ready:
                Label("Model ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .font(.caption)
    }
    
    func toggleWifi() {
        if (self.wifiManager.isEnabled) {
            try? self.wifiManager.disable()
        } else {
            try? self.wifiManager.enable()
        }
    }
    
    func toggleBluetooth() {
        if (self.bluetoothManager.isEnabled) {
            self.bluetoothManager.disable()
        } else {
            self.bluetoothManager.enable()
        }
    }

    private var currentFocusName: String {
        if focusManager.isActive == false { return "Off" }
        guard let id = focusManager.currentModeID else { return "Unknown" }
        return focusManager.modes?.first(where: { $0.id == id })?.name ?? id
    }

    private func changeFocus(to id: String?) {
        Task {
            do {
                if let id {
                    try await focusManager.switchMode(to: id)
                } else {
                    try await focusManager.disable()
                }
            } catch {
                print("Focus: \(error.localizedDescription)")
            }
        }
    }
    
}

#Preview {
    let assistant = Assistant()
    ContentView()
        .environmentObject(assistant)
        .environmentObject(assistant.sst)
        .environmentObject(assistant.hotkeys)
        .environmentObject(assistant.wifiManager)
        .environmentObject(assistant.bluetoothManager)
        .environmentObject(assistant.playbackManager)
        .environmentObject(assistant.focusManager)
        .environmentObject(assistant.audioManager)
}
