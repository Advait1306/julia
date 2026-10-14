import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var setup: AppSetup
    @State private var selection: Page? = .general
    @State private var search = ""
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var apiKey = ""

    enum Page: String, CaseIterable, Identifiable {
        case general, permissions, ai
        var id: Self { self }
        var title: String {
            switch self {
            case .general: "General"
            case .permissions: "Permissions"
            case .ai: "AI"
            }
        }
        var symbol: String {
            switch self {
            case .general: "slider.horizontal.3"
            case .permissions: "hand.raised"
            case .ai: "cpu"
            }
        }
        var keywords: String {
            switch self {
            case .general: "startup login onboarding setup shortcut keyboard about version"
            case .permissions: "microphone keyboard input monitoring bluetooth automation system events full disk access focus privacy"
            case .ai: "jev api key account credential password security keychain decision speech voice transcription model download audio recording"
            }
        }
    }

    private var filteredPages: [Page] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return Page.allCases.filter { term.isEmpty || ($0.title + " " + $0.keywords).localizedCaseInsensitiveContains(term) }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: $selection) {
                ForEach(filteredPages) { page in
                    Label(page.title, systemImage: page.symbol).tag(page)
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $search, placement: .sidebar, prompt: "Search settings")
            .navigationSplitViewColumnWidth(min: 200, ideal: 210, max: 240)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch selection ?? .general {
                case .general: general
                case .permissions: PermissionsView(permissions: setup.permissions, showsSectionHeaders: false)
                case .ai: AIView(setup: setup, apiKey: $apiKey, showsSectionHeaders: false)
                }
            }
        }
        .toolbar(removing: .sidebarToggle)
        .background(SettingsWindowAppearance().frame(width: 0, height: 0))
        .frame(minWidth: 620, idealWidth: 680, minHeight: 540, idealHeight: 620)
        .onChange(of: search) { _, _ in
            if let first = filteredPages.first, !filteredPages.contains(selection ?? .general) { selection = first }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginEnabled = SMAppService.mainApp.status == .enabled
            setup.refreshKeyStatus()
        }
    }

    private var general: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: Binding(get: { loginEnabled }, set: setLoginEnabled))
                if SMAppService.mainApp.status == .requiresApproval {
                    Button("Allow Julia in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                    Text("macOS needs your approval before Julia can open at login.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let loginError { Text(loginError).foregroundStyle(.red) }
            }
            Section {
                LabeledContent("Activate Julia", value: "Right ⌘")
            }
            Section {
                LabeledContent("Onboarding") {
                    Button("Restart") {
                        UserDefaults.standard.set(1, forKey: "onboarding.step")
                        openWindow(id: "onboarding")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func setLoginEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch { loginError = "Couldn’t update Open at Login. \(error.localizedDescription)" }
        loginEnabled = SMAppService.mainApp.status == .enabled
    }
}
