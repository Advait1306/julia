import AppKit
import ApplicationServices
import AVFoundation
import Carbon
import Combine
import CoreBluetooth

@MainActor
final class AppPermissions: ObservableObject {
    enum Permission: String, CaseIterable, Identifiable {
        case microphone, keyboard, bluetooth, automation, focus
        var id: Self { self }
        var required: Bool { self == .microphone || self == .keyboard }
        var title: String {
            switch self {
            case .microphone: "Microphone"
            case .keyboard: "Input Monitoring"
            case .bluetooth: "Bluetooth"
            case .automation: "System Events"
            case .focus: "Full Disk Access"
            }
        }
        var symbol: String {
            switch self {
            case .microphone: "mic.fill"
            case .keyboard: "keyboard"
            case .bluetooth: "antenna.radiowaves.left.and.right"
            case .automation: "gearshape.2.fill"
            case .focus: "moon.fill"
            }
        }
        var detail: String {
            switch self {
            case .microphone: "Use your microphone to listen for commands."
            case .keyboard: "Monitor for the shortcut key to activate when pressed."
            case .bluetooth: "Control your device’s Bluetooth state based on your commands."
            case .automation: "Use System Events to trigger changes based on your commands."
            case .focus: "Read device states, such as the current Focus state."
            }
        }
        var privacyPane: String {
            switch self {
            case .microphone: "Microphone"
            case .keyboard: "ListenEvent"
            case .bluetooth: "Bluetooth"
            case .automation: "Automation"
            case .focus: "AllFiles"
            }
        }
    }

    enum Status: Equatable {
        case notRequested, allowed, denied, restricted, unavailable
        var title: String {
            switch self {
            case .notRequested: "Not enabled"
            case .allowed: "Enabled"
            case .denied: "Needs access"
            case .restricted: "Restricted by macOS"
            case .unavailable: "Not available"
            }
        }
    }

    @Published private(set) var statuses: [Permission: Status] = [:]
    @Published private(set) var requesting: Permission?
    @Published private(set) var errorMessage: String?
    private let assistant: Assistant
    private var refreshing = false

    init(assistant: Assistant) { self.assistant = assistant }

    var voiceReady: Bool { status(.microphone) == .allowed && status(.keyboard) == .allowed }
    func status(_ permission: Permission) -> Status { statuses[permission] ?? .notRequested }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        assistant.sst.refreshMicrophonePermission()
        assistant.hotkeys.refreshAccess()
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: statuses[.microphone] = .allowed
        case .denied: statuses[.microphone] = .denied
        case .restricted: statuses[.microphone] = .restricted
        default: statuses[.microphone] = .notRequested
        }
        statuses[.keyboard] = assistant.hotkeys.globalAccess ? .allowed : .notRequested
        switch CBManager.authorization {
        case .allowedAlways: statuses[.bluetooth] = .allowed
        case .denied: statuses[.bluetooth] = .denied
        case .restricted: statuses[.bluetooth] = .restricted
        default: statuses[.bluetooth] = .notRequested
        }
        assistant.bluetoothManager.startIfAuthorized()
        let focusStatus = await Task.detached { Self.focusAccess() }.value
        if focusStatus == .allowed, statuses[.focus] != .allowed {
            assistant.focusManager.refreshAccess()
        }
        statuses[.focus] = focusStatus
        // Permission checks never launch System Events or display a prompt.
        if requesting != .automation {
            let result = await Task.detached { Self.automationAccess(ask: false) }.value
            statuses[.automation] = Self.automationStatus(result)
        }
    }

    func request(_ permission: Permission) async {
        guard requesting == nil else { return }
        requesting = permission
        errorMessage = nil
        defer { requesting = nil }
        switch permission {
        case .microphone:
            if status(permission) == .denied || status(permission) == .restricted {
                openSettings(permission)
            } else {
                await assistant.sst.enableMicrophone()
            }
        case .keyboard:
            assistant.hotkeys.requestGlobalAccess()
            if !assistant.hotkeys.globalAccess { openSettings(permission) }
        case .bluetooth:
            if status(permission) == .denied || status(permission) == .restricted {
                openSettings(permission)
            } else {
                assistant.bluetoothManager.requestAccess()
            }
        case .automation:
            if status(permission) == .denied {
                openSettings(permission)
            } else {
                do {
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.activates = false
                    _ = try await NSWorkspace.shared.openApplication(
                        at: URL(fileURLWithPath: "/System/Library/CoreServices/System Events.app"),
                        configuration: configuration
                    )
                    let result = await Task.detached { Self.automationAccess(ask: true) }.value
                    statuses[.automation] = Self.automationStatus(result)
                    if result != noErr && result != errAEEventNotPermitted {
                        errorMessage = "Couldn’t request Automation access (\(result)). Try System Settings."
                    }
                } catch {
                    errorMessage = "Couldn’t open System Events. Try System Settings → Privacy & Security → Automation."
                }
            }
        case .focus: openSettings(permission)
        }
        await refresh()
    }

    func openSettings(_ permission: Permission) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(permission.privacyPane)") else { return }
        if !NSWorkspace.shared.open(url) {
            errorMessage = "Open System Settings → Privacy & Security → \(permission.title)."
        }
    }

    private nonisolated static func automationAccess(ask: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.systemevents")
        return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, ask)
    }

    private static func automationStatus(_ result: OSStatus) -> Status {
        switch result {
        case noErr: .allowed
        case OSStatus(errAEEventNotPermitted): .denied
        case OSStatus(errAEEventWouldRequireUserConsent), OSStatus(procNotFound): .notRequested
        default: .unavailable
        }
    }

    /// macOS exposes no public Full Disk Access status API. Probe only the files
    /// FocusKit actually uses; “Enabled” describes access to those files, not TCC.
    private nonisolated static func focusAccess() -> Status {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB", isDirectory: true)
        do {
            for name in ["ModeConfigurations.json", "Assertions.json"] {
                let url = directory.appendingPathComponent(name)
                let handle = try FileHandle(forReadingFrom: url)
                try handle.close()
            }
            return FileManager.default.isWritableFile(atPath: directory.path)
                && FileManager.default.isWritableFile(atPath: directory.appendingPathComponent("Assertions.json").path)
                ? .allowed : .denied
        } catch let error as NSError {
            return error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError
                ? .unavailable : .denied
        }
    }
}
