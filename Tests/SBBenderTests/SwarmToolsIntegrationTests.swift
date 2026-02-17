import Testing
import Foundation
@testable import SBBender
import MCP

/// Comprehensive integration tests verifying that Swarms work correctly
/// with tools, skills (as tools), MCP servers, and Apple automations.
///
/// These tests exercise the full pipeline:
/// Agent → Tool Registry → Skill-as-Tool → Tool Execution → Model Loop
/// Agent → MCP Manager → MCP Tool → Tool Execution → Model Loop
/// Swarm → Multiple Agents with tools/skills/MCP → Coordinated execution

@Suite("Swarm + Tools Integration")
struct SwarmToolsIntegrationTests {

    // MARK: - Parallel Swarm with Tool-Calling Agents

    @Test("Parallel swarm where each agent calls tools autonomously")
    func testParallelSwarmWithToolCalls() async throws {
        // Agent 1: Calculator agent that calls an "add" tool
        let addToolCall = ToolCall(id: "tc-add", name: "add", arguments: #"{"a": 5, "b": 3}"#)
        let calcAgent = Agent(
            configuration: AgentConfiguration(name: "Calculator"),
            model: MockProvider(
                responses: ["The sum is 8."],
                toolCallResponses: [([addToolCall], "")]
            ),
            tools: [
                Tool(name: "add", description: "Add two numbers", parameters: JSONSchema(
                    properties: ["a": .number(), "b": .number()],
                    required: ["a", "b"]
                )) { args, _ in
                    struct AddArgs: Decodable { let a: Double; let b: Double }
                    let parsed = try JSONDecoder().decode(AddArgs.self, from: Data(args.utf8))
                    return String(parsed.a + parsed.b)
                }
            ]
        )

        // Agent 2: Greeter agent that calls a "greet" tool
        let greetToolCall = ToolCall(id: "tc-greet", name: "greet", arguments: #"{"name": "World"}"#)
        let greeterAgent = Agent(
            configuration: AgentConfiguration(name: "Greeter"),
            model: MockProvider(
                responses: ["I greeted World."],
                toolCallResponses: [([greetToolCall], "")]
            ),
            tools: [
                Tool(name: "greet", description: "Greet someone") { args, _ in
                    struct GreetArgs: Decodable { let name: String }
                    let parsed = try JSONDecoder().decode(GreetArgs.self, from: Data(args.utf8))
                    return "Hello, \(parsed.name)!"
                }
            ]
        )

        let swarm = Swarm(
            name: "ToolSwarm",
            mode: .parallel,
            members: [calcAgent, greeterAgent]
        )

        let result = try await swarm.run("Process data")
        #expect(result.memberResults.count == 2)

        // Both agents should have completed with tool executions
        for memberResult in result.memberResults {
            #expect(memberResult.status == .completed)
            #expect(memberResult.toolExecutions.count == 1)
            #expect(memberResult.toolExecutions[0].succeeded)
        }

        // Verify aggregated metrics count tool calls
        #expect(result.metrics.toolCalls == 2)
    }

    // MARK: - Sequential Swarm with Skills as Tools

    @Test("Sequential swarm where agents use NLP skills as tools")
    func testSequentialSwarmWithSkillTools() async throws {
        // Agent 1: Detects language using the LanguageDetection skill-as-tool
        let langToolCall = ToolCall(
            id: "tc-lang",
            name: "detectLanguage",
            arguments: #"{"input": "Bonjour le monde, comment allez-vous aujourd'hui?"}"#
        )
        let langAgent = Agent(
            configuration: AgentConfiguration(name: "LanguageDetector"),
            model: MockProvider(
                responses: ["The text is in French (fr)."],
                toolCallResponses: [([langToolCall], "")]
            ),
            nativeTools: [LanguageDetectionSkill()]
        )

        // Agent 2: Analyzes sentiment using the Sentiment skill-as-tool
        let sentimentToolCall = ToolCall(
            id: "tc-sent",
            name: "analyzeSentiment",
            arguments: #"{"input": "This is wonderful and amazing!"}"#
        )
        let sentimentAgent = Agent(
            configuration: AgentConfiguration(name: "SentimentAnalyzer"),
            model: MockProvider(
                responses: ["Sentiment is positive."],
                toolCallResponses: [([sentimentToolCall], "")]
            ),
            nativeTools: [SentimentSkill()]
        )

        let swarm = Swarm(
            name: "NLPPipeline",
            mode: .sequential,
            members: [langAgent, sentimentAgent]
        )

        let result = try await swarm.run("Analyze this text")
        #expect(result.memberResults.count == 2)

        // Agent 1 should have called detectLanguage
        let langResult = result.memberResults[0]
        #expect(langResult.toolExecutions.count == 1)
        #expect(langResult.toolExecutions[0].toolName == "detectLanguage")
        #expect(langResult.toolExecutions[0].result?.contains("fr") == true)

        // Agent 2 should have called analyzeSentiment
        let sentimentResult = result.memberResults[1]
        #expect(sentimentResult.toolExecutions.count == 1)
        #expect(sentimentResult.toolExecutions[0].toolName == "analyzeSentiment")
        #expect(sentimentResult.toolExecutions[0].succeeded)
    }

    // MARK: - Swarm with MCP Agents

    @Test("Parallel swarm with MCP-connected agents")
    func testSwarmWithMCPAgents() async throws {
        // Set up MCP server 1: echo tool
        let (client1, server1) = await InMemoryTransport.createConnectedPair()
        let echoServer = Server(name: "EchoServer", version: "1.0.0", capabilities: .init(tools: .init()))
        await echoServer.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [
                MCP.Tool(name: "echo", description: "Echo back the input",
                         inputSchema: .object(["type": "object",
                                               "properties": .object(["text": .object(["type": "string"])]),
                                               "required": .array([.string("text")])]))
            ])
        }
        await echoServer.withMethodHandler(CallTool.self) { params in
            let text = params.arguments?["text"]?.stringValue ?? "no input"
            return CallTool.Result(content: [.text("ECHO: \(text)")])
        }
        Task { try await echoServer.start(transport: server1) }
        try await Task.sleep(for: .milliseconds(100))

        // Set up MCP server 2: uppercase tool
        let (client2, server2) = await InMemoryTransport.createConnectedPair()
        let upperServer = Server(name: "UpperServer", version: "1.0.0", capabilities: .init(tools: .init()))
        await upperServer.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [
                MCP.Tool(name: "uppercase", description: "Uppercase text",
                         inputSchema: .object(["type": "object",
                                               "properties": .object(["text": .object(["type": "string"])]),
                                               "required": .array([.string("text")])]))
            ])
        }
        await upperServer.withMethodHandler(CallTool.self) { params in
            let text = params.arguments?["text"]?.stringValue ?? ""
            return CallTool.Result(content: [.text(text.uppercased())])
        }
        Task { try await upperServer.start(transport: server2) }
        try await Task.sleep(for: .milliseconds(100))

        // Agent 1: uses echo MCP server
        let echoManager = MCPManager()
        try await echoManager.connect(name: "echo", transport: client1)

        let echoToolCall = ToolCall(id: "tc-echo", name: "echo", arguments: #"{"text": "hello"}"#)
        let echoAgent = Agent(
            configuration: AgentConfiguration(name: "EchoAgent"),
            model: MockProvider(
                responses: ["Echo result received."],
                toolCallResponses: [([echoToolCall], "")]
            ),
            mcpManager: echoManager
        )

        // Agent 2: uses uppercase MCP server
        let upperManager = MCPManager()
        try await upperManager.connect(name: "upper", transport: client2)

        let upperToolCall = ToolCall(id: "tc-upper", name: "uppercase", arguments: #"{"text": "hello"}"#)
        let upperAgent = Agent(
            configuration: AgentConfiguration(name: "UpperAgent"),
            model: MockProvider(
                responses: ["Uppercase result received."],
                toolCallResponses: [([upperToolCall], "")]
            ),
            mcpManager: upperManager
        )

        let swarm = Swarm(
            name: "MCPSwarm",
            mode: .parallel,
            members: [echoAgent, upperAgent]
        )

        let result = try await swarm.run("Process text")
        #expect(result.memberResults.count == 2)

        // Check that MCP tools were called successfully
        var foundEcho = false
        var foundUpper = false
        for memberResult in result.memberResults {
            #expect(memberResult.status == .completed)
            for exec in memberResult.toolExecutions {
                if exec.toolName == "echo" {
                    #expect(exec.result == "ECHO: hello")
                    foundEcho = true
                }
                if exec.toolName == "uppercase" {
                    #expect(exec.result == "HELLO")
                    foundUpper = true
                }
            }
        }
        #expect(foundEcho)
        #expect(foundUpper)

        // Cleanup
        await echoManager.disconnect(name: "echo")
        await upperManager.disconnect(name: "upper")
        await echoServer.stop()
        await upperServer.stop()
    }

    // MARK: - Autonomous Swarm with Tool Delegation

    @Test("Autonomous swarm: leader delegates to tool-equipped agents")
    func testAutonomousSwarmWithToolAgents() async throws {
        // Worker 1: has a calculator tool
        let calcToolCall = ToolCall(id: "tc-1", name: "multiply", arguments: #"{"a": 6, "b": 7}"#)
        let mathWorker = Agent(
            id: "math-worker",
            configuration: AgentConfiguration(name: "MathWorker"),
            model: MockProvider(
                responses: ["The product of 6 and 7 is 42."],
                toolCallResponses: [([calcToolCall], "")]
            ),
            tools: [
                Tool(name: "multiply", description: "Multiply two numbers", parameters: JSONSchema(
                    properties: ["a": .number(), "b": .number()],
                    required: ["a", "b"]
                )) { args, _ in
                    struct MulArgs: Decodable { let a: Double; let b: Double }
                    let parsed = try JSONDecoder().decode(MulArgs.self, from: Data(args.utf8))
                    return String(parsed.a * parsed.b)
                }
            ]
        )

        // Leader delegates to math-worker
        let leader = Agent(
            configuration: AgentConfiguration(name: "Leader"),
            model: MockProvider(responses: ["DELEGATE:math-worker:Calculate 6 times 7"])
        )

        let swarm = Swarm(
            name: "AutoDelegation",
            mode: .autonomous,
            leader: leader,
            members: [mathWorker]
        )

        let result = try await swarm.run("What is 6 times 7?")
        #expect(!result.memberResults.isEmpty)

        // The math worker should have been delegated to and called its tool
        let workerResult = result.memberResults[0]
        #expect(workerResult.toolExecutions.count == 1)
        #expect(workerResult.toolExecutions[0].toolName == "multiply")
        #expect(workerResult.toolExecutions[0].result == "42.0")
    }

    // MARK: - Routed Swarm with Mixed Skills and Tools

    @Test("Routed swarm dispatches to agents with different capabilities")
    func testRoutedSwarmWithMixedCapabilities() async throws {
        // NLP agent with language + sentiment skills
        let langToolCall = ToolCall(
            id: "tc-lang",
            name: "detectLanguage",
            arguments: #"{"input": "Hello world, how are you doing today?"}"#
        )
        let nlpAgent = Agent(
            id: "nlp",
            configuration: AgentConfiguration(name: "NLPAgent"),
            model: MockProvider(
                responses: ["Language detected: English."],
                toolCallResponses: [([langToolCall], "")]
            ),
            nativeTools: [LanguageDetectionSkill(), SentimentSkill()]
        )

        // Shell agent with shell skill
        let shellToolCall = ToolCall(
            id: "tc-shell",
            name: "runShellCommand",
            arguments: #"{"input": "echo hello"}"#
        )
        let shellAgent = Agent(
            id: "shell",
            configuration: AgentConfiguration(name: "ShellAgent"),
            model: MockProvider(
                responses: ["Command executed successfully."],
                toolCallResponses: [([shellToolCall], "")]
            ),
            nativeTools: [ShellSkill(allowedCommands: ["echo", "date"])]
        )

        let swarm = Swarm(
            name: "CapabilityRouter",
            mode: .route { input in
                if input.lowercased().contains("language") || input.lowercased().contains("sentiment") {
                    return "nlp"
                } else if input.lowercased().contains("command") || input.lowercased().contains("shell") {
                    return "shell"
                }
                return nil
            },
            members: [nlpAgent, shellAgent]
        )

        // Route to NLP agent
        let nlpResult = try await swarm.run("Detect the language of this text")
        #expect(nlpResult.memberResults.count == 1)
        #expect(nlpResult.memberResults[0].toolExecutions.count == 1)
        #expect(nlpResult.memberResults[0].toolExecutions[0].toolName == "detectLanguage")
        #expect(nlpResult.memberResults[0].toolExecutions[0].result?.contains("en") == true)

        // Route to Shell agent
        let shellResult = try await swarm.run("Run a shell command")
        #expect(shellResult.memberResults.count == 1)
        #expect(shellResult.memberResults[0].toolExecutions.count == 1)
        #expect(shellResult.memberResults[0].toolExecutions[0].toolName == "runShellCommand")
        #expect(shellResult.memberResults[0].toolExecutions[0].result?.contains("hello") == true)
    }

    // MARK: - Agent with Multiple Tool Types (Skills + Custom + MCP)

    @Test("Single agent with skills, custom tools, and MCP tools all at once")
    func testAgentWithAllToolTypes() async throws {
        // MCP server
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()
        let server = Server(name: "TimestampServer", version: "1.0.0", capabilities: .init(tools: .init()))
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [
                MCP.Tool(name: "timestamp", description: "Get current timestamp",
                         inputSchema: .object(["type": "object"]))
            ])
        }
        await server.withMethodHandler(CallTool.self) { _ in
            CallTool.Result(content: [.text("2026-02-14T12:00:00Z")])
        }
        Task { try await server.start(transport: serverTransport) }
        try await Task.sleep(for: .milliseconds(100))

        let mcpManager = MCPManager()
        try await mcpManager.connect(name: "time", transport: clientTransport)

        // Agent calls 3 tools in sequence: custom, skill, MCP
        let customToolCall = ToolCall(id: "tc-1", name: "reverse", arguments: #"{"text": "hello"}"#)
        let skillToolCall = ToolCall(id: "tc-2", name: "detectLanguage", arguments: #"{"input": "Bonjour"}"#)
        let mcpToolCall = ToolCall(id: "tc-3", name: "timestamp", arguments: "{}")

        let agent = Agent(
            configuration: AgentConfiguration(name: "MultiTool"),
            model: MockProvider(
                responses: ["All tools called successfully."],
                toolCallResponses: [([customToolCall, skillToolCall, mcpToolCall], "")]
            ),
            tools: [
                Tool(name: "reverse", description: "Reverse a string") { args, _ in
                    struct Args: Decodable { let text: String }
                    let parsed = try JSONDecoder().decode(Args.self, from: Data(args.utf8))
                    return String(parsed.text.reversed())
                }
            ],
            nativeTools: [LanguageDetectionSkill()],
            mcpManager: mcpManager
        )

        let result = try await agent.run("Use all three tools")
        #expect(result.status == .completed)
        #expect(result.toolExecutions.count == 3)

        // Verify each tool type worked
        let reverseExec = result.toolExecutions.first(where: { $0.toolName == "reverse" })
        #expect(reverseExec?.result == "olleh")

        let langExec = result.toolExecutions.first(where: { $0.toolName == "detectLanguage" })
        #expect(langExec?.result?.contains("fr") == true)

        let timestampExec = result.toolExecutions.first(where: { $0.toolName == "timestamp" })
        #expect(timestampExec?.result == "2026-02-14T12:00:00Z")

        await mcpManager.disconnect(name: "time")
        await server.stop()
    }

    // MARK: - Swarm Metrics Aggregation with Tools

    @Test("Swarm correctly aggregates metrics from agents with tool calls")
    func testSwarmMetricsWithTools() async throws {
        let toolCall1 = ToolCall(id: "tc-1", name: "noop1", arguments: "{}")
        let toolCall2 = ToolCall(id: "tc-2", name: "noop2", arguments: "{}")

        let agent1 = Agent(
            configuration: AgentConfiguration(name: "Agent1"),
            model: MockProvider(
                responses: ["Done."],
                toolCallResponses: [([toolCall1], "")]
            ),
            tools: [Tool(name: "noop1", description: "No-op") { _, _ in "ok" }]
        )

        let agent2 = Agent(
            configuration: AgentConfiguration(name: "Agent2"),
            model: MockProvider(
                responses: ["Done."],
                toolCallResponses: [([toolCall2], "")]
            ),
            tools: [Tool(name: "noop2", description: "No-op") { _, _ in "ok" }]
        )

        let swarm = Swarm(
            name: "MetricSwarm",
            mode: .parallel,
            members: [agent1, agent2]
        )

        let result = try await swarm.run("Go")
        #expect(result.metrics.modelCalls >= 4) // 2 agents x 2 calls each (tool call + final)
        #expect(result.metrics.toolCalls == 2) // 1 tool call per agent
        #expect(result.metrics.totalTokens > 0)
    }

    // MARK: - Shell Skill in Swarm

    @Test("Sequential swarm with shell skill executes real commands")
    func testSequentialSwarmWithShellSkill() async throws {
        // Agent 1: runs echo
        let echoCall = ToolCall(id: "tc-1", name: "runShellCommand", arguments: #"{"input": "echo 'step1'"}"#)
        let step1 = Agent(
            configuration: AgentConfiguration(name: "Step1"),
            model: MockProvider(
                responses: ["Step 1 complete."],
                toolCallResponses: [([echoCall], "")]
            ),
            nativeTools: [ShellSkill(allowedCommands: ["echo"])]
        )

        // Agent 2: runs date
        let dateCall = ToolCall(id: "tc-2", name: "runShellCommand", arguments: #"{"input": "date +%Y"}"#)
        let step2 = Agent(
            configuration: AgentConfiguration(name: "Step2"),
            model: MockProvider(
                responses: ["Step 2 complete."],
                toolCallResponses: [([dateCall], "")]
            ),
            nativeTools: [ShellSkill(allowedCommands: ["date"])]
        )

        let swarm = Swarm(
            name: "ShellPipeline",
            mode: .sequential,
            members: [step1, step2]
        )

        let result = try await swarm.run("Run shell commands")
        #expect(result.memberResults.count == 2)
        #expect(result.memberResults[0].toolExecutions[0].result?.contains("step1") == true)
        #expect(result.memberResults[1].toolExecutions[0].result?.contains("2026") == true)
    }

    // MARK: - Entity Extraction + Tokenization in Swarm

    @Test("Parallel swarm combines entity extraction and tokenization skills")
    func testParallelNLPSkillSwarm() async throws {
        let entityCall = ToolCall(
            id: "tc-ent",
            name: "extractEntities",
            arguments: #"{"input": "Tim Cook announced Apple M4 at Cupertino."}"#
        )
        let entityAgent = Agent(
            configuration: AgentConfiguration(name: "EntityExtractor"),
            model: MockProvider(
                responses: ["Found entities: Tim Cook, Apple, Cupertino."],
                toolCallResponses: [([entityCall], "")]
            ),
            nativeTools: [EntityExtractionSkill()]
        )

        let tokenCall = ToolCall(
            id: "tc-tok",
            name: "tokenize",
            arguments: #"{"input": "Hello world. How are you?", "unit": "sentence"}"#
        )
        let tokenAgent = Agent(
            configuration: AgentConfiguration(name: "Tokenizer"),
            model: MockProvider(
                responses: ["Tokenized into 2 sentences."],
                toolCallResponses: [([tokenCall], "")]
            ),
            nativeTools: [TokenizationSkill()]
        )

        let swarm = Swarm(
            name: "NLPAnalysis",
            mode: .parallel,
            members: [entityAgent, tokenAgent]
        )

        let result = try await swarm.run("Analyze text")
        #expect(result.memberResults.count == 2)

        for member in result.memberResults {
            #expect(member.status == .completed)
            #expect(member.toolExecutions.count == 1)
            #expect(member.toolExecutions[0].succeeded)
        }
    }

    // MARK: - Error Handling in Swarm with Tools

    @Test("Swarm handles tool execution errors gracefully")
    func testSwarmHandlesToolErrors() async throws {
        let badToolCall = ToolCall(id: "tc-bad", name: "nonexistent_tool", arguments: "{}")
        let agent = Agent(
            configuration: AgentConfiguration(name: "ErrorAgent"),
            model: MockProvider(
                responses: ["Handled the error."],
                toolCallResponses: [([badToolCall], "")]
            )
        )

        let swarm = Swarm(
            name: "ErrorSwarm",
            mode: .sequential,
            members: [agent]
        )

        let result = try await swarm.run("Try calling a bad tool")
        #expect(result.memberResults.count == 1)
        #expect(result.memberResults[0].status == .completed)
        // The tool execution should record the error
        #expect(result.memberResults[0].toolExecutions[0].error != nil)
        #expect(result.memberResults[0].toolExecutions[0].error?.contains("not found") == true)
    }

    // MARK: - Multi-Tool Calling Agent in Swarm

    @Test("Agent calls multiple tools in a single turn within a swarm")
    func testMultiToolCallInSwarm() async throws {
        let tool1Call = ToolCall(id: "tc-1", name: "add", arguments: #"{"a": 1, "b": 2}"#)
        let tool2Call = ToolCall(id: "tc-2", name: "add", arguments: #"{"a": 3, "b": 4}"#)
        let tool3Call = ToolCall(id: "tc-3", name: "add", arguments: #"{"a": 5, "b": 6}"#)

        let agent = Agent(
            configuration: AgentConfiguration(name: "BatchCalc"),
            model: MockProvider(
                responses: ["Results: 3, 7, 11."],
                toolCallResponses: [([tool1Call, tool2Call, tool3Call], "")]
            ),
            tools: [
                Tool(name: "add", description: "Add two numbers", parameters: JSONSchema(
                    properties: ["a": .number(), "b": .number()],
                    required: ["a", "b"]
                )) { args, _ in
                    struct AddArgs: Decodable { let a: Double; let b: Double }
                    let parsed = try JSONDecoder().decode(AddArgs.self, from: Data(args.utf8))
                    return String(parsed.a + parsed.b)
                }
            ]
        )

        let swarm = Swarm(name: "BatchSwarm", mode: .sequential, members: [agent])
        let result = try await swarm.run("Add 1+2, 3+4, 5+6")

        let memberResult = result.memberResults[0]
        #expect(memberResult.toolExecutions.count == 3)
        #expect(memberResult.toolExecutions[0].result == "3.0")
        #expect(memberResult.toolExecutions[1].result == "7.0")
        #expect(memberResult.toolExecutions[2].result == "11.0")
    }
}
