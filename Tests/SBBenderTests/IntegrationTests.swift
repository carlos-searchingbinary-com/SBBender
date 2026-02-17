import Testing
import Foundation
@testable import SBBender

@Suite("Integration Tests")
struct IntegrationTests {

    // MARK: - Agent + ContextManager Integration

    @Suite("Agent Context Management")
    struct AgentContextTests {

        @Test("Agent trims history when configured")
        func agentTrimsHistory() async throws {
            let config = AgentConfiguration(
                name: "ContextTest",
                maxHistoryMessages: 4,
                maxHistoryToolResults: 2
            )
            let provider = MockProvider(responses: [
                "response 1", "response 2", "response 3", "response 4", "response 5", "final",
            ])
            let agent = Agent(configuration: config, model: provider)

            for i in 1...5 {
                _ = try await agent.run("message \(i)")
            }

            let result = try await agent.run("final message")
            #expect(result.status == .completed)
        }

        @Test("Agent stores tool outputs for inspection")
        func agentStoresToolOutputs() async throws {
            let tool = Tool(
                name: "search",
                description: "Search tool",
                parameters: JSONSchema(properties: ["query": .string("query")])
            ) { _, _ in
                "Found 42 results for your query with detailed information."
            }

            let tc = ToolCall(id: "tc-1", name: "search", arguments: "{\"query\": \"test\"}")
            let provider = MockProvider(
                responses: ["Done with search."],
                toolCallResponses: [([tc], "")]
            )
            let agent = Agent(model: provider, tools: [tool])
            _ = try await agent.run("search for test")

            let store = await agent.toolOutputStore
            #expect(store.count > 0)
            let entries = store.allEntries
            #expect(entries.first?.toolName == "search")
            #expect(entries.first?.fullOutput.contains("42 results") == true)
        }

        @Test("ToolOutputStore processes long outputs correctly")
        func longToolOutputProcessing() async throws {
            let longOutput = String(repeating: "x", count: 5000)
            let tool = Tool(
                name: "analyze",
                description: "Analysis tool",
                parameters: JSONSchema(),
                maxContentLength: 200
            ) { _, _ in
                longOutput
            }

            let tc = ToolCall(id: "tc-1", name: "analyze", arguments: "{}")
            let provider = MockProvider(
                responses: ["Analysis complete."],
                toolCallResponses: [([tc], "")]
            )
            let agent = Agent(model: provider, tools: [tool])
            let result = try await agent.run("analyze something")

            let store = await agent.toolOutputStore
            let entry = store.allEntries.first
            #expect(entry?.fullOutput.count == 5000)
            #expect(entry?.toolName == "analyze")
            #expect(result.status == .completed)
        }
    }

    // MARK: - Agent + DocumentIndexer Integration

    @Suite("Agent Knowledge Integration")
    struct AgentKnowledgeTests {

        @Test("Agent uses DocumentIndexer as knowledge source")
        func agentWithDocumentIndexer() async throws {
            let indexer = DocumentIndexer(config: .init(chunkingStrategy: .paragraph))

            try await indexer.insert(
                content: "SBBender is a Swift agent runtime for Apple platforms. It supports tools, skills, and swarms.",
                metadata: ["title": "About SBBender"]
            )
            try await indexer.insert(
                content: "The weather today is sunny with temperatures around 72F.",
                metadata: ["title": "Weather"]
            )

            let provider = MockProvider(responses: ["Based on the context, SBBender is an agent runtime."])
            let agent = Agent(model: provider, knowledge: indexer)

            let result = try await agent.run("What is SBBender?")
            #expect(result.status == .completed)
            #expect(!result.content.isEmpty)
        }
    }

    // MARK: - Swarm Integration

    @Suite("Swarm Integration")
    struct SwarmContextTests {

        @Test("Sequential swarm preserves order")
        func sequentialSwarmOrder() async throws {
            let agents: [Agent] = (1...3).map { i in
                let provider = MockProvider(responses: ["Agent \(i) response"])
                return Agent(
                    id: "agent-\(i)",
                    configuration: AgentConfiguration(name: "Agent\(i)"),
                    model: provider
                )
            }

            let swarm = Swarm(mode: .sequential, members: agents)
            let swarmResult = try await swarm.run("test input")

            #expect(swarmResult.memberResults.count == 3)
            #expect(swarmResult.memberResults[0].content.contains("Agent 1"))
            #expect(swarmResult.memberResults[1].content.contains("Agent 2"))
            #expect(swarmResult.memberResults[2].content.contains("Agent 3"))
        }

