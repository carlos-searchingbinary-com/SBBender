import Testing
import Foundation
@testable import SBBender

@Suite("MLX Tool Calling Tests")
struct MLXToolCallingTests {

    // MARK: - parseToolCalls

    @Test("Parse single tool call")
    func testParseSingleToolCall() {
        let output = """
        <tool_call>
        {"name": "add", "arguments": {"a": 5, "b": 3}}
        </tool_call>
        """

        let (toolCalls, remaining) = MLXProvider.parseToolCalls(output)
        #expect(toolCalls.count == 1)
        #expect(toolCalls[0].name == "add")
        #expect(remaining.isEmpty)

        // Verify arguments are valid JSON
        let args = try? JSONSerialization.jsonObject(with: Data(toolCalls[0].arguments.utf8)) as? [String: Any]
        #expect(args?["a"] as? Int == 5)
        #expect(args?["b"] as? Int == 3)
    }

    @Test("Parse multiple tool calls")
    func testParseMultipleToolCalls() {
        let output = """
        I'll help with both calculations.
        <tool_call>
        {"name": "add", "arguments": {"a": 1, "b": 2}}
        </tool_call>
        <tool_call>
        {"name": "multiply", "arguments": {"x": 3, "y": 4}}
        </tool_call>
        """

        let (toolCalls, remaining) = MLXProvider.parseToolCalls(output)
        #expect(toolCalls.count == 2)
        #expect(toolCalls[0].name == "add")
        #expect(toolCalls[1].name == "multiply")
        #expect(remaining == "I'll help with both calculations.")
    }

    @Test("No tool calls returns empty array")
    func testNoToolCalls() {
        let output = "Just a regular response with no tool calls."

        let (toolCalls, remaining) = MLXProvider.parseToolCalls(output)
        #expect(toolCalls.isEmpty)
        #expect(remaining == output)
    }

    @Test("Tool call with text before and after")
    func testToolCallWithSurroundingText() {
        let output = """
        Let me calculate that.
        <tool_call>
        {"name": "calc", "arguments": {"expr": "2+2"}}
        </tool_call>
        Here's another thought.
        """

        let (toolCalls, remaining) = MLXProvider.parseToolCalls(output)
        #expect(toolCalls.count == 1)
        #expect(toolCalls[0].name == "calc")
        #expect(remaining.contains("Let me calculate that."))
        #expect(remaining.contains("Here's another thought."))
    }

    @Test("Tool call with no arguments")
    func testToolCallNoArguments() {
        let output = """
        <tool_call>
        {"name": "get_time"}
        </tool_call>
        """

        let (toolCalls, remaining) = MLXProvider.parseToolCalls(output)
        #expect(toolCalls.count == 1)
        #expect(toolCalls[0].name == "get_time")
        #expect(toolCalls[0].arguments == "{}")
    }

    // MARK: - buildToolPrompt

    @Test("Build tool prompt with tools")
    func testBuildToolPrompt() {
        let tools = [
            ToolDefinition(
                name: "search",
                description: "Search the web",
                parameters: ["type": "object", "properties": ["query": ["type": "string"]], "required": ["query"]]
            ),
            ToolDefinition(
                name: "calculate",
                description: "Do math",
                parameters: ["type": "object", "properties": ["expr": ["type": "string"]]]
            ),
        ]

        let prompt = MLXProvider.buildToolPrompt(tools: tools)

        #expect(prompt.contains("# Tools"))
        #expect(prompt.contains("<tools>"))
        #expect(prompt.contains("</tools>"))
        #expect(prompt.contains("<tool_call>"))
        #expect(prompt.contains("search"))
        #expect(prompt.contains("calculate"))
    }

    @Test("Build tool prompt with no tools returns empty")
    func testBuildToolPromptEmpty() {
        let prompt = MLXProvider.buildToolPrompt(tools: [])
        #expect(prompt.isEmpty)
    }

    // MARK: - buildPrompt with tools

