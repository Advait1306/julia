import SwiftUI

struct DecisionModelSection: View {
    @ObservedObject var setup: AppSetup
    @Binding var key: String
    var savesOnFocusLoss = true
    var showsSectionHeaders = true
    @State private var savedKey = ""
    @State private var error: String?

    var body: some View {
        Section {
            LabeledContent("Jev") {
                NativeAPIKeyField(text: $key) {
                    if savesOnFocusLoss { save() }
                }
                .frame(minWidth: 0, idealWidth: 320, maxWidth: 320)
                .frame(height: 22)
                .privacySensitive()
            }
            if let error { Text(error).foregroundStyle(.red) }
            if let keychainError = setup.keychainError { Text(keychainError).foregroundStyle(.red) }
        } header: {
            if showsSectionHeaders { Text("Decision model") }
        } footer: {
            Text("Keys are encrypted and stored in Keychain")
        }
        .onAppear {
            do {
                let stored = try setup.readAPIKey() ?? ""
                savedKey = stored
                key = stored
            } catch { self.error = error.localizedDescription }
        }
        .onChange(of: key) { _, _ in error = nil }
        .onDisappear {
            if savesOnFocusLoss { save() }
            clearInput()
        }
    }

    private func save() {
        guard key != savedKey else { return }
        do {
            if key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try setup.removeAPIKey()
            } else {
                try setup.saveAPIKey(key)
            }
            savedKey = key
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func clearInput() {
        key = ""
        savedKey = ""
    }
}
