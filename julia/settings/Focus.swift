import Combine
import Foundation

@MainActor
final class Focus: ObservableObject {
    @Published private(set) var modes: [FocusMode]?
    @Published private(set) var isActive: Bool?
    @Published private(set) var currentModeID: String?
    @Published private(set) var isUpdating = false

    private let kit = FocusKit()
    private var observation: AnyCancellable?

    init() {
        observation = kit.changes.sink { [weak self] in self?.refresh() }
        refresh()
    }

    func switchMode(to id: String) async throws {
        try await setMode(id)
    }

    func disable() async throws {
        try await setMode(nil)
    }

    private func setMode(_ id: String?) async throws {
        guard !isUpdating else { throw FocusKit.Failure.updateInProgress }
        isUpdating = true
        defer {
            isUpdating = false
            refresh()
        }
        if let id {
            try await kit.switchMode(to: id)
        } else {
            try await kit.disable()
        }
    }

    private func refresh() {
        do {
            modes = try kit.readModes()
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch {
            modes = nil
            print("Focus: Couldn't read configured modes: \(error.localizedDescription)")
        }

        do {
            let state = try kit.readState()
            isActive = state.isActive
            currentModeID = state.currentModeID
        } catch {
            isActive = nil
            currentModeID = nil
            print("Focus: Couldn't read current mode: \(error.localizedDescription)")
        }
    }
}
