import SwiftUI
import Combine
import AppKit
import JuliaKit

@MainActor final class AssistantState: ObservableObject {
    @Published var input = ""
    @Published var lastCommand = ""
    @Published var answer = ""
    @Published var error: String?
    @Published var status = "Preparing your assistant…"
    @Published var ready = false
    @Published var preparing = false
    @Published var busy = false
    @Published var downloadProgress: Double?
    @Published var usedApplications: [String] = []
    @Published var events: [TraceEvent] = []
    private let runtime = LlamaRuntime()
    private let store = ModelStore()
    private var trace: TraceLog?
    private var harness: AssistantHarness?
    private var preparation: Task<Void, Error>?
    private var commandTask: Task<Void, Never>?

    init() {
        do {
            let log = try TraceLog(); trace = log
            log.onEvent = { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.events.append(event)
                    if (self?.events.count ?? 0) > 120 { self?.events.removeFirst() }
                }
            }
            harness = AssistantHarness(model: runtime, trace: log)
            log.record("app.launch", .object(["model": .string(ModelStore.modelName), "logFile": .string(log.fileURL.path)]))
            startPreparation()
        } catch { self.error = "Cannot create trace log: \(error.localizedDescription)" }
    }
    private func startPreparation() {
        guard !preparing else { return }
        preparing = true; error = nil
        preparation = Task { [weak self] in
            guard let self else { return }
            defer { preparing = false; downloadProgress = nil }
            do {
                let path = try await store.prepare { [weak self] progress in
                    Task { @MainActor [weak self] in self?.status = progress.message; self?.downloadProgress = progress.fraction }
                }
                status = "Loading Qwen into memory…"
                trace?.record("model.load.begin", .object(["path": .string(path.path)]))
                try await runtime.load(url: path)
                ready = true; status = "Ready"
                trace?.record("model.load.end")
            } catch {
                self.error = error.localizedDescription; status = "Model setup failed"
                trace?.record("model.load.error", .object(["error": .string(error.localizedDescription)]))
                throw error
            }
        }
    }
    func retryPreparation() { guard !busy else { return }; startPreparation() }
    func submit() {
        let command = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, !busy, let harness else { return }
        if !ready && !preparing { startPreparation() }
        busy = true; error = nil; answer = ""; usedApplications = []; lastCommand = command; input = ""
        commandTask = Task { [weak self] in
            guard let self else { return }
            defer { busy = false; commandTask = nil }
            do {
                try await preparation?.value
                try Task.checkCancellation()
                answer = try await harness.run(command) { [weak self] update in
                    Task { @MainActor [weak self] in
                        self?.status = update.message
                        if let app = update.application, !(self?.usedApplications.contains(app) ?? true) { self?.usedApplications.append(app) }
                    }
                }
                status = "Ready"
            } catch is CancellationError { status = "Stopped"; answer = "Stopped. Any action already completed is recorded in the trace." }
            catch { self.error = error.localizedDescription; status = ready ? "Ready" : "Model setup failed" }
        }
    }
    func cancel() { commandTask?.cancel(); status = "Stopping…" }
    func newConversation() {
        guard !busy else { return }
        input = ""; answer = ""; lastCommand = ""; error = nil; usedApplications = []
        trace?.record("conversation.cleared")
    }
    func revealLog() { if let trace { NSWorkspace.shared.activateFileViewerSelecting([trace.fileURL]) } }
}
