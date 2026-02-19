import Foundation
@testable import SBBenderCore

/// A deterministic mock model provider for testing.
actor MockProvider: ModelProvider {
    nonisolated let id = "mock"
    nonisolated let displayName = "Mock"
    nonisolated let modelID = "mock-model"

    nonisolated var isAvailable: Bool { get async { true } }

    private var responses: [String]
    private var responseIndex: Int = 0
    private var toolCallResponses: [([ToolCall], String)]
    private let shouldFail: Bool
    private(set) var generateCallCount: Int = 0

    init(
        responses: [String] = ["Hello, I'm a mock assistant."],
        toolCallResponses: [([ToolCall], String)] = [],
        shouldFail: Bool = false
    ) {
        self.responses = responses
        self.toolCallResponses = toolCallResponses
        self.shouldFail = shouldFail
    }

    func generate(
        messages: [Message],
        config: GenerationConfig,
        tools: [ToolDefinition]
    ) async throws -> ModelResponse {
        generateCallCount += 1

        if shouldFail {
            throw SBBenderError.generationFailed("Mock failure")
        }

        // Check if we should return tool calls
        if !toolCallResponses.isEmpty {
            let (toolCalls, _) = toolCallResponses.removeFirst()
            let message = Message(role: .assistant, content: [], toolCalls: toolCalls)
            return ModelResponse(
                message: message,
                metrics: ModelMetrics(inputTokens: 10, outputTokens: 5, totalTokens: 15, latency: 0.01),
                finishReason: .toolCall
            )
        }

        guard !responses.isEmpty else {
            return ModelResponse(
                message: .assistant(""),
                metrics: ModelMetrics(inputTokens: 10, outputTokens: 5, totalTokens: 15, latency: 0.01),
                finishReason: .stop
            )
        }
        let idx = min(responseIndex, responses.count - 1)
        responseIndex += 1
        let text = responses[idx]
        return ModelResponse(
            message: .assistant(text),
            metrics: ModelMetrics(inputTokens: 10, outputTokens: 5, totalTokens: 15, latency: 0.01),
            finishReason: .stop
        )
    }
}
