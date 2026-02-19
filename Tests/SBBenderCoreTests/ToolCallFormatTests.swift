import Testing
@testable import SBBenderCore

@Suite("ToolCallFormat Tests")
struct ToolCallFormatTests {
    let sampleTools: [ToolDefinition] = [
        ToolDefinition(
            name: "get_weather",
            description: "Get the weather for a location",
            parameters: [
                "type": "object",
                "properties": [
                    "location": ["type": "string", "description": "City name"]
                ],
                "required": ["location"]
            ]
        )
    ]

    // MARK: - Qwen3 Format

    @Suite("Qwen3ToolFormat")
    struct Qwen3Tests {
        let format = Qwen3ToolFormat()

        @Test("Format tool prompt includes tools XML tags")
        func formatToolPrompt() {
            let tools = [ToolDefinition(
                name: "test_tool",
                description: "A test tool",
                parameters: ["type": "object"]
            )]
            let prompt = format.formatToolPrompt(tools: tools)
            #expect(prompt.contains("<tools>"))
            #expect(prompt.contains("</tools>"))
            #expect(prompt.contains("test_tool"))
            #expect(prompt.contains("tool_call"))
        }

        @Test("Empty tools returns empty string")
        func emptyTools() {
            let prompt = format.formatToolPrompt(tools: [])
            #expect(prompt.isEmpty)
        }

        @Test("Parse single tool call")
        func parseSingleToolCall() {
            let text = """
            I'll check the weather.
            <tool_call>
            {"name": "get_weather", "arguments": {"location": "Paris"}}
            </tool_call>
            """
            let (calls, remaining) = format.parseToolCalls(text)
            #expect(calls.count == 1)
            #expect(calls[0].name == "get_weather")
            #expect(remaining.contains("I'll check the weather"))
            #expect(!remaining.contains("tool_call"))
        }

        @Test("Parse multiple tool calls")
        func parseMultipleToolCalls() {
            let text = """
            <tool_call>
            {"name": "get_weather", "arguments": {"location": "Paris"}}
            </tool_call>
            <tool_call>
            {"name": "get_weather", "arguments": {"location": "London"}}
            </tool_call>
            """
            let (calls, _) = format.parseToolCalls(text)
            #expect(calls.count == 2)
        }

        @Test("No tool calls returns empty array")
        func noToolCalls() {
            let (calls, remaining) = format.parseToolCalls("Just a normal response.")
            #expect(calls.isEmpty)
            #expect(remaining == "Just a normal response.")
        }

        @Test("Format tool result")
        func formatResult() {
            let result = format.formatToolResult(name: "get_weather", result: "Sunny, 25C")
            #expect(result.contains("<tool_response>"))
            #expect(result.contains("</tool_response>"))
            #expect(result.contains("get_weather"))
            #expect(result.contains("Sunny"))
        }
    }

    // MARK: - Llama Format

    @Suite("LlamaToolFormat")
    struct LlamaTests {
        let format = LlamaToolFormat()

        @Test("Format tool prompt")
        func formatToolPrompt() {
            let tools = [ToolDefinition(
                name: "search",
                description: "Search the web",
                parameters: ["type": "object"]
            )]
            let prompt = format.formatToolPrompt(tools: tools)
            #expect(prompt.contains("search"))
            #expect(prompt.contains("Available functions"))
        }

        @Test("Parse python_tag tool call")
        func parsePythonTag() {
            let text = """
            Let me search for that.
            <|python_tag|>{"name": "search", "parameters": {"query": "swift"}}
            """
            let (calls, remaining) = format.parseToolCalls(text)
            #expect(calls.count == 1)
            #expect(calls[0].name == "search")
            #expect(remaining.contains("Let me search"))
        }

        @Test("Parse standalone JSON tool call")
        func parseStandaloneJSON() {
            let text = """
            {"name": "search", "parameters": {"query": "swift"}}
            """
            let (calls, _) = format.parseToolCalls(text)
            #expect(calls.count == 1)
            #expect(calls[0].name == "search")
        }

        @Test("No tool call in plain text")
        func noToolCall() {
            let (calls, _) = format.parseToolCalls("Hello world")
            #expect(calls.isEmpty)
        }
    }

    // MARK: - Generic Format

    @Suite("GenericToolFormat")
    struct GenericTests {
        let format = GenericToolFormat()

        @Test("Format tool prompt")
        func formatToolPrompt() {
            let tools = [ToolDefinition(
                name: "calculate",
                description: "Do math",
                parameters: ["type": "object"]
            )]
            let prompt = format.formatToolPrompt(tools: tools)
            #expect(prompt.contains("calculate"))
            #expect(prompt.contains("json"))
        }

        @Test("Parse JSON code block")
        func parseCodeBlock() {
            let text = """
            Let me calculate that:
            ```json
            {"tool": "calculate", "arguments": {"expression": "2+2"}}
            ```
            """
            let (calls, remaining) = format.parseToolCalls(text)
            #expect(calls.count == 1)
            #expect(calls[0].name == "calculate")
            #expect(remaining.contains("Let me calculate"))
        }

        @Test("Parse code block with name key instead of tool")
        func parseNameKey() {
            let text = """
            ```json
            {"name": "calculate", "arguments": {"expression": "3*5"}}
            ```
            """
            let (calls, _) = format.parseToolCalls(text)
            #expect(calls.count == 1)
            #expect(calls[0].name == "calculate")
        }

        @Test("No code blocks returns empty")
        func noCodeBlocks() {
            let (calls, _) = format.parseToolCalls("Just text, no code blocks.")
            #expect(calls.isEmpty)
        }
    }
}
