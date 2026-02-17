import Foundation

/// Provider for Claude models via the Anthropic Messages API.
public struct AnthropicProvider: ModelProvider, Sendable {
    public let id = "anthropic"
    public let displayName = "Anthropic"
    public let modelID: String
    private let apiKey: String
    private let baseURL: URL
    private let apiVersion: String

    public init(
        modelID: String = "claude-sonnet-4-5-20250929",
        apiKey: String,
        baseURL: URL = URL(string: "https://api.anthropic.com")!,
        apiVersion: String = "2023-06-01"
    ) {
        self.modelID = modelID
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.apiVersion = apiVersion
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
        let url = baseURL.appendingPathComponent("v1/messages")

        let (systemPrompt, apiMessages) = buildAPIMessages(from: messages)

        var body: [String: Any] = [
            "model": modelID,
            "max_tokens": config.maxTokens,
            "temperature": Double(config.temperature),
            "messages": apiMessages,
        ]

        if let system = systemPrompt {
            body["system"] = system
        }

        if !tools.isEmpty {
            body["tools"] = tools.map { tool -> [String: Any] in
                [
                    "name": tool.name,
                    "description": tool.description,
                    "input_schema": tool.parameters,
                ]
            }
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SBBenderError.generationFailed("Invalid response from Anthropic")
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SBBenderError.generationFailed("Anthropic \(httpResponse.statusCode): \(errorBody)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SBBenderError.jsonParsingFailed("Failed to parse Anthropic response")
        }

        let (text, toolCalls) = parseResponse(json)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        let usage = json["usage"] as? [String: Any]
        let metrics = ModelMetrics(
            inputTokens: usage?["input_tokens"] as? Int ?? 0,
            outputTokens: usage?["output_tokens"] as? Int ?? 0,
            totalTokens: (usage?["input_tokens"] as? Int ?? 0) + (usage?["output_tokens"] as? Int ?? 0),
            latency: elapsed,
            tokensPerSecond: elapsed > 0 ? Double(usage?["output_tokens"] as? Int ?? 0) / elapsed : 0
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

    // MARK: - Streaming

    public func generateStream(
        messages: [Message],
        config: GenerationConfig,
        tools: [ToolDefinition]
    ) -> AsyncThrowingStream<StreamDelta, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let start = CFAbsoluteTimeGetCurrent()
                    let url = baseURL.appendingPathComponent("v1/messages")

                    let (systemPrompt, apiMessages) = buildAPIMessages(from: messages)

                    var body: [String: Any] = [
                        "model": modelID,
                        "max_tokens": config.maxTokens,
                        "temperature": Double(config.temperature),
                        "messages": apiMessages,
                        "stream": true,
                    ]

                    if let system = systemPrompt {
                        body["system"] = system
                    }

                    if !tools.isEmpty {
                        body["tools"] = tools.map { tool -> [String: Any] in
                            [
                                "name": tool.name,
                                "description": tool.description,
                                "input_schema": tool.parameters,
                            ]
                        }
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.addValue(apiVersion, forHTTPHeaderField: "anthropic-version")
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    request.timeoutInterval = 120

                    let (bytes, _) = try await URLSession.shared.bytes(for: request)

                    var inputTokens = 0
                    var outputTokens = 0
                    var currentToolName = ""
                    var currentToolID = ""
                    var currentToolArgs = ""

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonStr = String(line.dropFirst(6))
                        guard jsonStr != "[DONE]",
                              let lineData = jsonStr.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                              let type = event["type"] as? String else { continue }

                        switch type {
                        case "content_block_start":
                            if let contentBlock = event["content_block"] as? [String: Any],
                               contentBlock["type"] as? String == "tool_use" {
                                currentToolName = contentBlock["name"] as? String ?? ""
                                currentToolID = contentBlock["id"] as? String ?? UUID().uuidString
                                currentToolArgs = ""
                            }

                        case "content_block_delta":
                            if let delta = event["delta"] as? [String: Any] {
                                if delta["type"] as? String == "text_delta",
                                   let text = delta["text"] as? String {
                                    continuation.yield(.text(text))
                                } else if delta["type"] as? String == "input_json_delta",
                                          let partial = delta["partial_json"] as? String {
                                    currentToolArgs += partial
                                }
                            }

                        case "content_block_stop":
                            if !currentToolName.isEmpty {
                                let tc = ToolCall(id: currentToolID, name: currentToolName, arguments: currentToolArgs)
                                continuation.yield(.toolCall(tc))
                                currentToolName = ""
                                currentToolArgs = ""
                            }

                        case "message_delta":
                            if let usage = event["usage"] as? [String: Any] {
                                outputTokens = usage["output_tokens"] as? Int ?? outputTokens
                            }

                        case "message_start":
                            if let message = event["message"] as? [String: Any],
                               let usage = message["usage"] as? [String: Any] {
                                inputTokens = usage["input_tokens"] as? Int ?? 0
                            }

                        default:
                            break
                        }
                    }

                    let elapsed = CFAbsoluteTimeGetCurrent() - start
                    let metrics = ModelMetrics(
                        inputTokens: inputTokens,
                        outputTokens: outputTokens,
                        totalTokens: inputTokens + outputTokens,
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

    // MARK: - Helpers

    private func buildAPIMessages(from messages: [Message]) -> (String?, [[String: Any]]) {
        var systemPrompt: String?
        var apiMessages: [[String: Any]] = []

        for msg in messages {
            if msg.role == .system {
                systemPrompt = msg.text
                continue
            }

            if msg.role == .tool {
                apiMessages.append([
                    "role": "user",
                    "content": [
                        [
                            "type": "tool_result",
                            "tool_use_id": msg.toolCallID ?? "",
                            "content": msg.text,
                        ] as [String: Any]
                    ] as [[String: Any]],
                ])
                continue
            }

            var contentBlocks: [[String: Any]] = []

            for part in msg.content {
                switch part {
                case .text(let text):
                    contentBlocks.append(["type": "text", "text": text])

                case .image(let image):
                    if case .data(let data) = image.source {
                        contentBlocks.append([
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": image.mimeType ?? "image/png",
                                "data": data.base64EncodedString(),
                            ] as [String: Any],
                        ])
                    } else if case .url(let url) = image.source {
                        contentBlocks.append([
                            "type": "image",
                            "source": [
                                "type": "url",
                                "url": url.absoluteString,
                            ] as [String: Any],
                        ])
                    }

                default:
                    if let text = part.textValue {
                        contentBlocks.append(["type": "text", "text": text])
                    }
                }
            }

            if contentBlocks.count == 1, let first = contentBlocks.first, first["type"] as? String == "text" {
                apiMessages.append(["role": msg.role.rawValue, "content": first["text"] as Any])
            } else {
                apiMessages.append(["role": msg.role.rawValue, "content": contentBlocks])
            }
        }

        return (systemPrompt, apiMessages)
    }

    private func parseResponse(_ json: [String: Any]) -> (String, [ToolCall]) {
        var text = ""
        var toolCalls: [ToolCall] = []

        guard let contentBlocks = json["content"] as? [[String: Any]] else {
            return (text, toolCalls)
        }

        for block in contentBlocks {
            let type = block["type"] as? String
            if type == "text", let t = block["text"] as? String {
                text += t
            } else if type == "tool_use" {
                let name = block["name"] as? String ?? ""
                let id = block["id"] as? String ?? UUID().uuidString
                let input = block["input"] as? [String: Any] ?? [:]
                let argsData = (try? JSONSerialization.data(withJSONObject: input)) ?? Data()
                let argsStr = String(data: argsData, encoding: .utf8) ?? "{}"
                toolCalls.append(ToolCall(id: id, name: name, arguments: argsStr))
            }
        }

        return (text, toolCalls)
    }
}
