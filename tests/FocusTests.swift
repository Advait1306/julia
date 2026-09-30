import Foundation

@main
struct FocusTests {
    private enum TestError: Error { case reloadFailed }

    private static func assertFile(_ url: URL, equals expected: Data, _ message: String = "Unexpected file contents") throws {
        let actual = try Data(contentsOf: url)
        precondition(actual == expected, message)
    }

    @MainActor
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configurations = directory.appendingPathComponent("ModeConfigurations.json")
        let assertions = directory.appendingPathComponent("Assertions.json")
        let configuration = #"{"data":[{"modeConfigurations":{"work":{"mode":{"modeIdentifier":"work","name":"Work","visibility":0}},"hidden":{"mode":{"modeIdentifier":"hidden","name":"Placeholder","visibility":1}}}}]}"#
        let original = Data(#"{"header":{"version":8,"timestamp":1,"futureHeader":"keep"},"futureRoot":{"keep":true},"data":[{"storeInvalidationRecords":[{"opaque":"history"}],"storeInvalidationRequestRecords":[{"opaque":"request"}],"futureStore":"keep","storeAssertionRecords":[]}]}"#.utf8)
        try Data(configuration.utf8).write(to: configurations)
        try original.write(to: assertions)
        var reloads = 0
        let focus = Focus(directory: directory, reloadSystem: { reloads += 1 })
        precondition(focus.modes == [FocusMode(id: "work", name: "Work")])
        precondition(focus.isActive == false && focus.currentModeID == nil)
        try await focus.disable()
        precondition(reloads == 0, "Already-off Focus should not restart the daemon")

        try await focus.switchMode(to: "work")
        precondition(focus.isActive == true && focus.currentModeID == "work")
        precondition(reloads == 1 && !focus.isUpdating)
        let beforeRepeatedSelection = try Data(contentsOf: assertions)
        try await focus.switchMode(to: "work")
        precondition(reloads == 1, "Selecting the current mode must preserve its assertion and lifetime")
        try assertFile(assertions, equals: beforeRepeatedSelection)
        let written = try JSONSerialization.jsonObject(with: Data(contentsOf: assertions)) as! [String: Any]
        let store = (written["data"] as! [[String: Any]])[0]
        precondition((written["futureRoot"] as! [String: Bool])["keep"] == true)
        precondition((written["header"] as! [String: Any])["futureHeader"] as! String == "keep")
        precondition(store["futureStore"] as! String == "keep")
        precondition((store["storeInvalidationRecords"] as! [[String: String]])[0]["opaque"] == "history")
        precondition((store["storeInvalidationRequestRecords"] as! [[String: String]])[0]["opaque"] == "request")
        let details = (store["storeAssertionRecords"] as! [[String: Any]])[0]["assertionDetails"] as! [String: String]
        precondition(details["assertionDetailsReason"] == "user-action")
        try await focus.disable()
        precondition(focus.isActive == false && focus.currentModeID == nil && reloads == 2)

        let beforeInvalidSelection = try Data(contentsOf: assertions)
        do {
            try await focus.switchMode(to: "hidden")
            preconditionFailure("Placeholder modes must not be selectable")
        } catch {}
        try assertFile(assertions, equals: beforeInvalidSelection)
        try Data(#"{"data":[{"modeConfigurations":{}}]}"#.utf8).write(to: configurations, options: .atomic)
        do {
            try await focus.switchMode(to: "work")
            preconditionFailure("A removed mode must be rejected even if present in the earlier snapshot")
        } catch {}
        try assertFile(assertions, equals: beforeInvalidSelection)
        try Data(configuration.utf8).write(to: configurations)

        try original.write(to: assertions)
        let failing = Focus(directory: directory, reloadSystem: { throw TestError.reloadFailed })
        do {
            try await failing.switchMode(to: "work")
            preconditionFailure("Reload failure must propagate")
        } catch {}
        try assertFile(assertions, equals: original, "Failed reload must restore the original database")
        precondition(!failing.isUpdating && failing.isActive == false)

        let externalUpdate = Data(#"{"header":{"version":8},"data":[{"storeAssertionRecords":[]}],"externalUpdate":true}"#.utf8)
        let concurrent = Focus(directory: directory, reloadSystem: {
            try externalUpdate.write(to: assertions, options: .atomic)
            throw TestError.reloadFailed
        })
        do {
            try await concurrent.switchMode(to: "work")
            preconditionFailure("Reload failure must propagate")
        } catch {}
        try assertFile(assertions, equals: externalUpdate, "Rollback must preserve newer system updates")

        try Data(#"{"header":{"version":99},"data":[{}]}"#.utf8).write(to: assertions)
        let unknownVersion = try Data(contentsOf: assertions)
        do {
            try await focus.disable()
            preconditionFailure("Unsupported database versions must not be rewritten")
        } catch {}
        try assertFile(assertions, equals: unknownVersion)
        try Data("invalid JSON".utf8).write(to: assertions)
        do {
            try await focus.disable()
            preconditionFailure("Corrupt databases must not be replaced with an empty database")
        } catch {}
        try assertFile(assertions, equals: Data("invalid JSON".utf8))

        // Observe external changes, including atomic replacements and in-place writes.
        try original.write(to: assertions, options: .atomic)
        try await Task.sleep(for: .milliseconds(100))
        precondition(focus.isActive == false)
        try Data(#"{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"work"}}]}]}"#.utf8)
            .write(to: assertions, options: .atomic)
        try await Task.sleep(for: .milliseconds(100))
        precondition(focus.currentModeID == "work")
        try Data(#"{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"work"}},{"assertionDetails":{"assertionDetailsModeIdentifier":"sleep"}}]}]}"#.utf8)
            .write(to: assertions)
        try await Task.sleep(for: .milliseconds(100))
        precondition(focus.isActive == nil && focus.currentModeID == nil)
        try FileManager.default.removeItem(at: configurations)
        try await Task.sleep(for: .milliseconds(100))
        precondition(focus.modes == nil)
        try Data(configuration.utf8).write(to: configurations, options: .atomic)
        try await Task.sleep(for: .milliseconds(100))
        precondition(focus.modes == [FocusMode(id: "work", name: "Work")])
        print("Focus tests passed: switching, disabling, data preservation, stale choices, rollback, concurrent updates, schema rejection and file observation.")
    }
}
