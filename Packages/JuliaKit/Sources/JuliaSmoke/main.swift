import Foundation
import JuliaKit

/// Integration test double: exercise real model selection, never launch an app.
private actor OpeningCheckTools: ToolExecuting {
    let expected: String
    var opened = 0
    init(expected: String) { self.expected = expected }
    func execute(name: String, arguments: [String: JSONValue]) throws -> JSONValue {
        guard let definition = ToolCatalog.all.first(where: { $0.name == name }) else { throw JuliaError("Unknown tool '\(name)'.") }
        try definition.validate(arguments)
        guard name == "system.open_application" else { throw JuliaError("This test supports application opening only.") }
        let target = arguments["application"]?.string ?? ""
        let accepted = expected == "Settings" ? ["System Settings", "com.apple.systempreferences"] : [expected]
        guard accepted.contains(where: { $0.caseInsensitiveCompare(target) == .orderedSame }) else {
            throw JuliaError("Application '\(target)' was not found. Use the app the user requested.")
        }
        opened += 1
        return .object(["status": .string("opened"), "name": .string(target), "wasRunning": .bool(false)])
    }
}

/// Real-model prompt checks with synthetic data; never accesses Contacts or EventKit.
private actor DataCheckTools: ToolExecuting {
    let expectedTool: String
    let query: String?
    let denied: Bool
    var calls = 0
    init(expectedTool: String, query: String?, denied: Bool = false) {
        self.expectedTool = expectedTool; self.query = query; self.denied = denied
    }
    func execute(name: String, arguments: [String: JSONValue]) throws -> JSONValue {
        calls += 1
        guard name == expectedTool,
              let definition = ToolCatalog.all.first(where: { $0.name == name }) else {
            throw JuliaError("Unexpected tool in data check: \(name)")
        }
        try definition.validate(arguments)
        if let query {
            guard arguments["query"]?.string?.lowercased() == query.lowercased() else {
                throw JuliaError("Search must use the name from the user's request.")
            }
        } else {
            guard arguments["list"] == nil,
                  arguments["filter"] == nil || ["incomplete", "all"].contains(arguments["filter"]?.string ?? "") else {
                throw JuliaError("Omit list to retrieve reminders across all lists.")
            }
        }
        if denied { throw JuliaError("Contacts access denied. Grant access in System Settings > Privacy & Security > Contacts.") }
        if let query {
            return .object(["contacts": .array([.object([
                "id": .string("synthetic-contact-879"), "name": .string(query + " Example"),
                "emails": .array([.string("test-contact@example.invalid")]),
                "phones": .array([.string("+1 202-555-0147")])
            ])]), "total": .number(1), "limit": .number(10), "hasMore": .bool(false)])
        }
        return .array([.object(["id": .string("synthetic-reminder-879"),
                               "title": .string("Return library books"), "isCompleted": .bool(false),
                               "list": .string("Personal")])])
    }
}

@main struct Smoke {
    static func main() async throws {
        let trace = try TraceLog()
        print("Trace: \(trace.fileURL.path)")
        if CommandLine.arguments.contains("--native") {
            let result = try await NativeTools().execute(name: "system.info", arguments: [:])
            print(result.json)
            return
        }
        let store = ModelStore()
        let path = try await store.prepare { print($0.message) }
        let runtime = LlamaRuntime()
        try await runtime.load(url: path)
        if CommandLine.arguments.contains("--check-model") {
            // Exercise the app's exact runtime and grammar without executing tools.
            let generation = try await runtime.generate(messages: [
                .init(role: "system", content: AssistantHarness.systemPrompt()),
                .init(role: "user", content: "What is 2 + 2? Answer with just the number.")
            ])
            guard try ModelAction.parse(generation.text) == .answer("4"), generation.stopReason == "complete" else {
                throw JuliaError("Model smoke check failed: \(generation.text)")
            }
            print("PASS: \(ModelStore.modelName) → \(generation.text)")
            print("\(generation.promptTokens) prompt tokens, \(generation.generatedTokens) output tokens, \(generation.duration)s")
            return
        }
        if CommandLine.arguments.contains("--check-data") {
            let cases: [(String, String, String?, Bool)] = [
                ("What's vivek's contact?", "contacts.search", "Vivek", false),
                ("search vivek's contact infromation", "contacts.search", "Vivek", false),
                ("Find Nora's email address", "contacts.search", "Nora", false),
                ("what todos are in my reminders", "reminders.list", nil, false),
                ("what reminders do I have?", "reminders.list", nil, false),
                ("Search Vivek's contact information", "contacts.search", "Vivek", true)
            ]
            for (command, tool, query, denied) in cases {
                let fake = DataCheckTools(expectedTool: tool, query: query, denied: denied)
                let harness = AssistantHarness(model: runtime, tools: fake, trace: trace)
                let answer = try await harness.run(command)
                guard await fake.calls == 1 else { throw JuliaError("Expected one data call for \(command). Got answer: \(answer)") }
                let expected = denied ? "denied" : query == nil ? "Return library books" : query == "Nora" ? "test-contact@example.invalid" : "202-555-0147"
                guard answer.localizedCaseInsensitiveContains(expected) else {
                    throw JuliaError("Answer did not include the supplied result for \(command): \(answer)")
                }
                if query == nil && answer.localizedCaseInsensitiveContains("no reminders") {
                    throw JuliaError("Answer contradicts a nonempty reminder result: \(answer)")
                }
                print("PASS\(denied ? " (denied)" : ""): \(command) → \(answer)")
            }
            return
        }
        if CommandLine.arguments.contains("--check-opening") {
            for (command, target) in [("open the safari app", "Safari"), ("open dia", "Dia"), ("open settings", "Settings"), ("open calendar", "Calendar")] {
                let tools = OpeningCheckTools(expected: target)
                let harness = AssistantHarness(model: runtime, tools: tools, trace: trace)
                let answer = try await harness.run(command)
                guard await tools.opened == 1 else { throw JuliaError("Expected exactly one opening call for \(command). Got answer: \(answer)") }
                print("PASS: \(command) → \(answer)")
            }
            return
        }
        let harness = AssistantHarness(model: runtime, trace: trace)
        let command = CommandLine.arguments.dropFirst().joined(separator: " ")
        let result = try await harness.run(command.isEmpty ? "What is 2 + 2?" : command) { print($0.message) }
        print("ANSWER: \(result)")
    }
}
