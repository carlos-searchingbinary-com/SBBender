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
        if !tools.isEmpty { body["tools"] = encodeTools(tools) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError {
            throw mapURLError(urlError)
        }

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw mapHTTPError(statusCode: httpResponse.statusCode, data: data)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messageDict = json["message"] as? [String: Any] else {
            throw SBBenderError.jsonParsingFailed("Failed to parse Ollama response")
        }

        let content = messageDict["content"] as? String ?? ""
        let toolCalls = parseToolCalls(from: messageDict)

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

        let message = Message(
            role: .assistant,
            content: [.text(content)],
            toolCalls: toolCalls.isEmpty ? nil : toolCalls
        )

        return ModelResponse(
            message: message,
            metrics: metrics,
            finishReason: toolCalls.isEmpty ? .stop : .toolCall,
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
                do {
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
                            "repeat_penalty": config.repetitionPenalty,
                        ] as [String: Any],
                    ]
                    if !self.think { body["think"] = false }
                    if !tools.isEmpty { body["tools"] = encodeTools(tools) }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    request.timeoutInterval = 120

                    let bytes: URLSession.AsyncBytes
                    let response: URLResponse
                    do {
                        (bytes, response) = try await URLSession.shared.bytes(for: request)
                    } catch let urlError as URLError {
                        throw mapURLError(urlError)
                    }

                    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                        // Read body for error message
                        var bodyData = Data()
                        for try await byte in bytes {
                            bodyData.append(byte)
                            if bodyData.count > 4096 { break }
                        }
                        throw mapHTTPError(statusCode: httpResponse.statusCode, data: bodyData)
                    }

                    var totalTokens = 0

                    for try await line in bytes.lines {
                        guard let lineData = line.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                            continue
                        }

                        if let messageDict = json["message"] as? [String: Any] {
                            if let content = messageDict["content"] as? String, !content.isEmpty {
                                continuation.yield(.text(content))
                                totalTokens += 1
                            }

                            if let _ = messageDict["tool_calls"] as? [[String: Any]] {
                                let parsed = parseToolCalls(from: messageDict)
                                for tc in parsed {
                                    continuation.yield(.toolCall(tc))
                                }
                            }
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
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Error Mapping

    private func mapURLError(_ error: URLError) -> SBBenderError {
        switch error.code {
        case .cannotConnectToHost, .cannotFindHost:
            return .generationFailed("Ollama is not running at \(baseURL.absoluteString). Start it with 'ollama serve'")
        case .timedOut:
            return .generationFailed("Ollama request timed out. The model may be loading — try again in a moment")
        case .networkConnectionLost:
            return .generationFailed("Connection to Ollama lost. Check that 'ollama serve' is still running")
        default:
            return .generationFailed("Ollama connection error: \(error.localizedDescription)")
        }
    }

    private func mapHTTPError(statusCode: Int, data: Data) -> SBBenderError {
        let body = String(data: data, encoding: .utf8) ?? ""
        switch statusCode {
        case 404:
            return .generationFailed("Model '\(modelID)' not found in Ollama. Run 'ollama pull \(modelID)' first")
        case 500 where body.contains("not found"):
            return .generationFailed("Model '\(modelID)' not found in Ollama. Run 'ollama pull \(modelID)' first")
        default:
            let detail = body.isEmpty ? "" : ": \(body.prefix(200))"
            return .generationFailed("Ollama returned HTTP \(statusCode)\(detail)")
        }
    }

    // MARK: - Tool Encoding

    private func encodeTools(_ tools: [ToolDefinition]) -> [[String: Any]] {
        tools.map { tool -> [String: Any] in
            var function: [String: Any] = [
                "name": tool.name,
                "description": tool.description,
            ]
            if !tool.parameters.isEmpty {
                function["parameters"] = tool.parameters
            }
            return ["type": "function", "function": function]
        }
    }

    private func parseToolCalls(from messageDict: [String: Any]) -> [ToolCall] {
        guard let toolCallsArray = messageDict["tool_calls"] as? [[String: Any]] else {
            return []
        }
        return toolCallsArray.compactMap { tc -> ToolCall? in
            guard let function = tc["function"] as? [String: Any],
                  let name = function["name"] as? String else { return nil }
            let arguments = function["arguments"] as? [String: Any] ?? [:]
            let argsJSON: String
            if let data = try? JSONSerialization.data(withJSONObject: arguments),
               let str = String(data: data, encoding: .utf8) {
                argsJSON = str
            } else {
                argsJSON = "{}"
            }
            return ToolCall(
                id: UUID().uuidString,
                name: name,
                arguments: argsJSON
            )
        }
    }
}
