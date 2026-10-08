import AppKit
import SwiftUI

@main struct Julia: App {
    @NSApplicationDelegateAdaptor(JuliaDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Julia", systemImage: "waveform") {
            SpeechMenuView(assistant: delegate.assistant,
                           sst: delegate.assistant.sst,
                           hotkeys: delegate.assistant.hotkeys)
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class JuliaDelegate: NSObject, NSApplicationDelegate {
    let assistant = Assistant()
    private var overlay: SpeechPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay = SpeechPanel(assistant: assistant)
        Task { await assistant.activate() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        assistant.hotkeys.stop()
    }
}
