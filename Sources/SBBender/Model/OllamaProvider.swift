import Foundation

/// Provider for local models via Ollama HTTP API.
public struct OllamaProvider: ModelProvider, Sendable {
    public let id = "ollama"
    public let displayName = "Ollama"
    public let modelID: String
    public let baseURL: URL
    /// When false, disables thinking/reasoning for models that support it (e.g. Qwen3).
    public let think: Bool

    public init(modelID: String = "qwen3:4b", baseURL: URL = URL(string: "http://localhost:11434")!, think: Bool = true) {
        self.modelID = modelID
        self.baseURL = baseURL
        self.think = think
    }

    public var isAvailable: Bool {
        get async {
            let url = baseURL.appendingPathComponent("api/tags")
            var request = URLRequest(url: url)
            request.timeoutInterval = 3
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                return (response as? HTTPURLResponse)?.statusCode == 200
            } catch {
                return false
            }
        }
    }

    public func generate(
        messages: [Message],
        config: GenerationConfig,
        tools: [ToolDefinition]
    ) async throws -> ModelResponse {
        let start = CFAbsoluteTimeGetCurrent()
        let url = baseURL.appendingPathComponent("api/chat")

        let ollamaMessages = messages.map { msg -> [String: String] in
            ["role": msg.role.rawValue, "content": msg.text]
        }

        var body: [String: Any] = [
            "model": modelID,
            "messages": ollamaMessages,
            "stream": false,
            "options": [
                "temperature": config.temperature,
                "top_p": config.topP,
                "num_predict": config.maxTokens,
                "repeat_penalty": config.repetitionPenalty,
            ] as [String: Any],
        ]
        if !think { body["think"] = false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SBBenderError.generationFailed("Ollama returned non-200 status")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messageDict = json["message"] as? [String: Any],
              let content = messageDict["content"] as? String else {
            throw SBBenderError.jsonParsingFailed("Failed to parse Ollama response")
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - start

        var inputTokens = 0
        var outputTokens = 0
        if let promptEvalCount = json["prompt_eval_count"] as? Int {
            inputTokens = promptEvalCount
        }
        if let evalCount = json["eval_count"] as? Int {
            outputTokens = evalCount
        }

        let metrics = ModelMetrics(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            totalTokens: inputTokens + outputTokens,
            latency: elapsed,
            tokensPerSecond: elapsed > 0 ? Double(outputTokens) / elapsed : 0
        )

        return ModelResponse(
            message: .assistant(content),
            metrics: metrics,
            finishReason: .stop,
            rawOutput: content
        )
    }

    public func generateStream(
        messages: [Message],
        config: GenerationConfig,
        tools: [ToolDefinition]
    ) -> AsyncThrowingStream<StreamDelta, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let start = CFAbsoluteTimeGetCurrent()
                let url = baseURL.appendingPathComponent("api/chat")

                let ollamaMessages = messages.map { msg -> [String: String] in
                    ["role": msg.role.rawValue, "content": msg.text]
                }

                var body: [String: Any] = [
                    "model": modelID,
                    "messages": ollamaMessages,
                    "stream": true,
                    "options": [
                        "temperature": config.temperature,
                        "top_p": config.topP,
                        "num_predict": config.maxTokens,
                    ] as [String: Any],
                ]
                if !self.think { body["think"] = false }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                request.timeoutInterval = 120

                let (bytes, response) = try await URLSession.shared.bytes(for: request)

                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    throw SBBenderError.generationFailed("Ollama streaming returned non-200 status")
                }

                var totalTokens = 0

                for try await line in bytes.lines {
                    guard let lineData = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                        continue
                    }

                    if let messageDict = json["message"] as? [String: Any],
                       let content = messageDict["content"] as? String, !content.isEmpty {
                        continuation.yield(.text(content))
                        totalTokens += 1
                    }

                    if let done = json["done"] as? Bool, done {
                        let elapsed = CFAbsoluteTimeGetCurrent() - start
                        let metrics = ModelMetrics(
                            outputTokens: totalTokens,
                            totalTokens: totalTokens,
                            latency: elapsed,
                            tokensPerSecond: elapsed > 0 ? Double(totalTokens) / elapsed : 0
                        )
                        continuation.yield(.done(metrics))
                        break
                    }
                }

                continuation.finish()
            }
        }
    }
}
