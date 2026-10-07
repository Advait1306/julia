import AppKit
import AVFoundation
import SwiftUI

struct SpeechMenuView: View {
    @ObservedObject var assistant: Assistant
    @ObservedObject var sst: SST
    @ObservedObject var hotkeys: HotkeyManager

    var body: some View {
        Text("Hold right Command to speak")
        Text("Release to send · Esc to cancel")
        Divider()

        Text(modelStatus)
        if sst.modelState != .ready {
            Button(sst.modelState == .failed ? "Retry model download" : "Download speech model") {
                Task { await sst.downloadModel() }
            }
            .disabled(sst.isPreparingModel)
        }

        if sst.microphoneEnabled {
            Text("Microphone enabled")
        } else {
            Button("Enable microphone…") {
                Task {
                    await sst.enableMicrophone()
                    if !sst.microphoneEnabled {
                        openPrivacySettings("Microphone")
                    }
                }
            }
        }

        if hotkeys.globalAccess {
            Text("Global hotkey enabled")
        } else {
            Button("Enable global hotkey…") { hotkeys.requestGlobalAccess() }
            Button("Open Input Monitoring settings…") {
                openPrivacySettings("ListenEvent")
            }
        }

        if assistant.phase == .starting || assistant.phase == .listening {
            Divider()
            Button("Cancel recording") { assistant.cancel() }
        }

        Divider()
        Button("Quit Julia") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
            .onAppear {
                sst.refreshMicrophonePermission()
                hotkeys.refreshAccess()
            }
    }

    private var modelStatus: String {
        switch sst.modelState {
        case .checking: "Checking speech model…"
        case .notDownloaded: "Speech model needs downloading"
        case .downloading(let progress): "Downloading speech model… \(Int(progress * 100))%"
        case .preparing: "Preparing speech model…"
        case .ready: "Speech model ready"
        case .failed: "Speech model couldn't load"
        }
    }

    private func openPrivacySettings(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
}
