import Testing
import Foundation
@testable import SBBender

@Suite("Agent Tests")
struct AgentTests {

    @Test("Basic agent run with mock provider")
    func testBasicRun() async throws {
        let provider = MockProvider(responses: ["Hello! How can I help you?"])
        let agent = Agent(
            configuration: AgentConfiguration(name: "TestAgent"),
            model: provider
        )

        let result = try await agent.run("Hi there")
        #expect(result.status == .completed)
        #expect(result.content == "Hello! How can I help you?")
        #expect(result.metrics.modelCalls == 1)
    }

    @Test("Agent with tools")
    func testAgentWithTools() async throws {
        let addTool = Tool(
            name: "add",
            description: "Add two numbers",
            parameters: JSONSchema(
                properties: ["a": .integer(), "b": .integer()],
                required: ["a", "b"]
            )
        ) { arguments, _ in
            struct Args: Decodable { let a: Int; let b: Int }
            let args = try JSONDecoder().decode(Args.self, from: Data(arguments.utf8))
            return String(args.a + args.b)
        }

        let toolCall = ToolCall(id: "tc-1", name: "add", arguments: #"{"a": 5, "b": 3}"#)
        let provider = MockProvider(
            responses: ["The sum is 8."],
            toolCallResponses: [([toolCall], "")]
        )

        let agent = Agent(
            configuration: AgentConfiguration(name: "CalcAgent"),
            model: provider,
            tools: [addTool]
        )

        let result = try await agent.run("What is 5 + 3?")
        #expect(result.status == .completed)
        #expect(result.content == "The sum is 8.")
        #expect(result.toolExecutions.count == 1)
        #expect(result.toolExecutions.first?.toolName == "add")
        #expect(result.toolExecutions.first?.result == "8")
        #expect(result.metrics.toolCalls == 1)
    }

    @Test("Agent handles missing tool gracefully")
    func testMissingTool() async throws {
        let toolCall = ToolCall(id: "tc-1", name: "nonexistent", arguments: "{}")
        let provider = MockProvider(
            responses: ["I couldn't find that tool."],
            toolCallResponses: [([toolCall], "")]
        )

        let agent = Agent(
            configuration: AgentConfiguration(name: "TestAgent"),
            model: provider
        )

        let result = try await agent.run("Do something")
        #expect(result.status == .completed)
        #expect(result.toolExecutions.first?.error != nil)
    }

    @Test("Agent with skills")
    func testAgentWithSkills() async throws {
        let provider = MockProvider(responses: ["The text is in English."])
        let agent = Agent(
            configuration: AgentConfiguration(name: "SkillAgent"),
            model: provider,
            nativeTools: [LanguageDetectionSkill(), SentimentSkill()]
        )

        let result = try await agent.run("What language is 'Hello'?")
        #expect(result.status == .completed)
    }

    @Test("Agent with storage persists session")
    func testSessionPersistence() async throws {
        let storage = InMemoryStorage()
        let provider = MockProvider(responses: ["First response", "Second response"])
        let sessionID = "test-session-123"

        let agent = Agent(
            configuration: AgentConfiguration(name: "PersistentAgent"),
            model: provider,
            storage: storage,
            sessionID: sessionID
        )

        let _ = try await agent.run("Hello")
        let session = try await storage.getSession(id: sessionID)
        #expect(session != nil)
        #expect(session!.messages.count > 0)
    }

    @Test("Agent respects tool call limit")
    func testToolCallLimit() async throws {
        // Create an agent that would loop forever on tool calls
        let toolCall = ToolCall(id: "tc-1", name: "loop", arguments: "{}")
        let loopTool = Tool(name: "loop", description: "Loop forever") { _, _ in "looping" }

        // Provider always returns tool calls
        let provider = MockProvider(
            responses: [],
            toolCallResponses: Array(repeating: ([toolCall], ""), count: 50)
        )

        let agent = Agent(
            configuration: AgentConfiguration(
                name: "LoopAgent",
                toolCallLimit: 3
            ),
            model: provider,
            tools: [loopTool]
        )

        await #expect(throws: SBBenderError.self) {
            try await agent.run("Loop")
        }
    }

    @Test("Agent cancellation")
    func testCancellation() async throws {
        let provider = MockProvider(responses: ["done"])
        let agent = Agent(
            configuration: AgentConfiguration(name: "CancelAgent"),
            model: provider
        )

        await agent.cancel()
        let result = try await agent.run("test")
        #expect(result.status == .cancelled)
    }

    @Test("Agent reset clears history")
    func testReset() async throws {
        let provider = MockProvider(responses: ["Hello", "World"])
        let agent = Agent(
            configuration: AgentConfiguration(name: "ResetAgent"),
            model: provider
        )

        let _ = try await agent.run("First")
        await agent.reset()
        // After reset, the agent should have no history
        let result = try await agent.run("Second")
        #expect(result.status == .completed)
    }

    @Test("Agent system prompt construction")
    func testSystemPrompt() {
        let config = AgentConfiguration(
            name: "TestBot",
            instructions: "Always be helpful.",
            addDateToSystemPrompt: true,
            markdown: true
        )

        let prompt = config.buildSystemPrompt(
            nativeTools: [LanguageDetectionSkill()],
            knowledgeContext: "Some knowledge",
            learningContext: "User prefers code examples"
        )

        #expect(prompt.contains("TestBot"))
        #expect(prompt.contains("Always be helpful"))
        #expect(prompt.contains("detectLanguage"))
        #expect(prompt.contains("Some knowledge"))
        #expect(prompt.contains("User prefers code examples"))
    }
}