        @Test("Parallel swarm maintains order after fix")
        func parallelSwarmOrder() async throws {
            let agents: [Agent] = (1...5).map { i in
                let provider = MockProvider(responses: ["Result-\(i)"])
                return Agent(
                    id: "agent-\(i)",
                    configuration: AgentConfiguration(name: "Agent\(i)"),
                    model: provider
                )
            }

            let swarm = Swarm(mode: .parallel, members: agents)
            let swarmResult = try await swarm.run("test")

            #expect(swarmResult.memberResults.count == 5)
            for (i, result) in swarmResult.memberResults.enumerated() {
                #expect(result.content.contains("Result-\(i + 1)"))
            }
        }
    }

    // MARK: - ContextManager Detailed Tests

    @Suite("ContextManager Edge Cases")
    struct ContextManagerEdgeCases {

        @Test("TrimHistory correctly handles interleaved tool messages")
        func interleavedToolMessages() {
            let messages: [Message] = [
                .system("system"),
                .user("q1"),
                .assistant("thinking..."),
                .tool(id: "t1", result: "r1", name: "tool1"),
                .user("q2"),
                .assistant("thinking more..."),
                .tool(id: "t2", result: "r2", name: "tool2"),
                .tool(id: "t3", result: "r3", name: "tool3"),
                .user("q3"),
            ]

            let trimmed = ContextManager.trimHistory(messages, maxMessages: nil, maxToolResults: 2)
            let toolMessages = trimmed.filter { $0.role == .tool }
            #expect(toolMessages.count == 2)
        }

        @Test("TrimHistory preserves all system messages even with low limit")
        func preserveSystemMessages() {
            let messages: [Message] = [
                .system("system prompt"),
                .user("msg 1"),
                .assistant("reply 1"),
                .user("msg 2"),
                .assistant("reply 2"),
            ]

            let trimmed = ContextManager.trimHistory(messages, maxMessages: 1, maxToolResults: nil)
            #expect(trimmed.count == 2) // system + 1 non-system
            #expect(trimmed[0].role == .system)
        }

        @Test("ProcessToolOutput stores and summarizes correctly")
        func processToolOutput() {
            let store = ToolOutputStore()
            let longOutput = String(repeating: "data ", count: 1000)

            let model = ContextManager.processToolOutput(
                longOutput,
                maxLength: 100,
                toolName: "bigTool",
                callID: "call-42",
                store: store
            )

            #expect(model.count < longOutput.count)
            #expect(model.contains("truncated"))

            let entry = store.get(callID: "call-42")
            #expect(entry?.fullOutput.count == longOutput.count)
            #expect(entry?.toolName == "bigTool")
        }

        @Test("ToolOutputStore eviction works correctly under pressure")
        func storeEviction() {
            let store = ToolOutputStore(maxEntries: 5)

            for i in 0..<20 {
                store.store(ToolOutputEntry(
                    callID: "call-\(i)",
                    toolName: "tool",
                    fullOutput: "output \(i)",
                    timestamp: Date()
                ))
            }

            #expect(store.count == 5)
            #expect(store.get(callID: "call-14") == nil)
            #expect(store.get(callID: "call-15") != nil)
            #expect(store.get(callID: "call-19") != nil)
        }
    }

    // MARK: - Workflow Integration

    @Suite("Workflow Integration")
    struct WorkflowIntegrationTests {

        @Test("Sequential workflow steps execute in order")
        func sequentialWorkflow() async throws {
            let step1 = FunctionStep(name: "Step1") { input in
                StepIO(text: "result-1", data: input.data)
            }
            let step2 = FunctionStep(name: "Step2") { input in
                StepIO(text: "result-2 after \(input.text)", data: input.data)
            }
            let step3 = FunctionStep(name: "Step3") { input in
                StepIO(text: "done: \(input.text)")
            }

            let sequential = SequentialSteps(name: "Pipeline", steps: [step1, step2, step3])
            let workflow = Workflow(name: "Test", step: sequential)
            let result = try await workflow.run("start")

            #expect(result.output.text.contains("result-2"))
            #expect(result.output.text.contains("done"))
        }

