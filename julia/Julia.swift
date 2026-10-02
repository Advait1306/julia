import SwiftUI

@main struct Julia: App {
    @StateObject private var assistant = Assistant()

    var body: some Scene {
        WindowGroup {
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
    }
}
