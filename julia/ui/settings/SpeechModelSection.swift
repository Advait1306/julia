import SwiftUI

struct SpeechModelSection: View {
    @ObservedObject var sst: SST
    var showsSectionHeaders = true

    var body: some View {
        Section {
            LabeledContent {
                if sst.modelState == .ready {
                    Text("Ready").foregroundStyle(.secondary)
                } else if sst.isPreparingModel {
                    ProgressView().controlSize(.small)
                } else {
                    Button(sst.modelState == .failed ? "Retry download" : "Download model") {
                        Task { await sst.downloadModel() }
                    }
                }
            } label: {
                Text("Speech model")
                Text(status)
            }
            if case .downloading(let fraction) = sst.modelState {
                ProgressView(value: fraction)
            }
        } header: {
            if showsSectionHeaders { Text("Speech model") }
        }
        .task { await sst.restoreModelIfAvailable() }
    }

    private var status: String {
        switch sst.modelState {
        case .checking: "Checking for an existing model…"
        case .notDownloaded: "Download the model to turn speech into text on your Mac."
        case .downloading(let fraction): "Downloading… \(Int(fraction * 100))%"
        case .preparing: "Preparing the model for this Mac…"
        case .ready: "Downloaded and ready on this Mac."
        case .failed: "Couldn’t prepare the model. Check your connection and available storage, then retry."
        }
    }
}
