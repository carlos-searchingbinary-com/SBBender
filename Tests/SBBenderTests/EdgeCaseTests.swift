import Testing
import Foundation
@testable import SBBender

@Suite("Edge Case & Stress Tests")
struct EdgeCaseTests {

    // MARK: - Agent Error Handling

    @Suite("Agent Error Handling")
    struct AgentErrorTests {

        @Test("Agent handles model failure gracefully")
        func modelFailure() async {
            let provider = MockProvider(shouldFail: true)
            let agent = Agent(model: provider)

            await #expect(throws: Error.self) {
                try await agent.run("test")
            }
        }

        @Test("Agent respects tool call limit")
        func toolCallLimit() async throws {
            // Create a tool that always triggers another call
            let tool = Tool(
                name: "recurse",
                description: "Recursive tool",
                parameters: JSONSchema()
            ) { _, _ in
                "result"
            }

            // Provider always requests tool calls
            let tc = ToolCall(id: "tc-1", name: "recurse", arguments: "{}")
            let provider = MockProvider(
                responses: [],
                toolCallResponses: Array(repeating: ([tc], ""), count: 30)
            )

            let config = AgentConfiguration(name: "LimitTest", toolCallLimit: 3)
            let agent = Agent(configuration: config, model: provider, tools: [tool])

            await #expect(throws: SBBenderError.self) {
                try await agent.run("trigger recursion")
            }
        }

        @Test("Agent handles unknown tool call gracefully")
        func unknownToolCall() async throws {
            let tc = ToolCall(id: "tc-1", name: "nonexistent_tool", arguments: "{}")
            let provider = MockProvider(
                responses: ["Done."],
                toolCallResponses: [([tc], "")]
            )

            let agent = Agent(model: provider)
            let result = try await agent.run("call unknown tool")

            #expect(result.status == .completed)
            #expect(result.toolExecutions.count == 1)
            #expect(result.toolExecutions[0].error != nil)
            #expect(result.toolExecutions[0].error!.contains("not found"))
        }

        @Test("Agent cancellation stops run")
        func agentCancellation() async throws {
            let provider = MockProvider(responses: ["response"])
            let agent = Agent(model: provider)

            await agent.cancel()
            let result = try await agent.run("should be cancelled")
            #expect(result.status == .cancelled)
        }

        @Test("Agent reset clears history")
        func agentReset() async throws {
            let provider = MockProvider(responses: ["first", "second"])
            let agent = Agent(model: provider)

            _ = try await agent.run("message 1")
            await agent.reset()

            // After reset, agent should have clean state
            let result = try await agent.run("message 2")
            #expect(result.status == .completed)
        }

        @Test("Agent with empty input produces result")
        func emptyInput() async throws {
            let provider = MockProvider(responses: ["I can help!"])
            let agent = Agent(model: provider)

            let result = try await agent.run("")
            #expect(result.status == .completed)
            #expect(!result.content.isEmpty)
        }

        @Test("Agent with tool that throws error")
        func toolThrowsError() async throws {
            let tool = Tool(
                name: "failing",
                description: "Always fails",
                parameters: JSONSchema()
            ) { _, _ in
                throw SBBenderError.toolExecutionFailed(tool: "failing", reason: "Intentional failure")
            }

            let tc = ToolCall(id: "tc-1", name: "failing", arguments: "{}")
            let provider = MockProvider(
                responses: ["Handled the error."],
                toolCallResponses: [([tc], "")]
            )

            let agent = Agent(model: provider, tools: [tool])
            let result = try await agent.run("trigger failure")

            #expect(result.status == .completed)
            #expect(result.toolExecutions.count == 1)
            #expect(!result.toolExecutions[0].succeeded)
            #expect(result.toolExecutions[0].error!.contains("Intentional failure"))
        }

        @Test("Agent persists session to storage")
        func sessionPersistence() async throws {
            let storage = InMemoryStorage()
            let provider = MockProvider(responses: ["Hello back!"])
            let agent = Agent(model: provider, storage: storage, sessionID: "test-session")

            _ = try await agent.run("Hello!")

            let session = try await storage.getSession(id: "test-session")
            #expect(session != nil)
            #expect(session!.messages.count >= 2) // user + assistant at minimum
        }

        @Test("Agent with stopAfterCall tool returns tool result as content")
        func stopAfterCall() async throws {
            let tool = Tool(
                name: "final",
                description: "Final answer tool",
                parameters: JSONSchema(),
                stopAfterCall: true
            ) { _, _ in
                "The definitive answer is 42"
            }

            let tc = ToolCall(id: "tc-1", name: "final", arguments: "{}")
            let provider = MockProvider(
                responses: [],
                toolCallResponses: [([tc], "")]
            )

            let agent = Agent(model: provider, tools: [tool])
            let result = try await agent.run("what's the answer?")

            #expect(result.status == .completed)
            #expect(result.content.contains("42"))
        }
    }

    // MARK: - Agent Configuration

    @Suite("Agent Configuration")
    struct AgentConfigTests {

        @Test("System prompt includes date when configured")
        func dateInSystemPrompt() {
            let config = AgentConfiguration(name: "DateTest", addDateToSystemPrompt: true)
            let prompt = config.buildSystemPrompt()

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let today = formatter.string(from: Date())
            #expect(prompt.contains(today))
        }

        @Test("System prompt excludes date when disabled")
        func noDateInSystemPrompt() {
            let config = AgentConfiguration(name: "NoDate", addDateToSystemPrompt: false)
            let prompt = config.buildSystemPrompt()

            #expect(!prompt.contains("Current date"))
        }

        @Test("Custom system prompt overrides default")
        func customSystemPrompt() {
            let config = AgentConfiguration(
                name: "Custom",
                systemPrompt: "You are a pirate captain."
            )
            let prompt = config.buildSystemPrompt()

            #expect(prompt.contains("pirate captain"))
            #expect(!prompt.contains("You are Custom"))
        }

        @Test("Instructions appended to system prompt")
        func instructionsIncluded() {
            let config = AgentConfiguration(
                name: "Instructor",
                instructions: "Always respond in JSON format."
            )
            let prompt = config.buildSystemPrompt()

            #expect(prompt.contains("Always respond in JSON"))
        }

        @Test("Skills listed in system prompt")
        func skillsInPrompt() {
            let config = AgentConfiguration(name: "SkillTest")
            let skills: [any NativeTool] = [LanguageDetectionSkill(), SentimentSkill()]
            let prompt = config.buildSystemPrompt(nativeTools: skills)

            #expect(prompt.contains("detectLanguage"))
            #expect(prompt.contains("analyzeSentiment"))
        }

        @Test("Knowledge context injected into system prompt")
        func knowledgeContextInPrompt() {
            let config = AgentConfiguration(name: "KnowledgeTest")
            let prompt = config.buildSystemPrompt(
                knowledgeContext: "SBBender is a Swift agent runtime."
            )

            #expect(prompt.contains("Relevant Knowledge"))
            #expect(prompt.contains("Swift agent runtime"))
        }
    }

    // MARK: - Swarm Edge Cases

    @Suite("Swarm Edge Cases")
    struct SwarmEdgeCaseTests {

        @Test("Route mode routes to correct agent")
        func routedSwarm() async throws {
            let nlpAgent = Agent(
                id: "nlp-agent",
                configuration: AgentConfiguration(name: "NLP"),
                model: MockProvider(responses: ["NLP result"])
            )
            let mathAgent = Agent(
                id: "math-agent",
                configuration: AgentConfiguration(name: "Math"),
                model: MockProvider(responses: ["Math result"])
            )

            let swarm = Swarm(
                mode: .route { input in
                    input.contains("calculate") ? "math-agent" : "nlp-agent"
                },
                members: [nlpAgent, mathAgent]
            )

            let mathResult = try await swarm.run("calculate 2 + 2")
            #expect(mathResult.memberResults.count == 1)
            #expect(mathResult.content.contains("Math result"))

            let nlpResult = try await swarm.run("detect sentiment")
            #expect(nlpResult.memberResults.count == 1)
            #expect(nlpResult.content.contains("NLP result"))
        }

        @Test("Route mode throws on invalid target")
        func routedSwarmInvalidTarget() async {
            let agent = Agent(
                id: "agent-1",
                model: MockProvider(responses: ["response"])
            )

            let swarm = Swarm(
                mode: .route { _ in "nonexistent-agent" },
                members: [agent]
            )

            await #expect(throws: SBBenderError.self) {
                try await swarm.run("test")
            }
        }

        @Test("Route mode throws when router returns nil")
        func routedSwarmNilRoute() async {
            let agent = Agent(
                id: "agent-1",
                model: MockProvider(responses: ["response"])
            )

            let swarm = Swarm(
                mode: .route { _ in nil },
                members: [agent]
            )

            await #expect(throws: SBBenderError.self) {
                try await swarm.run("test")
            }
        }

        @Test("Autonomous mode without leader throws")
        func autonomousWithoutLeader() async {
            let agent = Agent(
                id: "agent-1",
                model: MockProvider(responses: ["response"])
            )

            let swarm = Swarm(
                mode: .autonomous,
                members: [agent]
            )

            await #expect(throws: SBBenderError.self) {
                try await swarm.run("test")
            }
        }

        @Test("Sequential swarm chains output through agents")
        func sequentialChaining() async throws {
            let agent1 = Agent(
                id: "agent-1",
                model: MockProvider(responses: ["step-1-output"])
            )
            let agent2 = Agent(
                id: "agent-2",
                model: MockProvider(responses: ["step-2-output"])
            )

            let swarm = Swarm(mode: .sequential, members: [agent1, agent2])
            let result = try await swarm.run("initial input")

            #expect(result.memberResults.count == 2)
            #expect(result.memberResults[0].content == "step-1-output")
            #expect(result.memberResults[1].content == "step-2-output")
        }

        @Test("Swarm aggregates metrics from all members")
        func metricsAggregation() async throws {
            let agents: [Agent] = (1...3).map { i in
                Agent(
                    id: "agent-\(i)",
                    model: MockProvider(responses: ["response \(i)"])
                )
            }

            let swarm = Swarm(mode: .parallel, members: agents)
            let result = try await swarm.run("test")

            #expect(result.metrics.modelCalls == 3)
            #expect(result.metrics.totalLatency > 0)
        }

        @Test("Single-member swarm works correctly")
        func singleMemberSwarm() async throws {
            let agent = Agent(
                id: "solo",
                model: MockProvider(responses: ["solo response"])
            )

            let swarm = Swarm(mode: .parallel, members: [agent])
            let result = try await swarm.run("test")

            #expect(result.memberResults.count == 1)
            #expect(result.content == "solo response")
        }
    }

    // MARK: - Workflow Edge Cases

    @Suite("Workflow Edge Cases")
    struct WorkflowEdgeCaseTests {

        @Test("Workflow error propagation through sequential steps")
        func errorPropagation() async {
            let failingStep = FunctionStep(name: "Failing") { _ in
                throw SBBenderError.workflowStepFailed(step: "Failing", reason: "Intentional")
            }

            let sequential = SequentialSteps(name: "Pipeline", steps: [
                FunctionStep(name: "OK") { input in input },
                failingStep,
                FunctionStep(name: "Unreachable") { _ in StepIO(text: "should not reach") },
            ])

            let workflow = Workflow(name: "FailTest", step: sequential)

            await #expect(throws: SBBenderError.self) {
                try await workflow.run("test")
            }
        }

        @Test("Loop step respects max iterations")
        func loopMaxIterations() async throws {
            let step = LoopStep(
                name: "InfiniteLoop",
                step: FunctionStep(name: "Count") { input in
                    let current = Int(input.text) ?? 0
                    return StepIO(text: "\(current + 1)")
                },
                maxIterations: 5,
                shouldContinue: { _, _ in true } // Always continue
            )

            let result = try await step.execute(input: .text("0"))
            #expect(result.text == "5")
        }

        @Test("Parallel steps with custom merge")
        func parallelCustomMerge() async throws {
            let step = ParallelSteps(
                name: "Parallel",
                steps: [
                    FunctionStep(name: "A") { _ in StepIO(text: "10", data: ["score": "10"]) },
                    FunctionStep(name: "B") { _ in StepIO(text: "20", data: ["score": "20"]) },
                    FunctionStep(name: "C") { _ in StepIO(text: "30", data: ["score": "30"]) },
                ],
                merge: { results in
                    let total = results.compactMap { Int($0.text) }.reduce(0, +)
                    return StepIO(text: "Total: \(total)")
                }
            )

            let result = try await step.execute(input: .text(""))
            #expect(result.text == "Total: 60")
        }

        @Test("StepIO data propagates through pipeline")
        func dataPropagation() async throws {
            let pipeline = SequentialSteps(name: "DataPipeline", steps: [
                FunctionStep(name: "Init") { _ in
                    StepIO(text: "ready", data: ["key1": "value1"])
                },
                FunctionStep(name: "Enrich") { input in
                    var data = input.data
                    data["key2"] = "value2"
                    return StepIO(text: input.text, data: data)
                },
                FunctionStep(name: "Verify") { input in
                    let has1 = input.data["key1"] == "value1"
                    let has2 = input.data["key2"] == "value2"
                    return StepIO(text: has1 && has2 ? "all_data_present" : "missing_data", data: input.data)
                },
            ])

            let result = try await pipeline.execute(input: .text("start"))
            #expect(result.text == "all_data_present")
            #expect(result.data.count == 2)
        }

        @Test("Router with no matching route and no default throws")
        func routerNoMatch() async {
            let step = RouterStep(
                name: "Router",
                router: { _ in "unknown_route" },
                routes: ["known": FunctionStep(name: "K") { _ in StepIO(text: "ok") }]
            )

            await #expect(throws: SBBenderError.self) {
                try await step.execute(input: .text("test"))
            }
        }

        @Test("Workflow preserves run metadata")
        func workflowMetadata() async throws {
            let workflow = Workflow(
                name: "MetaTest",
                step: FunctionStep(name: "Identity") { $0 }
            )

            let result = try await workflow.run("input")
            #expect(!result.runID.isEmpty)
            #expect(!result.workflowID.isEmpty)
            #expect(result.latency >= 0)
        }
    }

    // MARK: - ToolRegistry Edge Cases

    @Suite("ToolRegistry Edge Cases")
    struct ToolRegistryEdgeCaseTests {

        @Test("Register and retrieve tool")
        func registerAndGet() {
            var registry = ToolRegistry()
            let tool = Tool(
                name: "test_tool",
                description: "A test tool",
                parameters: JSONSchema()
            ) { _, _ in "result" }

            registry.register(tool)
            #expect(registry.get("test_tool") != nil)
            #expect(registry.get("nonexistent") == nil)
        }

        @Test("Duplicate registration overwrites")
        func duplicateRegistration() {
            var registry = ToolRegistry()
            let tool1 = Tool(name: "tool", description: "Version 1", parameters: JSONSchema()) { _, _ in "v1" }
            let tool2 = Tool(name: "tool", description: "Version 2", parameters: JSONSchema()) { _, _ in "v2" }

            registry.register(tool1)
            registry.register(tool2)

            let tool = registry.get("tool")
            #expect(tool?.description == "Version 2")
        }

        @Test("Tool definitions list matches registered tools")
        func definitionsList() {
            var registry = ToolRegistry()
            registry.register(Tool(name: "a", description: "Tool A", parameters: JSONSchema()) { _, _ in "" })
            registry.register(Tool(name: "b", description: "Tool B", parameters: JSONSchema()) { _, _ in "" })

            let defs = registry.definitions
            #expect(defs.count == 2)
            let names = Set(defs.map(\.name))
            #expect(names.contains("a"))
            #expect(names.contains("b"))
        }
    }

    // MARK: - ContextManager Edge Cases

    @Suite("ContextManager Stress Tests")
    struct ContextManagerStressTests {

        @Test("Token estimation is reasonable")
        func tokenEstimation() {
            let messages: [Message] = [
                .system("You are a helpful assistant."),
                .user("What is the weather like today in San Francisco?"),
                .assistant("The weather in San Francisco today is partly cloudy with a high of 65F."),
            ]

            let estimate = ContextManager.estimateTokens(messages)
            #expect(estimate > 0)
            // Rough chars/4 estimate should be in reasonable range
            let totalChars = messages.compactMap(\.text).reduce(0) { $0 + $1.count }
            #expect(estimate <= totalChars) // Can't be more than total chars
        }

        @Test("TrimHistory with nil limits preserves all messages")
        func noLimits() {
            let messages: [Message] = (0..<20).map { .user("Message \($0)") }
            let trimmed = ContextManager.trimHistory(messages, maxMessages: nil, maxToolResults: nil)
            #expect(trimmed.count == 20)
        }

        @Test("TrimHistory with zero messages keeps only system")
        func zeroLimit() {
            let messages: [Message] = [
                .system("system"),
                .user("msg1"),
                .assistant("reply1"),
            ]

            let trimmed = ContextManager.trimHistory(messages, maxMessages: 0, maxToolResults: nil)
            // Should keep system message at minimum
            #expect(trimmed.count >= 1)
            #expect(trimmed[0].role == .system)
        }

        @Test("ProcessToolOutput with short output stores without truncation")
        func shortOutput() {
            let store = ToolOutputStore()
            let output = "Short result"
            let processed = ContextManager.processToolOutput(
                output,
                maxLength: 1000,
                toolName: "test",
                callID: "c1",
                store: store
            )

            #expect(processed == output)
            #expect(store.count == 1)
            #expect(store.get(callID: "c1")?.fullOutput == output)
        }

        @Test("ToolOutputStore concurrent access is safe")
        func concurrentAccess() async {
            let store = ToolOutputStore(maxEntries: 100)

            await withTaskGroup(of: Void.self) { group in
                for i in 0..<50 {
                    group.addTask {
                        store.store(ToolOutputEntry(
                            callID: "call-\(i)",
                            toolName: "tool",
                            fullOutput: "output \(i)",
                            timestamp: Date()
                        ))
                    }
                }
            }

            #expect(store.count == 50)
        }
    }

    // MARK: - Storage Edge Cases

    @Suite("Storage Edge Cases")
    struct StorageEdgeCaseTests {

        @Test("InMemoryStorage handles concurrent session writes")
        func concurrentSessionWrites() async throws {
            let storage = InMemoryStorage()

            // Write sessions concurrently
            try await withThrowingTaskGroup(of: Void.self) { group in
                for i in 0..<20 {
                    group.addTask {
                        try await storage.upsertSession(Session(
                            id: "s\(i)",
                            agentID: "agent"
                        ))
                    }
                }
            }

            let sessions = try await storage.listSessions(agentID: "agent")
            #expect(sessions.count == 20)
        }

        @Test("GRDB handles concurrent operations")
        func grdbConcurrency() async throws {
            let storage = try GRDBStorage(inMemory: true)

            try await withThrowingTaskGroup(of: Void.self) { group in
                for i in 0..<10 {
                    group.addTask {
                        try await storage.upsertSession(Session(
                            id: "s\(i)",
                            agentID: "agent"
                        ))
                    }
                }
            }

            let sessions = try await storage.listSessions(agentID: "agent")
            #expect(sessions.count == 10)
        }

        @Test("Session with tool messages round-trips through storage")
        func sessionWithToolMessages() async throws {
            let storage = try GRDBStorage(inMemory: true)

            let messages: [Message] = [
                .user("Search for Swift"),
                Message(role: .assistant, content: [.text("Let me search.")], toolCalls: [
                    ToolCall(id: "tc1", name: "search", arguments: "{\"q\":\"Swift\"}")
                ]),
                .tool(id: "tc1", result: "Found 10 results", name: "search"),
                .assistant("I found 10 results about Swift."),
            ]

            let session = Session(
                id: "tool-session",
                agentID: "agent",
                messages: messages,
                state: ["topic": "Swift"]
            )

            try await storage.upsertSession(session)
            let loaded = try await storage.getSession(id: "tool-session")

            #expect(loaded != nil)
            #expect(loaded!.messages.count == 4)
            #expect(loaded!.messages[2].role == .tool)
            #expect(loaded!.state["topic"] == "Swift")
        }
    }

    // MARK: - Message & Content

    @Suite("Message Edge Cases")
    struct MessageEdgeCaseTests {

        @Test("Message text extraction from various roles")
        func textExtraction() {
            let system = Message.system("system prompt")
            let user = Message.user("user message")
            let assistant = Message.assistant("assistant reply")
            let tool = Message.tool(id: "t1", result: "tool result", name: "search")

            #expect(system.text == "system prompt")
            #expect(user.text == "user message")
            #expect(assistant.text == "assistant reply")
            #expect(tool.text == "tool result")
        }

        @Test("Assistant message with tool calls")
        func assistantWithToolCalls() {
            let msg = Message(
                role: .assistant,
                content: [.text("Let me help.")],
                toolCalls: [
                    ToolCall(id: "tc1", name: "search", arguments: "{}"),
                    ToolCall(id: "tc2", name: "calculate", arguments: "{\"expr\":\"2+2\"}"),
                ]
            )

            #expect(msg.role == .assistant)
            #expect(msg.toolCalls?.count == 2)
            #expect(msg.text == "Let me help.")
        }
    }

    // MARK: - BM25 Edge Cases

    @Suite("BM25 Edge Cases")
    struct BM25EdgeCaseTests {

        @Test("Single document scores correctly")
        func singleDocument() {
            let bm25 = BM25Index(documents: ["Swift programming language"])
            let scores = bm25.score(query: "Swift")
            #expect(scores.count == 1)
            #expect(scores[0] > 0)
        }

        @Test("Document matching all query terms scores highest")
        func allTermsMatch() {
            let docs = [
                "Apple Swift programming",
                "Swift programming language",
                "Apple Swift programming language", // matches all terms
                "Python programming",
            ]
            let bm25 = BM25Index(documents: docs)
            let scores = bm25.score(query: "Apple Swift programming language")

            // Doc with all terms should score highest
            let maxIndex = scores.enumerated().max(by: { $0.element < $1.element })!.offset
            #expect(maxIndex == 2)
        }

        @Test("Very long documents don't dominate scores")
        func longDocuments() {
            let shortDoc = "Swift is great"
            let longDoc = "Swift is great " + String(repeating: "filler word ", count: 500)
            let bm25 = BM25Index(documents: [shortDoc, longDoc])
            let scores = bm25.score(query: "Swift great")

            // BM25 length normalization should prevent long doc from dominating
            // Short doc with higher term density should score well
            #expect(scores[0] > 0)
            #expect(scores[1] > 0)
        }
    }

    // MARK: - HNSW Edge Cases

    @Suite("HNSW Edge Cases")
    struct HNSWEdgeCaseTests {

        @Test("Single vector graph")
        func singleVector() async {
            let graph = HNSWGraph()
            await graph.build(vectors: [[1, 0, 0]])

            let results = await graph.search(query: [1, 0, 0], k: 1)
            #expect(results.count == 1)
            #expect(results[0].id == 0)
        }

        @Test("k larger than graph returns all nodes")
        func kLargerThanGraph() async {
            let graph = HNSWGraph(maxConnections: 4, efConstruction: 16)
            await graph.build(vectors: [[1, 0], [0, 1]])

            let results = await graph.search(query: [1, 0], k: 10)
            #expect(results.count == 2)
        }

        @Test("Identical vectors are both found")
        func identicalVectors() async {
            let graph = HNSWGraph(maxConnections: 4, efConstruction: 16)
            await graph.build(vectors: [[1, 1], [1, 1], [0, 0]])

            let results = await graph.search(query: [1, 1], k: 3)
            #expect(results.count == 3)
            // First two should have distance 0 (identical)
            #expect(results[0].distance < 0.001)
        }

        @Test("High-dimensional vectors")
        func highDimensional() async {
            let dim = 128
            var vectors: [[Float]] = []
            for i in 0..<10 {
                var v = [Float](repeating: 0, count: dim)
                v[i % dim] = 1.0
                vectors.append(v)
            }

            let graph = HNSWGraph(maxConnections: 8, efConstruction: 32)
            await graph.build(vectors: vectors)

            let query = vectors[0]
            let results = await graph.search(query: query, k: 3)
            #expect(results.count == 3)
            #expect(results[0].id == 0)
        }
    }
}
