import Foundation

/// A pluggable parser for tool call formatting in model prompts and outputs.
///
/// Different LLM architectures use different conventions for tool calling.
/// This protocol abstracts the format so that `MLXProvider` can work with
/// any model family by swapping the format implementation.
public protocol ToolCallFormat: Sendable {
    /// Format tool definitions into a prompt block for the system message.
    func formatToolPrompt(tools: [ToolDefinition]) -> String

    /// Parse tool calls from raw model output.
    ///
    /// Returns the parsed `ToolCall` objects and any remaining text content
    /// that is not part of a tool call block.
    func parseToolCalls(_ text: String) -> ([ToolCall], String)

    /// Format a tool result for injection back into the conversation.
    func formatToolResult(name: String, result: String) -> String
}

// MARK: - Qwen3 Format

/// Tool call format for Qwen3 models.
///
/// Uses `<tool_call>` / `</tool_call>` XML tags and `<tool_response>` for results.
/// This is the default format for MLXProvider.
public struct Qwen3ToolFormat: ToolCallFormat {
    public init() {}

    public func formatToolPrompt(tools: [ToolDefinition]) -> String {
        guard !tools.isEmpty else { return "" }

        var toolDefs: [String] = []
        for tool in tools {
            let funcDict: [String: Any] = [
                "name": tool.name,
                "description": tool.description,
                "parameters": tool.parameters
            ]
            let toolDict: [String: Any] = ["type": "function", "function": funcDict]

            if let data = try? JSONSerialization.data(withJSONObject: toolDict, options: [.sortedKeys]),
               let json = String(data: data, encoding: .utf8) {
                toolDefs.append(json)
            }
        }

        return """
        # Tools

        You may call one or more functions to assist with the user query.

        You are provided with function signatures within <tools></tools> XML tags:
        <tools>
        \(toolDefs.joined(separator: "\n"))
        </tools>

        For each function call, return a json object with function name and arguments within <tool_call></tool_call> XML tags:
        <tool_call>
        {"name": <function-name>, "arguments": <args-json-object>}
        </tool_call>
        """
    }

