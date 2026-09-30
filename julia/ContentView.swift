import SwiftUI
import Playgrounds

struct ContentView: View {
    
    @StateObject private var wifiManager = Wifi()
    @StateObject private var bluetoothManager = Bluetooth()
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
    
    func runJev(prompt: String) {
        Task {
            do {
                let response = try await jev.evaluate(prompt: prompt, state: SettingsState(
                    wifi: wifiManager.isEnabled,
                    bluetooth: bluetoothManager.isEnabled,
                    audio: .init(
                        devices: audioManager.devices,
                        selectedDeviceID: audioManager.selectedDeviceID,
                        isMuted: audioManager.isMuted
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