    @Test("buildPrompt includes tool definitions in system message")
    func testBuildPromptWithTools() {
        let messages: [Message] = [
            .system("You are helpful."),
            .user("Hello"),
        ]

        let tools = [
            ToolDefinition(name: "test_tool", description: "A test", parameters: [:])
        ]

        let prompt = MLXProvider.buildPrompt(from: messages, tools: tools)

        #expect(prompt.contains("You are helpful."))
        #expect(prompt.contains("# Tools"))
        #expect(prompt.contains("test_tool"))
        #expect(prompt.contains("<|im_start|>user\nHello<|im_end|>"))
    }

    // MARK: - buildPrompt with tool response messages

    @Test("buildPrompt formats tool results as tool_response")
    func testBuildPromptToolResponse() {
        let messages: [Message] = [
            .system("Assistant"),
            .user("What is 2+2?"),
            Message(role: .assistant, content: [], toolCalls: [
                ToolCall(id: "tc1", name: "add", arguments: #"{"a":2,"b":2}"#)
            ]),
            .tool(id: "tc1", result: "4", name: "add"),
        ]

        let prompt = MLXProvider.buildPrompt(from: messages)

        #expect(prompt.contains("<tool_response>"))
        #expect(prompt.contains("</tool_response>"))
        #expect(prompt.contains("\"add\""))
        // The tool result should be in the user turn with tool_response tags
        #expect(prompt.contains("<|im_start|>user\n<tool_response>"))
    }

    @Test("buildPrompt reconstructs assistant tool call messages")
    func testBuildPromptAssistantToolCalls() {
        let messages: [Message] = [
            .system("Bot"),
            Message(role: .assistant, content: [.text("Let me check.")], toolCalls: [
                ToolCall(id: "tc1", name: "search", arguments: #"{"q":"test"}"#)
            ]),
        ]

        let prompt = MLXProvider.buildPrompt(from: messages)

        #expect(prompt.contains("<tool_call>"))
        #expect(prompt.contains("</tool_call>"))
        #expect(prompt.contains("\"search\""))
        #expect(prompt.contains("Let me check."))
    }

    // MARK: - Integration: Agent with tool calling via MockProvider

    @Test("Agent autonomously calls tool when model returns tool_call format")
    func testAgentToolCallingIntegration() async throws {
        // Create a mock provider that returns tool call format on first call,
        // then a final response on second call
        let toolCall = ToolCall(id: "tc-1", name: "multiply", arguments: #"{"a": 15, "b": 37}"#)
        let provider = MockProvider(
            responses: ["The result of 15 * 37 is 555."],
            toolCallResponses: [([toolCall], "")]
        )

        let multiplyTool = Tool(
            name: "multiply",
            description: "Multiply two numbers",
            parameters: JSONSchema(
                properties: ["a": .number("First number"), "b": .number("Second number")],
                required: ["a", "b"]
            )
        ) { arguments, _ in
            struct Args: Decodable { let a: Double; let b: Double }
            let args = try JSONDecoder().decode(Args.self, from: Data(arguments.utf8))
            return String(args.a * args.b)
        }

        let agent = Agent(
            configuration: AgentConfiguration(name: "CalcAgent"),
            model: provider,
            tools: [multiplyTool]
        )

        let result = try await agent.run("What is 15 * 37?")
        #expect(result.status == .completed)
        #expect(result.toolExecutions.count == 1)
        #expect(result.toolExecutions[0].toolName == "multiply")
        #expect(result.toolExecutions[0].result == "555.0")
        #expect(result.content == "The result of 15 * 37 is 555.")
    }

    // MARK: - stripThinkingTags + parseToolCalls combined

    @Test("Parse tool calls after stripping thinking tags")
    func testThinkingThenToolCall() {
        let output = """
        <think>Let me think about which tool to use...</think>
        <tool_call>
        {"name": "search", "arguments": {"query": "weather today"}}
        </tool_call>
        """

        let stripped = MLXProvider.stripThinkingTags(output)
        let (toolCalls, remaining) = MLXProvider.parseToolCalls(stripped)

        #expect(toolCalls.count == 1)
        #expect(toolCalls[0].name == "search")
        #expect(remaining.isEmpty)
    }
}
