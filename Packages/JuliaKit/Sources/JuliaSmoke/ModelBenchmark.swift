import Foundation
import JuliaKit

/// Synthetic requests only; no tools or application data are accessed.
enum ModelBenchmark {
    static func run(runtime: any ModelGenerating) async throws {
        let paragraph = "Rain begins when sunlight warms water in oceans, lakes, and rivers. Some water evaporates and rises into the atmosphere as invisible vapor. As the moist air rises, it cools. Cooler air can hold less water vapor, so the vapor condenses onto tiny particles of dust or salt. These small droplets gather to form clouds. Inside a cloud, droplets collide and combine into larger drops. When the drops become too heavy for rising air currents to support, gravity pulls them toward the ground. If the air below the cloud is warm enough, the drops remain liquid and reach the surface as rain."
        let longAnswer = JSONValue.object(["answer": .string(paragraph)]).json
        let cases = [
            ("short", "What is 2 + 2? Answer with just the number."),
            ("tool", "Return exactly this JSON action: {\"tool\":\"system.open_application\",\"arguments\":{\"application\":\"Safari\"}}"),
            ("long", "Return exactly this JSON action: " + longAnswer)
        ]
        // Fixed date makes inputs identical across runs and backends.
        let system = AssistantHarness.systemPrompt(now: Date(timeIntervalSince1970: 1_789_761_600))
        for (name, command) in cases {
            // Isolate sustained decoding from the app's tool-selection instructions.
            let systemPrompt = name == "long"
                ? "You are a helpful assistant. Return exactly one JSON object with the key \"answer\" and no other text."
                : system
            let expected: ModelAction = name == "short" ? .answer("4") : name == "long" ? .answer(paragraph)
                : .call("system.open_application", ["application": .string("Safari")])
            let messages = [ModelMessage(role: "system", content: systemPrompt), .init(role: "user", content: command)]
            _ = try await runtime.generate(messages: messages) // Shape/kernel warmup, excluded.
            for iteration in 1...3 {
                let result = try await runtime.generate(messages: messages)
                let decodeDuration = max(0.000001, result.duration - result.firstTokenDuration)
                let record: JSONValue = .object([
                    "model": .string(ModelStore.modelName), "case": .string(name),
                    "iteration": .number(Double(iteration)), "promptTokens": .number(Double(result.promptTokens)),
                    "outputTokens": .number(Double(result.generatedTokens)), "durationMs": .number(result.duration * 1000),
                    "firstTokenMs": .number(result.firstTokenDuration * 1000),
                    "decodeTokensPerSecond": .number(Double(max(0, result.generatedTokens - 1)) / decodeDuration),
                    "validAction": .bool((try? ModelAction.parse(result.text)) != nil),
                    "matchesExpectedAction": .bool((try? ModelAction.parse(result.text)) == expected),
                    "stopReason": .string(result.stopReason), "output": .string(result.text)
                ])
                print("BENCH " + record.json)
            }
        }
    }
}
