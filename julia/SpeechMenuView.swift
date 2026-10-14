import AppKit
import SwiftUI

struct SpeechMenuView: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var setup: AppSetup
    @ObservedObject var assistant: Assistant
    @ObservedObject var sst: SST

    var body: some View {
        if setup.isComplete {
            Text("Hold right Command to speak")
            Text("Release to send · Esc to cancel")
            if !setup.hasAPIKey { Text("Add a Jev API key in Settings") }
            if sst.modelState != .ready { Text("Prepare the speech model in Settings") }
        } else {
            Text("Finish setting up voice input")
            Button("Set up Julia…") {
                openWindow(id: "onboarding")
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        if assistant.phase == .starting || assistant.phase == .listening {
            Divider()
            Button("Cancel recording") { assistant.cancel() }
        }

        Divider()
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
            // A native menu key equivalent, not a global hotkey registration.
            .keyboardShortcut(",")
        Divider()
        Button("Quit Julia") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
            .onAppear {
                setup.refreshKeyStatus()
                sst.refreshMicrophonePermission()
                assistant.hotkeys.refreshAccess()
            }
    }
}
