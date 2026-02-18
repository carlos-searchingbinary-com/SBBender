import Foundation

/// A model provider that tries multiple providers in order, falling back on failure.
///
/// Use this to create resilient agent configurations that gracefully handle
/// provider outages, rate limits, or network errors.
///
/// ```swift
/// let provider = FallbackProvider(providers: [
///     mlxProvider,       // Try local first
///     ollamaProvider,    // Fall back to Ollama
///     openaiProvider,    // Then cloud
/// ])
/// let agent = Agent(model: provider, ...)
/// ```
public struct FallbackProvider: ModelProvider, Sendable {
    public let providers: [any ModelProvider]
    public let maxRetries: Int
    public let retryDelay: TimeInterval

    public var id: String { "fallback" }

    public var displayName: String {
        let names = providers.map(\.displayName)
        return "Fallback(\(names.joined(separator: " → ")))"
    }

    public var modelID: String {
        providers.first?.modelID ?? "fallback"
    }

    public var isAvailable: Bool {
        get async {
            for provider in providers {
                if await provider.isAvailable { return true }
            }
            return false
        }
    }

    public var supportsToolCalling: Bool {
        providers.first?.supportsToolCalling ?? false
    }

    /// Create a fallback provider chain.
    ///
    /// - Parameters:
    ///   - providers: Ordered list of providers to try. First provider is primary.
    ///   - maxRetries: Number of retries per provider before moving to the next (default 1).
    ///   - retryDelay: Delay between retries in seconds (default 1.0).
    public init(
        providers: [any ModelProvider],
        maxRetries: Int = 1,
        retryDelay: TimeInterval = 1.0
    ) {
        precondition(!providers.isEmpty, "FallbackProvider requires at least one provider")
        self.providers = providers
        self.maxRetries = maxRetries
        self.retryDelay = retryDelay
    }

    public func generate(
        messages: [Message],
        config: GenerationConfig,
        tools: [ToolDefinition]
    ) async throws -> ModelResponse {
        var lastError: Error?

        for (index, provider) in providers.enumerated() {
            for attempt in 0...maxRetries {
                do {
                    let response = try await provider.generate(
                        messages: messages,
                        config: config,
                        tools: tools
                    )
                    if index > 0 {
                        Log.model.info("FallbackProvider: succeeded with provider \(index) (\(provider.displayName)) after primary failed")
                    }
                    return response
                } catch {
                    lastError = error
                    let isRetryable = isRetryableError(error)
                    Log.model.warning("FallbackProvider: provider \(index) (\(provider.displayName)) attempt \(attempt + 1) failed: \(error.localizedDescription) (retryable: \(isRetryable))")

                    if !isRetryable {
                        break // Don't retry non-retryable errors, move to next provider
                    }

                    if attempt < maxRetries {
                        try await Task.sleep(for: .seconds(retryDelay * Double(attempt + 1)))
                    }
                }
            }
        }

        let providerNames = providers.map(\.displayName)
        throw lastError ?? SBBenderError.allProvidersFailed(providerNames)
    }

    public func generateStream(
        messages: [Message],
        config: GenerationConfig,
        tools: [ToolDefinition]
    ) -> AsyncThrowingStream<StreamDelta, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var lastError: Error?

                for (index, provider) in providers.enumerated() {
                    for attempt in 0...maxRetries {
                        do {
                            let stream = provider.generateStream(
                                messages: messages,
                                config: config,
                                tools: tools
                            )
                            for try await delta in stream {
                                continuation.yield(delta)
                            }
                            if index > 0 {
                                Log.model.info("FallbackProvider: stream succeeded with provider \(index) (\(provider.displayName))")
                            }
                            continuation.finish()
                            return
                        } catch {
                            lastError = error
                            let isRetryable = isRetryableError(error)
                            Log.model.warning("FallbackProvider: stream provider \(index) attempt \(attempt + 1) failed: \(error.localizedDescription)")

                            if !isRetryable { break }

                            if attempt < maxRetries {
                                try? await Task.sleep(for: .seconds(retryDelay * Double(attempt + 1)))
                            }
                        }
                    }
                }

                let providerNames = providers.map(\.displayName)
                continuation.finish(throwing: lastError ?? SBBenderError.allProvidersFailed(providerNames))
            }
        }
    }

    // MARK: - Error Classification

    private func isRetryableError(_ error: Error) -> Bool {
        let description = error.localizedDescription.lowercased()

        // HTTP 429 (rate limit) — always retry
        if description.contains("429") || description.contains("rate limit") {
            return true
        }

        // HTTP 5xx (server errors) — retry
        if description.contains("500") || description.contains("502")
            || description.contains("503") || description.contains("504") {
            return true
        }

        // Network errors — retry
        if description.contains("timed out") || description.contains("connection")
            || description.contains("network") {
            return true
        }

        // Model loading errors (MLX) — don't retry, move to next provider
        if description.contains("model") && description.contains("load") {
            return false
        }

        // Default: don't retry unknown errors
        return false
    }
}
