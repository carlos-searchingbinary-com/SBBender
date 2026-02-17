import Foundation

/// Provider for OpenAI and OpenAI-compatible APIs (GPT-4, local servers, etc.).
public struct OpenAIProvider: ModelProvider, Sendable {
    public let id = "openai"
    public let displayName = "OpenAI"
    public let modelID: String
    private let apiKey: String
    private let baseURL: URL

    public init(
        modelID: String = "gpt-4o",
        apiKey: String,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!
    ) {
        self.modelID = modelID
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    public var isAvailable: Bool {
        get async { !apiKey.isEmpty }
    }

    public func generate(
        messages: [Message],
        config: GenerationConfig,
        tools: [ToolDefinition]
    ) async throws -> ModelResponse {
        let start = CFAbsoluteTimeGetCurrent()
        let url = baseURL.appendingPathComponent("chat/completions")

        let apiMessages: [[String: Any]] = messages.map { msg in
            var dict: [String: Any] = ["role": msg.role.rawValue, "content": msg.text]
            if let toolCallID = msg.toolCallID {
                dict["tool_call_id"] = toolCallID
            }
            if let name = msg.name {
                dict["name"] = name
            }
            return dict
        }

        var body: [String: Any] = [
            "model": modelID,
            "messages": apiMessages,
            "max_tokens": config.maxTokens,
            "temperature": Double(config.temperature),
            "top_p": Double(config.topP),
        ]

        if !tools.isEmpty {
            body["tools"] = tools.map { tool -> [String: Any] in
                [
                    "type": "function",
                    "function": [
                        "name": tool.name,
                        "description": tool.description,
                        "parameters": tool.parameters,
                    ] as [String: Any],
                ]
            }
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown"
            throw SBBenderError.generationFailed("OpenAI error: \(errorBody)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let choice = choices.first,
              let messageDict = choice["message"] as? [String: Any] else {
            throw SBBenderError.jsonParsingFailed("Failed to parse OpenAI response")
        }

        let text = messageDict["content"] as? String ?? ""
        var toolCalls: [ToolCall] = []

        if let tcs = messageDict["tool_calls"] as? [[String: Any]] {
            for tc in tcs {
                let tcID = tc["id"] as? String ?? UUID().uuidString
                if let function = tc["function"] as? [String: Any] {
                    let name = function["name"] as? String ?? ""
                    let args = function["arguments"] as? String ?? "{}"
                    toolCalls.append(ToolCall(id: tcID, name: name, arguments: args))
                }
            }
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let usage = json["usage"] as? [String: Any]
        let metrics = ModelMetrics(
            inputTokens: usage?["prompt_tokens"] as? Int ?? 0,
            outputTokens: usage?["completion_tokens"] as? Int ?? 0,
            totalTokens: usage?["total_tokens"] as? Int ?? 0,
            latency: elapsed,
            tokensPerSecond: elapsed > 0 ? Double(usage?["completion_tokens"] as? Int ?? 0) / elapsed : 0
        )

        let finishReason: FinishReason = toolCalls.isEmpty ? .stop : .toolCall

        let message = Message(
            role: .assistant,
            content: text.isEmpty ? [] : [.text(text)],
            toolCalls: toolCalls.isEmpty ? nil : toolCalls
        )

        return ModelResponse(
            message: message,
            metrics: metrics,
            finishReason: finishReason,
            rawOutput: text
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
                    let url = baseURL.appendingPathComponent("chat/completions")

                    let apiMessages: [[String: Any]] = messages.map { msg in
                        ["role": msg.role.rawValue, "content": msg.text]
                    }

                    var body: [String: Any] = [
                        "model": modelID,
                        "messages": apiMessages,
                        "max_tokens": config.maxTokens,
                        "temperature": Double(config.temperature),
                        "stream": true,
                    ]

                    if !tools.isEmpty {
                        body["tools"] = tools.map { tool -> [String: Any] in
                            [
                                "type": "function",
                                "function": [
                                    "name": tool.name,
                                    "description": tool.description,
                                    "parameters": tool.parameters,
                                ] as [String: Any],
                            ]
                        }
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    request.timeoutInterval = 120

                    let (bytes, _) = try await URLSession.shared.bytes(for: request)

                    var outputTokens = 0
                    // Accumulate tool calls from stream
                    var pendingToolCalls: [String: (name: String, args: String)] = [:]

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonStr = String(line.dropFirst(6))
                        guard jsonStr != "[DONE]",
                              let lineData = jsonStr.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                              let choices = event["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any] else { continue }

                        if let content = delta["content"] as? String, !content.isEmpty {
                            continuation.yield(.text(content))
                            outputTokens += 1
                        }

                        if let tcs = delta["tool_calls"] as? [[String: Any]] {
                            for tc in tcs {
                                let index = tc["index"] as? Int ?? 0
                                let key = "\(index)"
                                if let function = tc["function"] as? [String: Any] {
                                    var existing = pendingToolCalls[key] ?? (name: "", args: "")
                                    if let name = function["name"] as? String {
                                        existing.name = name
                                    }
                                    if let args = function["arguments"] as? String {
                                        existing.args += args
                                    }
                                    pendingToolCalls[key] = existing
                                }
                            }
                        }

                        if let finishReason = choices.first?["finish_reason"] as? String, finishReason == "tool_calls" {
                            for (_, tc) in pendingToolCalls {
                                continuation.yield(.toolCall(ToolCall(name: tc.name, arguments: tc.args)))
                            }
                        }
                    }

                    let elapsed = CFAbsoluteTimeGetCurrent() - start
                    let metrics = ModelMetrics(
                        outputTokens: outputTokens,
                        totalTokens: outputTokens,
                        latency: elapsed,
                        tokensPerSecond: elapsed > 0 ? Double(outputTokens) / elapsed : 0
                    )
                    continuation.yield(.done(metrics))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