    public func parseToolCalls(_ text: String) -> ([ToolCall], String) {
        var toolCalls: [ToolCall] = []
        var remainingText = text

        while let startRange = remainingText.range(of: "<tool_call>"),
              let endRange = remainingText.range(of: "</tool_call>", range: startRange.upperBound..<remainingText.endIndex) {

            let blockContent = String(remainingText[startRange.upperBound..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let data = blockContent.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let name = json["name"] as? String {

                let arguments: String
                if let args = json["arguments"] {
                    if let argsData = try? JSONSerialization.data(withJSONObject: args, options: [.sortedKeys]),
                       let argsString = String(data: argsData, encoding: .utf8) {
                        arguments = argsString
                    } else {
                        arguments = "{}"
                    }
                } else {
                    arguments = "{}"
                }

                toolCalls.append(ToolCall(name: name, arguments: arguments))
            }

            remainingText = String(remainingText[remainingText.startIndex..<startRange.lowerBound])
                + String(remainingText[endRange.upperBound...])
        }

        remainingText = remainingText.trimmingCharacters(in: .whitespacesAndNewlines)
        return (toolCalls, remainingText)
    }

    public func formatToolResult(name: String, result: String) -> String {
        let escaped = escapeJSON(result)
        return "<tool_response>\n{\"name\": \"\(name)\", \"content\": \(escaped)}\n</tool_response>"
    }

    private func escapeJSON(_ string: String) -> String {
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

// MARK: - Llama Format

/// Tool call format for Llama 3.x models.
///
/// Uses `<|python_tag|>` prefix with `{"name": ..., "parameters": ...}` JSON blocks.
public struct LlamaToolFormat: ToolCallFormat {
    public init() {}

    public func formatToolPrompt(tools: [ToolDefinition]) -> String {
        guard !tools.isEmpty else { return "" }

        var toolDefs: [String] = []
        for tool in tools {
            let funcDict: [String: Any] = [
                "name": tool.name,
                "description": tool.description,
                "parameters": tool.parameters
            ]

            if let data = try? JSONSerialization.data(withJSONObject: funcDict, options: [.sortedKeys]),
               let json = String(data: data, encoding: .utf8) {
                toolDefs.append(json)
            }
        }

        return """
        You have access to the following functions. To call a function, respond with a JSON object with the function name and parameters.

        Available functions:
        \(toolDefs.joined(separator: "\n"))
        """
    }

    public func parseToolCalls(_ text: String) -> ([ToolCall], String) {
        var toolCalls: [ToolCall] = []
        var remainingText = text

        // Llama uses <|python_tag|> prefix
        let pythonTag = "<|python_tag|>"
        if let tagRange = remainingText.range(of: pythonTag) {
            let afterTag = String(remainingText[tagRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            remainingText = String(remainingText[..<tagRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)

            // Try to parse JSON object(s) after the tag
            if let parsed = parseJSONToolCall(afterTag, nameKey: "name", argsKey: "parameters") {
                toolCalls.append(parsed)
            }
        }

        // Also try parsing standalone JSON objects with "name" and "parameters" keys
        if toolCalls.isEmpty {
            if let parsed = parseJSONToolCall(text, nameKey: "name", argsKey: "parameters") {
                toolCalls.append(parsed)
                remainingText = ""
            }
        }

        return (toolCalls, remainingText)
    }

    public func formatToolResult(name: String, result: String) -> String {
        return "{\"name\": \"\(name)\", \"result\": \(escapeJSON(result))}"
    }

    private func parseJSONToolCall(_ text: String, nameKey: String, argsKey: String) -> ToolCall? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json[nameKey] as? String else {
            return nil
        }

        let arguments: String
        if let args = json[argsKey] {
            if let argsData = try? JSONSerialization.data(withJSONObject: args, options: [.sortedKeys]),
               let argsString = String(data: argsData, encoding: .utf8) {
                arguments = argsString
            } else {
                arguments = "{}"
            }
        } else {
            arguments = "{}"
        }

        return ToolCall(name: name, arguments: arguments)
    }

    private func escapeJSON(_ string: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: [string], options: []),
           let jsonArray = String(data: data, encoding: .utf8) {
            return String(jsonArray.dropFirst(1).dropLast(1))
        }
        return "\"\(string)\""
    }
}

// MARK: - Generic Format

/// A fallback tool call format that uses JSON code blocks.
///
/// Works with models that don't have a specific tool calling convention
/// but can be instructed to output JSON in code blocks.
public struct GenericToolFormat: ToolCallFormat {
    public init() {}

    public func formatToolPrompt(tools: [ToolDefinition]) -> String {
        guard !tools.isEmpty else { return "" }

        var toolDefs: [String] = []
        for tool in tools {
            let funcDict: [String: Any] = [
                "name": tool.name,
                "description": tool.description,
                "parameters": tool.parameters
            ]
            if let data = try? JSONSerialization.data(withJSONObject: funcDict, options: [.sortedKeys, .prettyPrinted]),
               let json = String(data: data, encoding: .utf8) {
                toolDefs.append(json)
            }
        }

        return """
        You have access to the following tools:

        \(toolDefs.joined(separator: "\n\n"))

        To call a tool, output a JSON code block with the tool name and arguments:
        ```json
        {"tool": "<tool-name>", "arguments": {<args>}}
        ```
        """
    }

    public func parseToolCalls(_ text: String) -> ([ToolCall], String) {
        var toolCalls: [ToolCall] = []
        var remainingText = text

        // Match ```json ... ``` blocks
        let codeBlockPattern = "```(?:json)?\\s*\\n?(\\{[\\s\\S]*?\\})\\s*\\n?```"
        guard let regex = try? NSRegularExpression(pattern: codeBlockPattern) else {
            return ([], text)
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        // Process matches in reverse to preserve indices when removing
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2 else { continue }

            let jsonRange = match.range(at: 1)
            let jsonStr = nsText.substring(with: jsonRange)

            if let data = jsonStr.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let name = json["tool"] as? String ?? json["name"] as? String {

                let arguments: String
                if let args = json["arguments"] {
                    if let argsData = try? JSONSerialization.data(withJSONObject: args, options: [.sortedKeys]),
                       let argsString = String(data: argsData, encoding: .utf8) {
                        arguments = argsString
                    } else {
                        arguments = "{}"
                    }
                } else {
                    arguments = "{}"
                }

                toolCalls.insert(ToolCall(name: name, arguments: arguments), at: 0)
            }

            // Remove the code block from remaining text
            let fullRange = match.range(at: 0)
            let startIdx = remainingText.index(remainingText.startIndex, offsetBy: fullRange.location)
            let endIdx = remainingText.index(startIdx, offsetBy: fullRange.length)
            remainingText.replaceSubrange(startIdx..<endIdx, with: "")
        }

        remainingText = remainingText.trimmingCharacters(in: .whitespacesAndNewlines)
        return (toolCalls, remainingText)
    }

    public func formatToolResult(name: String, result: String) -> String {
        return "Tool \"\(name)\" returned: \(result)"
    }
}
