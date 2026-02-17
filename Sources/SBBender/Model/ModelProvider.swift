import Foundation

/// Metrics collected from a single model invocation.
public struct ModelMetrics: Sendable, Codable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var totalTokens: Int
    public var latency: TimeInterval
    public var tokensPerSecond: Double

    public init(
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        totalTokens: Int = 0,
        latency: TimeInterval = 0,
        tokensPerSecond: Double = 0
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.latency = latency
        self.tokensPerSecond = tokensPerSecond
    }
}

/// The response returned by a single model invocation.
public struct ModelResponse: Sendable {
    public var message: Message
    public var metrics: ModelMetrics
    public var finishReason: FinishReason
    public var rawOutput: String?

    public init(
        message: Message,
        metrics: ModelMetrics = ModelMetrics(),
        finishReason: FinishReason = .stop,
        rawOutput: String? = nil
    ) {
        self.message = message
        self.metrics = metrics
        self.finishReason = finishReason
        self.rawOutput = rawOutput
    }
}

/// Why the model stopped generating.
public enum FinishReason: String, Sendable, Codable {
    case stop
    case toolCall = "tool_calls"
    case length
    case contentFilter = "content_filter"
    case error
}

/// Configuration for model generation.
public struct GenerationConfig: Sendable {
    public var maxTokens: Int
    public var temperature: Float
    public var topP: Float
    public var repetitionPenalty: Float
    public var enableThinking: Bool

    public init(
        maxTokens: Int = 2048,
        temperature: Float = 0.7,
        topP: Float = 0.9,
        repetitionPenalty: Float = 1.0,
        enableThinking: Bool = false
    ) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.repetitionPenalty = repetitionPenalty
        self.enableThinking = enableThinking
    }
}

/// A tool definition formatted for the model API.
///
/// Uses `@unchecked Sendable` because `parameters` contains JSON-serializable
/// values that are effectively immutable after construction.
public struct ToolDefinition: @unchecked Sendable {
    public let name: String
    public let description: String
    public let parameters: [String: Any]

    public init(name: String, description: String, parameters: [String: Any]) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

/// Unified protocol for all LLM providers.
///
/// Implementations must be `Sendable` and safe to call from any isolation context.
/// The provider handles a single model invocation; the Agent handles the run loop.
public protocol ModelProvider: Sendable {
    /// Unique identifier for this provider (e.g. "mlx", "anthropic").
    var id: String { get }

    /// Human-readable display name.
    var displayName: String { get }

    /// The model identifier (e.g. "mlx-community/Qwen3-4B-4bit").
    var modelID: String { get }

    /// Whether this provider is currently available and ready to generate.
    var isAvailable: Bool { get async }

    /// Generate a complete response from a list of messages.
    func generate(
        messages: [Message],
        config: GenerationConfig,
        tools: [ToolDefinition]
    ) async throws -> ModelResponse

    /// Stream a response token-by-token.
    func generateStream(
        messages: [Message],
        config: GenerationConfig,
        tools: [ToolDefinition]
    ) -> AsyncThrowingStream<StreamDelta, Error>
}

/// A delta chunk from a streaming response.
public enum StreamDelta: Sendable {
    /// A text fragment.
    case text(String)
    /// A complete tool call (accumulated from chunks).
    case toolCall(ToolCall)
    /// The stream has finished.
    case done(ModelMetrics)
}

// MARK: - Default implementations

extension ModelProvider {
    public func generateStream(
        messages: [Message],
        config: GenerationConfig,
        tools: [ToolDefinition]
    ) -> AsyncThrowingStream<StreamDelta, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let response = try await self.generate(messages: messages, config: config, tools: tools)
                    continuation.yield(.text(response.message.text))
                    continuation.yield(.done(response.metrics))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
