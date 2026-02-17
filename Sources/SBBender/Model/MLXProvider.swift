import Foundation
import os
import MLX
import MLXRandom
@preconcurrency import MLXLLM
@preconcurrency import MLXLMCommon

/// Local LLM inference via MLX Swift on Apple Silicon.
///
/// This is the primary provider for SBBender. It runs Qwen3, Llama, and other
/// models entirely on-device using the GPU.
///
/// Uses `@unchecked Sendable` because `ModelContainer` manages its own
/// thread safety internally.
public final class MLXProvider: @unchecked Sendable, ModelProvider {
    public let id = "mlx"
    public let displayName = "MLX Local"
    public let modelID: String

    private let gpuCacheLimit: Int
    private let toolCallFormat: any ToolCallFormat
    private let state = OSAllocatedUnfairLock(initialState: MLXState())

    struct MLXState: Sendable {
        var container: ModelContainer?
        var loadTask: Task<ModelContainer, Error>?
    }

    public init(
        modelID: String = "mlx-community/Qwen3-4B-4bit",
        gpuCacheLimit: Int = 20 * 1024 * 1024,
        toolCallFormat: any ToolCallFormat = Qwen3ToolFormat()
    ) {
        self.modelID = modelID
        self.gpuCacheLimit = gpuCacheLimit
        self.toolCallFormat = toolCallFormat
    }

    public var isAvailable: Bool {
        get async {
            state.withLock { $0.container != nil || $0.loadTask != nil }
        }
    }

    /// Load the model if not already loaded.
    public func loadModel() async throws -> ModelContainer {
        enum LoadState {
            case loaded(ModelContainer)
            case loading(Task<ModelContainer, Error>)
            case needsLoad
        }

        let loadState: LoadState = state.withLock { s in
            if let container = s.container {
                return .loaded(container)
            }
            if let task = s.loadTask {
                return .loading(task)
            }
            return .needsLoad
        }

        switch loadState {
        case .loaded(let container):
            return container
        case .loading(let task):
            return try await task.value
        case .needsLoad:
            break
        }

        let mid = modelID
        let cacheLimit = gpuCacheLimit

        let task = Task<ModelContainer, Error> {
            Log.model.info("Loading MLX model: \(mid)")
            MLX.Memory.cacheLimit = cacheLimit

            let config = ModelConfiguration(id: mid)

            let container = try await LLMModelFactory.shared.loadContainer(
                configuration: config
            )
            Log.model.info("MLX model loaded: \(mid)")
            return container
        }

        state.withLock { $0.loadTask = task }

        let result = try await task.value

        state.withLock { s in
            s.container = result
            s.loadTask = nil
        }

        return result
    }

