import AppKit
import Combine
import Foundation

@MainActor
final class Appearance: ObservableObject {
    @Published private(set) var isDarkMode = false
    private var observation: NSKeyValueObservation?

    init() {
        refresh()
        // Julia inherits the system appearance, including changes made outside the app.
        observation = NSApplication.shared.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    func enableDarkMode() throws {
        try setDarkMode(true)
    }

    func enableLightMode() throws {
        try setDarkMode(false)
    }

    private func refresh() {
        isDarkMode = NSApplication.shared.effectiveAppearance
            .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private func setDarkMode(_ enabled: Bool) throws {
        let source = """
            tell application "System Events"
                tell appearance preferences
                    set dark mode to \(enabled ? "true" : "false")
                    return dark mode
                end tell
            end tell
            """
        guard let script = NSAppleScript(source: source) else { throw Failure.invalidScript }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            throw Failure.scriptFailed(String(describing: error[NSAppleScript.errorMessage] ?? error))
        }
        isDarkMode = result.booleanValue
    }

    private enum Failure: LocalizedError {
        case invalidScript
        case scriptFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidScript: return "Couldn't create the appearance control script."
            case .scriptFailed(let message): return "Couldn't change macOS appearance: \(message)"
            }
        }
    }
}
