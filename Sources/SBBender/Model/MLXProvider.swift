import Foundation
import os
import MLX
import MLXRandom
@preconcurrency import MLXLLM
@preconcurrency import MLXLMCommon
import SBBenderCore

/// Local LLM inference via MLX Swift on Apple Silicon.
///
/// Uses mlx-swift-lm's native chat template and tool calling system:
/// - `UserInput(chat:tools:)` for proper multi-turn with tool results
/// - `ModelContainer.generate()` async stream with native `Generation.toolCall` detection
/// - Auto-detected tool call format based on model type (Qwen3, Llama, GLM4, etc.)
///
/// Uses `@unchecked Sendable` because `ModelContainer` manages its own
/// thread safety internally.
public final class MLXProvider: @unchecked Sendable, ModelProvider {
    public let id = "mlx"
    public let displayName = "MLX Local"
    public let modelID: String

    private let gpuCacheLimit: Int
    private let state = OSAllocatedUnfairLock(initialState: MLXState())

    struct MLXState: Sendable {
        var container: ModelContainer?
        var loadTask: Task<ModelContainer, Error>?
    }

    public init(
        modelID: String = "mlx-community/Qwen3-4B-4bit",
        gpuCacheLimit: Int = 20 * 1024 * 1024,
        toolCallFormat: (any SBToolCallFormat)? = nil // Ignored — native detection used
    ) {
        self.modelID = modelID
        self.gpuCacheLimit = gpuCacheLimit
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

    // MARK: - Generate (non-streaming)

    public func generate(
        messages: [SBMessage],
        config: GenerationConfig,
        tools: [ToolDefinition]
    ) async throws -> ModelResponse {
        let container = try await loadModel()
        let start = CFAbsoluteTimeGetCurrent()

        let chatMessages = messages.map { Self.toChatMessage($0) }
        let toolSchemas: [[String: any Sendable]]? = tools.isEmpty ? nil : tools.map { Self.toToolSchema($0) }

        var userInput = UserInput(chat: chatMessages, tools: toolSchemas)
        userInput.processing.resize = .none
        if !config.enableThinking {
            userInput.additionalContext = ["enable_thinking": false]
        }

        let lmInput = try await container.prepare(input: userInput)

        let generateConfig = GenerateParameters(
            maxTokens: config.maxTokens,
            temperature: config.temperature,
            topP: config.topP,
            repetitionPenalty: config.repetitionPenalty
        )

        let stream = try await container.generate(
            input: lmInput,
            parameters: generateConfig
        )

        var text = ""
        var nativeToolCalls: [MLXLMCommon.ToolCall] = []
        var completionInfo: GenerateCompletionInfo?

        for try await generation in stream {
            if let chunk = generation.chunk {
                text += chunk
            }
            if let tc = generation.toolCall {
                nativeToolCalls.append(tc)
            }
            if let info = generation.info {
                completionInfo = info
            }
        }

        // Strip thinking tags if thinking is disabled
        if !config.enableThinking {
            text = Self.stripThinkingTags(text)
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let metrics = Self.buildMetrics(from: completionInfo, elapsed: elapsed, fallbackText: text)

        // Convert native tool calls to SBBender tool calls
        if !nativeToolCalls.isEmpty {
            let sbToolCalls = nativeToolCalls.map { Self.toSBBenderToolCall($0) }
            Log.tool.info("MLX native tool calls detected: \(sbToolCalls.map(\.name))")

            let content: [SBBenderCore.Content] = text.isEmpty ? [] : [.text(text)]
            let message = SBMessage(
                role: .assistant,
                content: content,
                toolCalls: sbToolCalls
            )
            return ModelResponse(
                message: message,
                metrics: metrics,
                finishReason: .toolCall,
                rawOutput: text
            )
        }

        return ModelResponse(
            message: .assistant(text),
            metrics: metrics,
            finishReason: .stop,
            rawOutput: text
        )
    }

    // MARK: - Generate (streaming)

    public func generateStream(
        messages: [SBMessage],
        config: GenerationConfig,
        tools: [ToolDefinition]
    ) -> AsyncThrowingStream<StreamDelta, Error> {
        AsyncThrowingStream { continuation in
            Task { [self] in
                do {
                    let container = try await self.loadModel()
                    let start = CFAbsoluteTimeGetCurrent()

                    let chatMessages = messages.map { Self.toChatMessage($0) }
                    let toolSchemas: [[String: any Sendable]]? = tools.isEmpty ? nil : tools.map { Self.toToolSchema($0) }

                    var userInput = UserInput(chat: chatMessages, tools: toolSchemas)
                    userInput.processing.resize = .none
                    if !config.enableThinking {
                        userInput.additionalContext = ["enable_thinking": false]
                    }

                    let lmInput = try await container.prepare(input: userInput)

                    let generateConfig = GenerateParameters(
                        maxTokens: config.maxTokens,
                        temperature: config.temperature,
                        topP: config.topP,
                        repetitionPenalty: config.repetitionPenalty
                    )

                    let stream = try await container.generate(
                        input: lmInput,
                        parameters: generateConfig
                    )

                    var completionInfo: GenerateCompletionInfo?

                    for try await generation in stream {
                        if let chunk = generation.chunk {
                            continuation.yield(.text(chunk))
                        }
                        if let tc = generation.toolCall {
                            let sbToolCall = Self.toSBBenderToolCall(tc)
                            Log.tool.info("MLX stream tool call: \(sbToolCall.name)")
                            continuation.yield(.toolCall(sbToolCall))
                        }
                        if let info = generation.info {
                            completionInfo = info
                        }
                    }

                    let elapsed = CFAbsoluteTimeGetCurrent() - start
                    let metrics = Self.buildMetrics(from: completionInfo, elapsed: elapsed, fallbackText: "")
                    continuation.yield(.done(metrics))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Type Conversions

    /// Convert SBBender Message → mlx-swift-lm Chat.Message
    static func toChatMessage(_ message: SBMessage) -> Chat.Message {
        switch message.role {
        case .system:
            return .system(message.text)
        case .user:
            return .user(message.text)
        case .assistant:
            // Include tool call info in assistant text if present
            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                var parts: [String] = []
                let text = message.text
                if !text.isEmpty {
                    parts.append(text)
                }
                // The model's chat template will format these properly
                for tc in toolCalls {
                    parts.append("<tool_call>\n{\"name\": \"\(tc.name)\", \"arguments\": \(tc.arguments)}\n</tool_call>")
                }
                return .assistant(parts.joined(separator: "\n"))
            }
            return .assistant(message.text)
        case .tool:
            let toolName = message.name ?? "unknown"
            let result = message.text
            // Format as JSON tool response for the model
            let escaped = escapeJSONString(result)
            return .tool("{\"name\": \"\(toolName)\", \"content\": \(escaped)}")
        }
    }

    /// Convert SBBender ToolDefinition → mlx-swift-lm tool schema
    static func toToolSchema(_ def: ToolDefinition) -> [String: any Sendable] {
        let funcDict: [String: any Sendable] = [
            "name": def.name,
            "description": def.description,
            "parameters": toSendableDict(def.parameters),
        ]
        return [
            "type": "function" as any Sendable,
            "function": funcDict as any Sendable,
        ]
    }

    /// Convert mlx-swift-lm ToolCall → SBBender ToolCall
    static func toSBBenderToolCall(_ tc: MLXLMCommon.ToolCall) -> SBBenderCore.ToolCall {
        // Convert JSONValue arguments to JSON string
        let argsDict = tc.function.arguments.mapValues { $0.anyValue }
        let argsString: String
        if let data = try? JSONSerialization.data(withJSONObject: argsDict, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            argsString = json
        } else {
            argsString = "{}"
        }
        return SBBenderCore.ToolCall(name: tc.function.name, arguments: argsString)
    }

    /// Recursively convert [String: Any] to [String: any Sendable] for tool schemas.
    private static func toSendableDict(_ dict: [String: Any]) -> [String: any Sendable] {
        var result: [String: any Sendable] = [:]
        for (key, value) in dict {
            switch value {
            case let s as String:
                result[key] = s
            case let i as Int:
                result[key] = i
            case let d as Double:
                result[key] = d
            case let b as Bool:
                result[key] = b
            case let arr as [Any]:
                result[key] = toSendableArray(arr)
            case let nested as [String: Any]:
                result[key] = toSendableDict(nested)
            default:
                result[key] = "\(value)"
            }
        }
        return result
    }

    private static func toSendableArray(_ arr: [Any]) -> [any Sendable] {
        arr.map { value in
            switch value {
            case let s as String: return s as any Sendable
            case let i as Int: return i as any Sendable
            case let d as Double: return d as any Sendable
            case let b as Bool: return b as any Sendable
            case let nested as [String: Any]: return toSendableDict(nested) as any Sendable
            case let nestedArr as [Any]: return toSendableArray(nestedArr) as any Sendable
            default: return "\(value)" as any Sendable
            }
        }
    }

    // MARK: - Helpers

    private static func buildMetrics(
        from info: GenerateCompletionInfo?,
        elapsed: TimeInterval,
        fallbackText: String
    ) -> ModelMetrics {
        if let info {
            return ModelMetrics(
                inputTokens: info.promptTokenCount,
                outputTokens: info.generationTokenCount,
                totalTokens: info.promptTokenCount + info.generationTokenCount,
                latency: elapsed,
                tokensPerSecond: info.tokensPerSecond
            )
        }
        // Fallback: estimate from text
        let tokenCount = fallbackText.split(separator: " ").count
        return ModelMetrics(
            outputTokens: tokenCount,
            totalTokens: tokenCount,
            latency: elapsed,
            tokensPerSecond: elapsed > 0 ? Double(tokenCount) / elapsed : 0
        )
    }

    private static func escapeJSONString(_ string: String) -> String {
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

    // MARK: - Static Helpers (backward compatibility for tests)

    /// Build a ChatML prompt string from messages. Delegates to Qwen3ToolFormat.
    static func buildPrompt(from messages: [SBMessage], tools: [ToolDefinition] = []) -> String {
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
    static func parseToolCalls(_ text: String) -> ([SBBenderCore.ToolCall], String) {
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
        escapeJSONString(string)
    }
}
