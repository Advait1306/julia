import Foundation
import MLX
import MLXLLM
import MLXLMCommon

public struct ModelMessage: Codable, Sendable, Equatable {
    public let role: String
    public let content: String
    public init(role: String, content: String) { self.role = role; self.content = content }
}
public struct Generation: Sendable {
    public let text: String
    public let promptTokens: Int
    public let generatedTokens: Int
    public let duration: Double
    public let firstTokenDuration: Double
    public let stopReason: String
    public init(text: String, promptTokens: Int = 0, generatedTokens: Int = 0, duration: Double = 0, stopReason: String = "complete", firstTokenDuration: Double = 0) {
        self.text = text; self.promptTokens = promptTokens; self.generatedTokens = generatedTokens
        self.duration = duration; self.stopReason = stopReason; self.firstTokenDuration = firstTokenDuration
    }
}
public protocol ModelGenerating: Sendable {
    func tokenCount(messages: [ModelMessage]) async throws -> Int
    func generate(messages: [ModelMessage]) async throws -> Generation
}

/// Native MLX inference. Each request has fresh KV/recurrent state.
public actor MLXRuntime: ModelGenerating {
    private var container: ModelContainer?
    public static let contextSize = 51_200
    public static let maxOutputTokens = 768
    public static let maxPromptTokens = contextSize - maxOutputTokens - 256
    public static let thinkingEnabled = false
    public init() {}

    public func load(url: URL) async throws {
        guard container == nil else { return }
        container = try await LLMModelFactory.shared.loadContainer(from: url, using: LocalTokenizerLoader())
    }

    public func tokenCount(messages: [ModelMessage]) async throws -> Int {
        guard let container else { throw JuliaError("The model is not loaded yet.") }
        return await container.perform { context in
            context.tokenizer.encode(text: Self.prompt(messages), addSpecialTokens: false).count
        }
    }

    /// Qwen's enable_thinking=false text template, including the closed think block.
    public static func prompt(_ messages: [ModelMessage]) -> String {
        messages.map {
            let prefix = $0.role == "assistant" ? "<think>\n\n</think>\n\n" : ""
            let content = $0.content.replacingOccurrences(of: "<|", with: "< |")
            return "<|im_start|>\($0.role)\n\(prefix)\(content)<|im_end|>\n"
        }.joined() + "<|im_start|>assistant\n<think>\n\n</think>\n\n"
    }

    public func generate(messages: [ModelMessage]) async throws -> Generation {
        guard let container else { throw JuliaError("The model is not loaded yet.") }
        return try await container.perform { context in
            try Task.checkCancellation()
            let start = Date()
            let tokens = context.tokenizer.encode(text: Self.prompt(messages), addSpecialTokens: false)
            guard tokens.count <= Self.maxPromptTokens else {
                throw JuliaError("The request exceeds the model context budget. Start a new command.")
            }
            // Drain asynchronous GPU work on every exit, including cancellation.
            defer { Stream().synchronize() }
            let iterator = try TokenIterator(
                input: LMInput(tokens: MLXArray(tokens)), model: context.model,
                parameters: GenerateParameters(maxTokens: Self.maxOutputTokens, temperature: 0))
            var generated: [Int] = []
            var text = ""
            var firstTokenDuration = 0.0
            var reason = "length"
            var stopTokens = context.configuration.eosTokenIds
            if let eos = context.tokenizer.eosTokenId { stopTokens.insert(eos) }
            for token in iterator {
                try Task.checkCancellation()
                if firstTokenDuration == 0 { firstTokenDuration = Date().timeIntervalSince(start) }
                if stopTokens.contains(token) { reason = "eog"; break }
                generated.append(token)
                text = context.tokenizer.decode(tokenIds: generated)
                // MLX does not apply llama.cpp's GBNF grammar. The harness still
                // validates every action and tool argument before dispatch.
                if text.last == "}", (try? ModelAction.parse(text)) != nil { reason = "complete"; break }
            }
            try Task.checkCancellation()
            Stream().synchronize()
            return Generation(text: text, promptTokens: tokens.count, generatedTokens: generated.count,
                              duration: Date().timeIntervalSince(start), stopReason: reason,
                              firstTokenDuration: firstTokenDuration)
        }
    }
}
