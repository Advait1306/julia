import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @ObservedObject var setup: AppSetup
    @ObservedObject var permissions: AppPermissions
    @ObservedObject var sst: SST
    @AppStorage("onboarding.step") private var savedStep = 1
    @State private var apiKey = ""
    @State private var apiKeyError: String?

    private enum Step: Int, CaseIterable, Hashable {
        // Keep stored step values. Both former AI steps (2 and 3) resume on AI.
        case permissions = 1, ai = 2, ready = 4

        var title: String {
            switch self {
            case .permissions: "Permissions"
            case .ai: "AI"
            case .ready: "Get Started"
            }
        }
    }

    // Preserve navigation and saved progress while keeping page controls below the form.
    private var path: Binding<[Step]> {
        Binding {
            Step.allCases.filter { $0 != .permissions && $0.rawValue <= savedStep }
        } set: { steps in
            savedStep = steps.last?.rawValue ?? Step.permissions.rawValue
        }
    }

    var body: some View {
        NavigationStack(path: path) {
            page(.permissions)
                .navigationDestination(for: Step.self) { step in page(step) }
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 580, idealHeight: 680)
        .task { await sst.restoreModelIfAvailable() }
        .task(id: savedStep) {
            setup.refreshKeyStatus()
            await permissions.refresh()
        }
        .onChange(of: apiKey) { _, _ in apiKeyError = nil }
    }

    private func page(_ step: Step) -> some View {
        VStack(spacing: 16) {
            content(for: step)

            if let apiKeyError, step == .ai {
                Text(apiKeyError).font(.callout).foregroundStyle(.red)
            }
            if step == .ready && !canContinue(from: step) {
                Text("Review the unfinished steps to start using Julia.").font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                if step != .permissions {
                    Button("Back") { savedStep = step == .ready ? Step.ai.rawValue : Step.permissions.rawValue }
                }
                Spacer()
                Button(step == .ready ? "Start Using Julia" : "Continue") { advance(from: step) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canContinue(from: step))
            }
        }
        .padding(24)
        .navigationTitle(step.title)
        .navigationBarBackButtonHidden()
    }

    @ViewBuilder
    private func content(for step: Step) -> some View {
        switch step {
        case .permissions:
            PermissionsView(permissions: permissions)
        case .ai:
            AIView(setup: setup, apiKey: $apiKey, savesOnFocusLoss: false)
        case .ready:
            GetStartedView()
        }
    }

    private func canContinue(from step: Step) -> Bool {
        switch step {
        case .permissions: permissions.voiceReady
        case .ai: !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && sst.modelState == .ready
        case .ready: permissions.voiceReady && setup.hasAPIKey && sst.modelState == .ready
        }
    }

    private func advance(from step: Step) {
        guard canContinue(from: step) else { return }
        if step == .ai {
            do {
                try setup.saveAPIKey(apiKey)
                apiKeyError = nil
            } catch {
                apiKeyError = error.localizedDescription
                return
            }
        }
        if step == .ready {
            Task {
                await permissions.refresh()
                setup.refreshKeyStatus()
                setup.complete()
                if canContinue(from: step) && setup.isComplete { dismissWindow(id: "onboarding") }
            }
        } else {
            savedStep = step == .permissions ? Step.ai.rawValue : Step.ready.rawValue
        }
    }
}