    public func generate(
        messages: [Message],
        config: GenerationConfig,
        tools: [ToolDefinition]
    ) async throws -> ModelResponse {
        let container = try await loadModel()
        let start = CFAbsoluteTimeGetCurrent()

        let promptString = buildPrompt(from: messages, tools: tools)
        let maxTokens = config.maxTokens
        let enableThinking = config.enableThinking

        let userInput: UserInput = {
            var input = UserInput(prompt: promptString)
            input.processing.resize = .none
            if !enableThinking {
                input.additionalContext = ["enable_thinking": false]
            }
            return input
        }()

        let lmInput = try await container.perform { ctx in
            try await ctx.processor.prepare(input: userInput)
        }

        let generateConfig = GenerateParameters(
            temperature: config.temperature,
            topP: config.topP,
            repetitionPenalty: config.repetitionPenalty
        )

        let generationResult = try await container.perform { ctx in
            try MLXLMCommon.generate(
                input: lmInput,
                parameters: generateConfig,
                context: ctx
            ) { tokens in
                tokens.count >= maxTokens ? .stop : .more
            }
        }

        var output = generationResult.output
        if !enableThinking {
            output = Self.stripThinkingTags(output)
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let tokenCount = output.split(separator: " ").count
        let metrics = ModelMetrics(
            outputTokens: tokenCount,
            totalTokens: tokenCount,
            latency: elapsed,
            tokensPerSecond: elapsed > 0 ? Double(tokenCount) / elapsed : 0
        )

        // Parse tool calls from output using the configured format
        let (parsedToolCalls, remainingText) = toolCallFormat.parseToolCalls(output)

        if !parsedToolCalls.isEmpty {
            let content: [Content] = remainingText.isEmpty ? [] : [.text(remainingText)]
            let message = Message(
                role: .assistant,
                content: content,
                toolCalls: parsedToolCalls
            )
            return ModelResponse(
                message: message,
                metrics: metrics,
                finishReason: .toolCall,
                rawOutput: output
            )
        }

        return ModelResponse(
            message: .assistant(output),
            metrics: metrics,
            finishReason: .stop,
            rawOutput: output
        )
    }

    public func generateStream(
        messages: [Message],
        config: GenerationConfig,
        tools: [ToolDefinition]
    ) -> AsyncThrowingStream<StreamDelta, Error> {
        AsyncThrowingStream { continuation in
            Task { [self] in
                do {
                    let container = try await self.loadModel()
                    let start = CFAbsoluteTimeGetCurrent()

                    let promptString = self.buildPrompt(from: messages, tools: tools)
                    let maxTokens = config.maxTokens
                    let enableThinking = config.enableThinking
                    let format = self.toolCallFormat
                    let hasTools = !tools.isEmpty

                    let userInput: UserInput = {
                        var input = UserInput(prompt: promptString)
                        input.processing.resize = .none
                        if !enableThinking {
                            input.additionalContext = ["enable_thinking": false]
                        }
                        return input
                    }()

                    let lmInput = try await container.perform { ctx in
                        try await ctx.processor.prepare(input: userInput)
                    }

                    let generateConfig = GenerateParameters(
                        temperature: config.temperature,
                        topP: config.topP,
                        repetitionPenalty: config.repetitionPenalty
                    )

                    let generationResult = try await container.perform { ctx in
                        try MLXLMCommon.generate(
                            input: lmInput,
                            parameters: generateConfig,
                            context: ctx
                        ) { tokens in
                            if let last = tokens.last {
                                let text = ctx.tokenizer.decode(tokens: [last])
                                if !text.isEmpty {
                                    continuation.yield(.text(text))
                                }
                            }
                            return tokens.count >= maxTokens ? .stop : .more
                        }
                    }

                    let fullOutput = generationResult.output

                    // After generation completes, check for tool calls if tools were provided
                    if hasTools {
                        var processedOutput = fullOutput
                        if !enableThinking {
                            processedOutput = Self.stripThinkingTags(processedOutput)
                        }

                        let (parsedToolCalls, _) = format.parseToolCalls(processedOutput)
                        for tc in parsedToolCalls {
                            continuation.yield(.toolCall(tc))
                        }
                    }

                    let elapsed = CFAbsoluteTimeGetCurrent() - start
                    let tokenCount = fullOutput.split(separator: " ").count
                    let metrics = ModelMetrics(
                        outputTokens: tokenCount,
                        totalTokens: tokenCount,
                        latency: elapsed,
                        tokensPerSecond: elapsed > 0 ? Double(tokenCount) / elapsed : 0
                    )
                    continuation.yield(.done(metrics))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Prompt Building

    /// Build a ChatML prompt string from messages, optionally including tool definitions.
    func buildPrompt(from messages: [Message], tools: [ToolDefinition] = []) -> String {
        let format = toolCallFormat
        return messages.map { msg in
            switch msg.role {
            case .system:
                let systemText: String
                if tools.isEmpty {
                    systemText = msg.text
                } else {
                    systemText = msg.text + "\n\n" + format.formatToolPrompt(tools: tools)
                }
                return "<|im_start|>system\n\(systemText)<|im_end|>"
            case .user:
                return "<|im_start|>user\n\(msg.text)<|im_end|>"
            case .assistant:
                if let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                    var parts: [String] = []
                    let text = msg.text
                    if !text.isEmpty {
                        parts.append(text)
                    }
                    for tc in toolCalls {
                        parts.append("<tool_call>\n{\"name\": \"\(tc.name)\", \"arguments\": \(tc.arguments)}\n</tool_call>")
                    }
                    return "<|im_start|>assistant\n\(parts.joined(separator: "\n"))<|im_end|>"
                }
                return "<|im_start|>assistant\n\(msg.text)<|im_end|>"
            case .tool:
                guard let toolName = msg.name else {
                    Log.model.error("Tool message missing name field, using 'unknown'")
                    return "<|im_start|>user\n\(format.formatToolResult(name: "unknown", result: msg.text))<|im_end|>"
                }
                let result = msg.text
                return "<|im_start|>user\n\(format.formatToolResult(name: toolName, result: result))<|im_end|>"
            }
        }.joined(separator: "\n") + "\n<|im_start|>assistant\n"
    }

    // MARK: - Static Helpers (backward compatibility)

    /// Build a ChatML prompt string from messages. Delegates to Qwen3ToolFormat.
    static func buildPrompt(from messages: [Message], tools: [ToolDefinition] = []) -> String {
        let format = Qwen3ToolFormat()
        return messages.map { msg in
            switch msg.role {
            case .system:
                let systemText: String
                if tools.isEmpty {
                    systemText = msg.text
                } else {
                    systemText = msg.text + "\n\n" + format.formatToolPrompt(tools: tools)
                }
                return "<|im_start|>system\n\(systemText)<|im_end|>"
            case .user:
                return "<|im_start|>user\n\(msg.text)<|im_end|>"
            case .assistant:
                if let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                    var parts: [String] = []
                    let text = msg.text
                    if !text.isEmpty {
                        parts.append(text)
                    }
                    for tc in toolCalls {
                        parts.append("<tool_call>\n{\"name\": \"\(tc.name)\", \"arguments\": \(tc.arguments)}\n</tool_call>")
                    }
                    return "<|im_start|>assistant\n\(parts.joined(separator: "\n"))<|im_end|>"
                }
                return "<|im_start|>assistant\n\(msg.text)<|im_end|>"
            case .tool:
                guard let toolName = msg.name else {
                    Log.model.error("Tool message missing name field, using 'unknown'")
                    return "<|im_start|>user\n\(format.formatToolResult(name: "unknown", result: msg.text))<|im_end|>"
                }
                let result = msg.text
                return "<|im_start|>user\n\(format.formatToolResult(name: toolName, result: result))<|im_end|>"
            }
        }.joined(separator: "\n") + "\n<|im_start|>assistant\n"
    }

    /// Build the tool prompt block. Delegates to Qwen3ToolFormat.
    static func buildToolPrompt(tools: [ToolDefinition]) -> String {
        Qwen3ToolFormat().formatToolPrompt(tools: tools)
    }

    /// Parse `<tool_call>` blocks from model output. Delegates to Qwen3ToolFormat.
    static func parseToolCalls(_ text: String) -> ([ToolCall], String) {
        Qwen3ToolFormat().parseToolCalls(text)
    }

    static func stripThinkingTags(_ text: String) -> String {
        guard let thinkEnd = text.range(of: "</think>") else {
            if text.hasPrefix("<think>") {
                return ""
            }
            return text
        }
        return String(text[thinkEnd.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Escape a string for JSON embedding.
    static func escapeJSON(_ string: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: [string], options: []),
           let jsonArray = String(data: data, encoding: .utf8) {
            let trimmed = jsonArray.dropFirst(1).dropLast(1)
            return String(trimmed)
        }
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }
}
