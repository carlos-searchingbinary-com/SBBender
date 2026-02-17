import Foundation
import os

#if canImport(FoundationModels)
import FoundationModels

/// Apple Intelligence provider using the FoundationModels framework.
///
/// Runs entirely on-device via Apple's built-in language model.
/// Requires macOS 26+ and Apple Silicon with Apple Intelligence enabled.
///
/// Does not support tool calling (FoundationModels doesn't expose it yet).
@available(macOS 26, *)
public final class FoundationProvider: @unchecked Sendable, ModelProvider {
    public let id = "foundation"
    public let displayName = "Apple Intelligence"
    public let modelID = "apple-intelligence"

    private let state = OSAllocatedUnfairLock(initialState: FoundationState())

    struct FoundationState: Sendable {
        var available: Bool?
    }

    public init() {}

    public var isAvailable: Bool {
        get async {
            if let cached = state.withLock({ $0.available }) {
                return cached
            }
            let model = SystemLanguageModel.default
            let available: Bool
            switch model.availability {
            case .available:
                available = true
            default:
                available = false
            }
            state.withLock { $0.available = available }
            return available
        }
    }

    public func generate(
        messages: [Message],
        config: GenerationConfig,
        tools: [ToolDefinition]
    ) async throws -> ModelResponse {
        guard await isAvailable else {
            throw SBBenderError.modelNotAvailable("Apple Intelligence is not available on this device")
        }

        let start = CFAbsoluteTimeGetCurrent()

        // Extract system prompt and user message
        let systemPrompt = messages.first(where: { $0.role == .system })?.text ?? ""
        let userMessage = messages.last(where: { $0.role == .user || $0.role == .assistant })?.text ?? ""

        let session: LanguageModelSession
        if systemPrompt.isEmpty {
            session = LanguageModelSession()
        } else {
            session = LanguageModelSession(instructions: systemPrompt)
        }

        let response = try await session.respond(to: userMessage)
        let output = response.content

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let tokenCount = output.split(separator: " ").count

        let metrics = ModelMetrics(
            outputTokens: tokenCount,
            totalTokens: tokenCount,
            latency: elapsed,
            tokensPerSecond: elapsed > 0 ? Double(tokenCount) / elapsed : 0
        )

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
#endif
