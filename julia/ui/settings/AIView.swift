import SwiftUI

struct AIView: View {
    @ObservedObject var setup: AppSetup
    @Binding var apiKey: String
    var savesOnFocusLoss = true
    var showsSectionHeaders = true

    var body: some View {
        Form {
            DecisionModelSection(setup: setup, key: $apiKey, savesOnFocusLoss: savesOnFocusLoss,
                                 showsSectionHeaders: showsSectionHeaders)
            SpeechModelSection(sst: setup.assistant.sst, showsSectionHeaders: showsSectionHeaders)
        }
        .formStyle(.grouped)
    }
}