        @Test("Conditional workflow step runs based on predicate")
        func conditionalWorkflow() async throws {
            let check = FunctionStep(name: "Check") { _ in
                StepIO(text: "approved")
            }
            let process = FunctionStep(name: "Process") { input in
                StepIO(text: "processed: \(input.text)")
            }
            let skip = FunctionStep(name: "Skip") { input in
                StepIO(text: "skipped")
            }

            let conditional = ConditionalStep(
                name: "DecideStep",
                condition: { $0.text == "approved" },
                ifTrue: process,
                ifFalse: skip
            )

            let sequential = SequentialSteps(name: "Pipeline", steps: [check, conditional])
            let workflow = Workflow(name: "CondTest", step: sequential)
            let result = try await workflow.run("test")

            #expect(result.output.text.contains("processed"))
        }
    }

    // MARK: - Tool Call Format Round-Trip

    @Suite("ToolCallFormat Round-Trip")
    struct ToolCallFormatRoundTrip {

        @Test("Qwen3 format: format → parse round-trip")
        func qwen3RoundTrip() {
            let format = Qwen3ToolFormat()
            let tools = [ToolDefinition(
                name: "get_weather",
                description: "Get weather",
                parameters: ["type": "object", "properties": ["city": ["type": "string"]]]
            )]

            let prompt = format.formatToolPrompt(tools: tools)
            #expect(prompt.contains("get_weather"))
            #expect(prompt.contains("<tools>"))

            let text = """
            Let me check.
            <tool_call>
            {"name": "get_weather", "arguments": {"city": "NYC"}}
            </tool_call>
            """
            let (calls, remaining) = format.parseToolCalls(text)
            #expect(calls.count == 1)
            #expect(calls[0].name == "get_weather")
            #expect(remaining.contains("Let me check"))

            let result = format.formatToolResult(name: "get_weather", result: "Sunny, 72F")
            #expect(result.contains("<tool_response>"))
            #expect(result.contains("Sunny"))
        }

        @Test("Llama format: python_tag → parse round-trip")
        func llamaRoundTrip() {
            let format = LlamaToolFormat()
            let text = """
            <|python_tag|>{"name": "search", "parameters": {"query": "swift"}}
            """
            let (calls, _) = format.parseToolCalls(text)
            #expect(calls.count == 1)
            #expect(calls[0].name == "search")
        }

        @Test("Generic format: code block → parse round-trip")
        func genericRoundTrip() {
            let format = GenericToolFormat()
            let text = """
            Here's my plan:
            ```json
            {"tool": "calculate", "arguments": {"expr": "2+2"}}
            ```
            """
            let (calls, remaining) = format.parseToolCalls(text)
            #expect(calls.count == 1)
            #expect(calls[0].name == "calculate")
            #expect(remaining.contains("Here's my plan"))
        }
    }

    // MARK: - End-to-End: Agent + Knowledge + Tools

    @Suite("End-to-End Agent Pipeline")
    struct E2ETests {

        @Test("Full pipeline: ingest → index → agent search")
        func fullPipeline() async throws {
            let indexer = DocumentIndexer(config: .init(chunkingStrategy: .paragraph))
            try await indexer.insert(
                content: "Swift 6 introduces strict concurrency checking. All public APIs must be Sendable-safe.",
                metadata: ["title": "Swift 6"]
            )
            try await indexer.insert(
                content: "The Eiffel Tower was built in 1889 for the World's Fair in Paris.",
                metadata: ["title": "History"]
            )

            let results = try await indexer.search(query: "concurrency Swift", limit: 1)
            #expect(!results.isEmpty)
            #expect(results[0].content.contains("Sendable"))

            let provider = MockProvider(responses: ["Swift 6 has strict concurrency."])
            let agent = Agent(model: provider, knowledge: indexer)
            let result = try await agent.run("Tell me about Swift concurrency")
            #expect(result.status == .completed)
        }

        @Test("Agent with multiple skills produces correct tool executions")
        func agentMultipleSkills() async throws {
            let tc = ToolCall(id: "tc-1", name: "detectLanguage", arguments: "{\"input\": \"Bonjour le monde\"}")
            let provider = MockProvider(
                responses: ["The language is French."],
                toolCallResponses: [([tc], "")]
            )
            let skills: [any NativeTool] = [LanguageDetectionSkill(), SentimentSkill()]
            let agent = Agent(model: provider, nativeTools: skills)

            let result = try await agent.run("Detect language of: Bonjour le monde")
            #expect(result.toolExecutions.count >= 1)
            #expect(result.toolExecutions[0].toolName == "detectLanguage")
            #expect(result.toolExecutions[0].succeeded)
        }
    }
}
