import AppKit
import SwiftUI

@main struct Julia: App {
    @NSApplicationDelegateAdaptor(JuliaDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Julia", systemImage: "waveform") {
            SpeechMenuView(setup: delegate.setup, assistant: delegate.assistant,
                           sst: delegate.assistant.sst)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(setup: delegate.setup)
        }
        .defaultSize(width: 680, height: 620)

        Window("Set Up Julia", id: "onboarding") {
            OnboardingView(setup: delegate.setup, permissions: delegate.setup.permissions,
                           sst: delegate.assistant.sst)
        }
        .defaultSize(width: 680, height: 680)
        .defaultPosition(.center)
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(delegate.setup.isComplete ? .suppressed : .presented)
        .restorationBehavior(.disabled)
    }
}

@MainActor
final class JuliaDelegate: NSObject, NSApplicationDelegate {
    let setup = AppSetup()
    var assistant: Assistant { setup.assistant }
    private var overlay: SpeechPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay = SpeechPanel(assistant: assistant)
        if setup.isComplete {
            Task { await assistant.activate() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        assistant.hotkeys.stop()
    }
}
