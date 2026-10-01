import SwiftUI
import Playgrounds

struct ContentView: View {
    
    @StateObject private var wifiManager = Wifi()
    @StateObject private var bluetoothManager = Bluetooth()
    @StateObject private var playbackManager = Playback()
    @StateObject private var focusManager = Focus()
    @EnvironmentObject private var audioManager: Audio
    private var jev = Jev(apiKey: ProcessInfo.processInfo.environment["JEV_API_KEY"]!)
    
    @State private var jevPrompt: String = ""
    
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
            TextField("Send a prompt to jev", text: $jevPrompt)
                .disableAutocorrection(true)
                .border(.secondary)
                .onSubmit {
                    runJev(prompt: jevPrompt)
                }
            
            Button(action: {
                runJev(prompt: jevPrompt)
            }) {
                Text("Run Jev")
            }
            
        }
        
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
    
    func runJev(prompt: String) {
        Task {
            do {
                let focusModes = focusManager.modes
                let response = try await jev.evaluate(prompt: prompt, state: SettingsState(
                    wifi: wifiManager.isEnabled,
                    bluetooth: bluetoothManager.isEnabled,
                    audio: .init(
                        devices: audioManager.devices,
                        selectedDeviceID: audioManager.selectedDeviceID,
                        isMuted: audioManager.isMuted
                    ),
                    focus: .init(
                        modes: focusModes,
                        isActive: focusManager.isActive,
                        currentModeID: focusManager.currentModeID
                    )
                ))

                if response.wifi != wifiManager.isEnabled {
                    toggleWifi()
                }
                if response.bluetooth != bluetoothManager.isEnabled {
                    toggleBluetooth()
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
                case .off:
                    do { try await focusManager.disable() }
                    catch { print("Focus: \(error.localizedDescription)") }
                case .mode(let id):
                    do { try await focusManager.switchMode(to: id) }
                    catch { print("Focus: \(error.localizedDescription)") }
                }
            } catch {
                print("Jev: \(error.localizedDescription)")
            }
        }
        
    }
}

#Preview {
    ContentView()
        .environmentObject(Audio())
}
