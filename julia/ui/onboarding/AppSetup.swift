import AppKit
import Combine
import Foundation

@MainActor
final class AppSetup: ObservableObject {
    @Published private(set) var hasAPIKey = false
    @Published private(set) var keychainError: String?
    @Published private(set) var isComplete: Bool
    let assistant: Assistant
    let permissions: AppPermissions
    private let keychain = JevKeychain()

    init() {
        let assistant = Assistant()
        self.assistant = assistant
        permissions = AppPermissions(assistant: assistant)
        isComplete = UserDefaults.standard.bool(forKey: "onboarding.completed")
        refreshKeyStatus()
    }

    func refreshKeyStatus() {
        do {
            hasAPIKey = try keychain.containsKey()
            keychainError = nil
        } catch {
            hasAPIKey = false
            keychainError = error.localizedDescription
        }
    }

    func readAPIKey() throws -> String? {
        try keychain.read()
    }

    func saveAPIKey(_ key: String) throws {
        try keychain.save(key)
        refreshKeyStatus()
    }

    func removeAPIKey() throws {
        try keychain.delete()
        refreshKeyStatus()
    }

    func complete() {
        guard permissions.voiceReady, hasAPIKey, assistant.sst.modelState == .ready else { return }
        UserDefaults.standard.set(true, forKey: "onboarding.completed")
        isComplete = true
        Task { await assistant.activate() }
    }
}
