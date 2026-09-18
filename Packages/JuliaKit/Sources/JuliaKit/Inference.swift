import Foundation
import llama

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
    public let stopReason: String
    public init(text: String, promptTokens: Int = 0, generatedTokens: Int = 0, duration: Double = 0, stopReason: String = "complete") {
        self.text = text; self.promptTokens = promptTokens; self.generatedTokens = generatedTokens
        self.duration = duration; self.stopReason = stopReason
    }
}
public protocol ModelGenerating: Sendable {
    func tokenCount(messages: [ModelMessage]) async throws -> Int
    func generate(messages: [ModelMessage]) async throws -> Generation
}

/// The grammar constrains JSON syntax only. Tool names are unrestricted strings:
/// discovery is documentation, never a gate on which registered tool can execute.
public enum ActionGrammar {
    public static let source = #"""
    root ::= ws (call | answer) ws
    call ::= "{" ws "\"tool\"" ws ":" ws string ws "," ws "\"arguments\"" ws ":" ws object ws "}"
    answer ::= "{" ws "\"answer\"" ws ":" ws string ws "}"
    object ::= "{" ws (string ws ":" ws value (ws "," ws string ws ":" ws value)*)? ws "}"
    array ::= "[" ws (value (ws "," ws value)*)? ws "]"
    value ::= string | number | object | array | "true" | "false" | "null"
    string ::= "\"" char* "\""
    char ::= [^"\\\x00-\x1F] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F])
    number ::= "-"? ("0" | [1-9] [0-9]*) ("." [0-9]+)? ([eE] [+-]? [0-9]+)?
    ws ::= [ \t\n\r]?
    """#
}

public actor LlamaRuntime: ModelGenerating {
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocabulary: OpaquePointer?
    public static let contextSize = 32_768
    public static let maxOutputTokens = 768
    public static let maxPromptTokens = contextSize - maxOutputTokens - 256
    // LFM2.5-350M uses direct answers with JSON constrained from the first token.
    public static let thinkingEnabled = false
    public init() {}
    deinit {
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
    }
    public func load(url: URL) throws {
        if model != nil { return }
        llama_backend_init()
        var parameters = llama_model_default_params()
        parameters.n_gpu_layers = 99
        guard let loaded = llama_model_load_from_file(url.path, parameters) else { throw JuliaError("Could not load \(ModelStore.displayName). See the runtime log.") }
        var settings = llama_context_default_params()
        settings.n_ctx = UInt32(Self.contextSize)
        settings.n_batch = 512; settings.n_ubatch = 512
        settings.n_threads = Int32(min(8, max(2, ProcessInfo.processInfo.activeProcessorCount / 2)))
        settings.n_threads_batch = settings.n_threads
        guard let ctx = llama_init_from_model(loaded, settings) else {
            llama_model_free(loaded); throw JuliaError("Not enough memory to create the model context.")
        }
        model = loaded; context = ctx; vocabulary = llama_model_get_vocab(loaded)
    }
    public func tokenCount(messages: [ModelMessage]) throws -> Int { try tokenize(Self.prompt(messages)).count }

    /// LFM's text chat template includes BOS and a plain assistant generation prefix.
    /// Tool calls remain JSON content, as requested by the harness system prompt.
    public static func prompt(_ messages: [ModelMessage]) -> String {
        "<|startoftext|>" + messages.map {
            "<|im_start|>\($0.role)\n\(escapeSpecialTokens($0.content))<|im_end|>\n"
        }.joined() + "<|im_start|>assistant\n"
    }
    private static func escapeSpecialTokens(_ content: String) -> String {
        // App data and user content must not inject ChatML message boundaries.
        content.replacingOccurrences(of: "<|", with: "< |")
    }
    private func tokenize(_ text: String) throws -> [llama_token] {
        guard let vocabulary else { throw JuliaError("The model is not loaded yet.") }
        let bytes = text.utf8.count
        var tokens = [llama_token](repeating: 0, count: bytes + 16)
        let count = llama_tokenize(vocabulary, text, Int32(bytes), &tokens, Int32(tokens.count), false, true)
        guard count >= 0 else { throw JuliaError("Tokenization failed.") }
        return Array(tokens.prefix(Int(count)))
    }
    public func generate(messages: [ModelMessage]) throws -> Generation {
        guard let context, let vocabulary else { throw JuliaError("The model is not loaded yet.") }
        try Task.checkCancellation()
        let start = Date()
        var tokens = try tokenize(Self.prompt(messages))
        guard tokens.count + Self.maxOutputTokens < Self.contextSize else { throw JuliaError("The request exceeds the model context budget. Start a new command.") }
        if let memory = llama_get_memory(context) { llama_memory_clear(memory, true) }
        // Each generation replays explicit messages. Do not retain KV/recurrent
        // state after success, failure, or cancellation, including between commands.
        defer { if let memory = llama_get_memory(context) { llama_memory_clear(memory, true) } }
        for offset in stride(from: 0, to: tokens.count, by: 512) {
            try Task.checkCancellation()
            let n = min(512, tokens.count - offset)
            let status = tokens.withUnsafeMutableBufferPointer { ptr in
                llama_decode(context, llama_batch_get_one(ptr.baseAddress!.advanced(by: offset), Int32(n)))
            }
            guard status == 0 else { throw JuliaError("Model prompt evaluation failed (\(status)).") }
        }
        guard let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params()) else {
            throw JuliaError("Could not initialize constrained decoding.")
        }
        defer { llama_sampler_free(sampler) }
        guard let grammar = llama_sampler_init_grammar(vocabulary, ActionGrammar.source, "root") else {
            throw JuliaError("Could not initialize constrained decoding.")
        }
        llama_sampler_chain_add(sampler, grammar)
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy())
        var output = Data()
        var count = 0
        var reason = "length"
        for _ in 0..<Self.maxOutputTokens {
            try Task.checkCancellation()
            var token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocabulary, token) { reason = "eog"; break }
            var buffer = [CChar](repeating: 0, count: 512)
            var n = llama_token_to_piece(vocabulary, token, &buffer, Int32(buffer.count), 0, false)
            if n < 0 {
                buffer = [CChar](repeating: 0, count: Int(-n))
                n = llama_token_to_piece(vocabulary, token, &buffer, Int32(buffer.count), 0, false)
            }
            guard n >= 0 else { throw JuliaError("Could not decode generated token.") }
            output.append(contentsOf: buffer.prefix(Int(n)).map { UInt8(bitPattern: $0) })
            count += 1
            // A complete action is the natural stop. Avoid wasting tokens on trailing whitespace.
            if output.last == 0x7d, (try? JSONDecoder().decode(JSONValue.self, from: output)) != nil {
                reason = "complete"; break
            }
            let status = withUnsafeMutablePointer(to: &token) { llama_decode(context, llama_batch_get_one($0, 1)) }
            guard status == 0 else { throw JuliaError("Token evaluation failed (\(status)).") }
        }
        return Generation(text: String(decoding: output, as: UTF8.self), promptTokens: tokens.count,
                          generatedTokens: count, duration: Date().timeIntervalSince(start), stopReason: reason)
    }
}
