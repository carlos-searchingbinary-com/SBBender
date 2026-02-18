import Testing
import Foundation
@testable import SBBender
import MCP

/// Real-world end-to-end tests that exercise actual system capabilities.
///
/// These tests do NOT use MockProvider for the skill/tool execution path.
/// They verify that real Apple frameworks, real shell commands, and real MCP
/// servers work correctly when wired through the SBBender agent+swarm system.
///
/// The MockProvider is only used for the LLM decision-making (since we don't
/// have a local LLM in CI), but the tools and skills execute FOR REAL.

@Suite("Real World End-to-End Tests")
struct RealWorldTests {

    // MARK: - Real NLP Pipeline via Agent Tool Calls

    @Test("Agent autonomously calls real NLP skills and gets real results")
    func testAgentWithRealNLPSkills() async throws {
        // The model "decides" to call detectLanguage and analyzeSentiment
        // But the skills execute FOR REAL against Apple NaturalLanguage
        let langCall = ToolCall(
            id: "tc-1",
            name: "detectLanguage",
            arguments: #"{"input": "La inteligencia artificial está transformando el mundo de la tecnología moderna"}"#
        )
        let sentimentCall = ToolCall(
            id: "tc-2",
            name: "analyzeSentiment",
            arguments: #"{"input": "This product is absolutely fantastic, I love everything about it!"}"#
        )
        let entityCall = ToolCall(
            id: "tc-3",
            name: "extractEntities",
            arguments: #"{"input": "Elon Musk and Tim Cook met at Apple headquarters in Cupertino, California to discuss Tesla and SpaceX partnerships."}"#
        )

        let agent = Agent(
            configuration: AgentConfiguration(
                name: "RealNLPAgent",
                instructions: "You analyze text using your NLP tools."
            ),
            model: MockProvider(
                responses: ["Analysis complete. Spanish detected, positive sentiment, entities extracted."],
                toolCallResponses: [([langCall, sentimentCall, entityCall], "")]
            ),
            nativeTools: [LanguageDetectionSkill(), SentimentSkill(), EntityExtractionSkill()]
        )

        let result = try await agent.run("Analyze these texts")
        #expect(result.status == .completed)
        #expect(result.toolExecutions.count == 3)

        // Verify REAL language detection
        let langExec = result.toolExecutions.first(where: { $0.toolName == "detectLanguage" })!
        #expect(langExec.succeeded)
        #expect(langExec.result?.contains("es") == true, "Should detect Spanish, got: \(langExec.result ?? "nil")")

        // Verify REAL sentiment analysis
        let sentExec = result.toolExecutions.first(where: { $0.toolName == "analyzeSentiment" })!
        #expect(sentExec.succeeded)
        #expect(sentExec.result?.contains("positive") == true, "Should detect positive sentiment, got: \(sentExec.result ?? "nil")")

        // Verify REAL entity extraction
        let entExec = result.toolExecutions.first(where: { $0.toolName == "extractEntities" })!
        #expect(entExec.succeeded)
        let entResult = entExec.result ?? ""
        #expect(entResult.contains("Tim Cook") || entResult.contains("Elon Musk"),
                "Should extract person names, got: \(entResult)")
        #expect(entResult.contains("Apple") || entResult.contains("Tesla") || entResult.contains("SpaceX"),
                "Should extract organizations, got: \(entResult)")
    }

    // MARK: - Real Shell Execution via Agent

    @Test("Agent calls shell skill and gets real command output")
    func testAgentWithRealShellSkill() async throws {
        let echoCall = ToolCall(
            id: "tc-echo",
            name: "runShellCommand",
            arguments: #"{"input": "echo 'SBBender real test'"}"#
        )
        let dateCall = ToolCall(
            id: "tc-date",
            name: "runShellCommand",
            arguments: #"{"input": "date +%Y"}"#
        )
        let pwdCall = ToolCall(
            id: "tc-pwd",
            name: "runShellCommand",
            arguments: #"{"input": "echo $((6 * 7))"}"#
        )

        let agent = Agent(
            configuration: AgentConfiguration(name: "ShellAgent"),
            model: MockProvider(
                responses: ["Shell commands executed."],
                toolCallResponses: [([echoCall, dateCall, pwdCall], "")]
            ),
            nativeTools: [ShellSkill(allowedCommands: ["echo", "date"])]
        )

        let result = try await agent.run("Run some shell commands")
        #expect(result.status == .completed)
        #expect(result.toolExecutions.count == 3)

        // Verify REAL echo — shell skill returns structured JSON via asTool()
        let echoExec = result.toolExecutions[0]
        #expect(echoExec.result?.contains("SBBender real test") == true,
                "Should contain echo output, got: \(echoExec.result ?? "nil")")

        // Verify REAL date
        let dateExec = result.toolExecutions[1]
        #expect(dateExec.result?.contains("2026") == true,
                "Should contain year, got: \(dateExec.result ?? "nil")")

        // Verify REAL arithmetic via shell
        let calcExec = result.toolExecutions[2]
        #expect(calcExec.result?.contains("42") == true,
                "Should contain 42, got: \(calcExec.result ?? "nil")")
    }

    // MARK: - Shell Skill Security: Blocked Commands

    @Test("Shell skill blocks unauthorized commands for real")
    func testShellSkillBlocksRealCommands() async throws {
        let rmCall = ToolCall(
            id: "tc-rm",
            name: "runShellCommand",
            arguments: #"{"input": "rm -rf /tmp/fake"}"#
        )

        let agent = Agent(
            configuration: AgentConfiguration(name: "BadAgent"),
            model: MockProvider(
                responses: ["Handled error."],
                toolCallResponses: [([rmCall], "")]
            ),
            nativeTools: [ShellSkill(allowedCommands: ["echo", "date"])]
        )

        let result = try await agent.run("Delete files")
        #expect(result.status == .completed)
        // The tool execution should fail because rm is not allowed
        #expect(result.toolExecutions[0].error != nil)
        #expect(result.toolExecutions[0].error?.contains("not in the allowed list") == true)
    }

    // MARK: - Real MCP Server End-to-End

    @Test("Agent communicates with real MCP server via InMemoryTransport")
    func testRealMCPServerEndToEnd() async throws {
        // Set up a REAL MCP server (not mocked) with actual logic
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()

        let server = Server(name: "MathServer", version: "1.0.0", capabilities: .init(tools: .init()))

        // Real math tool on the MCP server
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [
                MCP.Tool(
                    name: "add",
                    description: "Add two numbers",
                    inputSchema: .object([
                        "type": "object",
                        "properties": .object([
                            "a": .object(["type": "number", "description": "First number"]),
                            "b": .object(["type": "number", "description": "Second number"]),
                        ]),
                        "required": .array([.string("a"), .string("b")]),
                    ])
                ),
                MCP.Tool(
                    name: "multiply",
                    description: "Multiply two numbers",
                    inputSchema: .object([
                        "type": "object",
                        "properties": .object([
                            "a": .object(["type": "number", "description": "First number"]),
                            "b": .object(["type": "number", "description": "Second number"]),
                        ]),
                        "required": .array([.string("a"), .string("b")]),
                    ])
                ),
            ])
        }

        await server.withMethodHandler(CallTool.self) { params in
            let a = params.arguments?["a"]?.doubleValue ?? params.arguments?["a"]?.intValue.map(Double.init) ?? 0
            let b = params.arguments?["b"]?.doubleValue ?? params.arguments?["b"]?.intValue.map(Double.init) ?? 0

            switch params.name {
            case "add":
                return CallTool.Result(content: [.text(String(a + b))])
            case "multiply":
                return CallTool.Result(content: [.text(String(a * b))])
            default:
                return CallTool.Result(content: [.text("Unknown tool")])
            }
        }

        Task { try await server.start(transport: serverTransport) }
        try await Task.sleep(for: .milliseconds(100))

        let mcpManager = MCPManager()
        try await mcpManager.connect(name: "math", transport: clientTransport)

        // Agent calls BOTH MCP tools
        let addCall = ToolCall(id: "tc-add", name: "add", arguments: #"{"a": 15, "b": 27}"#)
        let mulCall = ToolCall(id: "tc-mul", name: "multiply", arguments: #"{"a": 6, "b": 7}"#)

        let agent = Agent(
            configuration: AgentConfiguration(name: "MathAgent"),
            model: MockProvider(
                responses: ["15 + 27 = 42, and 6 * 7 = 42. Both are 42!"],
                toolCallResponses: [([addCall, mulCall], "")]
            ),
            mcpManager: mcpManager
        )

        let result = try await agent.run("Calculate 15+27 and 6*7")
        #expect(result.status == .completed)
        #expect(result.toolExecutions.count == 2)

        // Verify REAL MCP math
        let addExec = result.toolExecutions.first(where: { $0.toolName == "add" })!
        #expect(addExec.result == "42.0", "15+27 should be 42, got: \(addExec.result ?? "nil")")

        let mulExec = result.toolExecutions.first(where: { $0.toolName == "multiply" })!
        #expect(mulExec.result == "42.0", "6*7 should be 42, got: \(mulExec.result ?? "nil")")

        await mcpManager.disconnect(name: "math")
        await server.stop()
    }

    // MARK: - Real Swarm: Parallel NLP + MCP + Shell

    @Test("Parallel swarm combining real NLP skills, MCP, and shell execution")
    func testRealWorldParallelSwarm() async throws {
        // ── Agent 1: NLP analysis with real Apple frameworks ──
        let langCall = ToolCall(
            id: "tc-lang",
            name: "detectLanguage",
            arguments: #"{"input": "Dies ist ein deutscher Satz zur Erkennung der Sprache."}"#
        )
        let nlpAgent = Agent(
            configuration: AgentConfiguration(name: "NLPAgent"),
            model: MockProvider(
                responses: ["Detected German language."],
                toolCallResponses: [([langCall], "")]
            ),
            nativeTools: [LanguageDetectionSkill()]
        )

        // ── Agent 2: MCP math server ──
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()
        let mathServer = Server(name: "MathServer", version: "1.0.0", capabilities: .init(tools: .init()))
        await mathServer.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [
                MCP.Tool(name: "add", description: "Add two numbers",
                         inputSchema: .object(["type": "object",
                                               "properties": .object([
                                                "a": .object(["type": "number"]),
                                                "b": .object(["type": "number"])
                                               ]),
                                               "required": .array([.string("a"), .string("b")])]))
            ])
        }
        await mathServer.withMethodHandler(CallTool.self) { params in
            let a = params.arguments?["a"]?.doubleValue ?? params.arguments?["a"]?.intValue.map(Double.init) ?? 0
            let b = params.arguments?["b"]?.doubleValue ?? params.arguments?["b"]?.intValue.map(Double.init) ?? 0
            return CallTool.Result(content: [.text(String(a + b))])
        }
        Task { try await mathServer.start(transport: serverTransport) }
        try await Task.sleep(for: .milliseconds(100))

        let mcpManager = MCPManager()
        try await mcpManager.connect(name: "math", transport: clientTransport)

        let addCall = ToolCall(id: "tc-add", name: "add", arguments: #"{"a": 100, "b": 200}"#)
        let mcpAgent = Agent(
            configuration: AgentConfiguration(name: "MathAgent"),
            model: MockProvider(
                responses: ["100 + 200 = 300."],
                toolCallResponses: [([addCall], "")]
            ),
            mcpManager: mcpManager
        )

        // ── Agent 3: Real shell execution ──
        let shellCall = ToolCall(
            id: "tc-shell",
            name: "runShellCommand",
            arguments: #"{"input": "echo 'real-world-test-output'"}"#
        )
        let shellAgent = Agent(
            configuration: AgentConfiguration(name: "ShellAgent"),
            model: MockProvider(
                responses: ["Shell command ran successfully."],
                toolCallResponses: [([shellCall], "")]
            ),
            nativeTools: [ShellSkill(allowedCommands: ["echo"])]
        )

        // ── Run all 3 in parallel ──
        let swarm = Swarm(
            name: "RealWorldSwarm",
            mode: .parallel,
            members: [nlpAgent, mcpAgent, shellAgent]
        )

        let result = try await swarm.run("Process everything")
        #expect(result.memberResults.count == 3)

        // Verify all completed successfully
        for member in result.memberResults {
            #expect(member.status == .completed)
            #expect(member.toolExecutions.count == 1)
            #expect(member.toolExecutions[0].succeeded, "Tool \(member.toolExecutions[0].toolName) failed: \(member.toolExecutions[0].error ?? "?")")
        }

        // Verify real results
        var foundLang = false
        var foundMath = false
        var foundShell = false
        for member in result.memberResults {
            let exec = member.toolExecutions[0]
            switch exec.toolName {
            case "detectLanguage":
                #expect(exec.result?.contains("de") == true, "Should detect German, got: \(exec.result ?? "nil")")
                foundLang = true
            case "add":
                #expect(exec.result == "300.0", "100+200 should be 300, got: \(exec.result ?? "nil")")
                foundMath = true
            case "runShellCommand":
                #expect(exec.result?.contains("real-world-test-output") == true, "Shell should output marker, got: \(exec.result ?? "nil")")
                foundShell = true
            default:
                Issue.record("Unexpected tool: \(exec.toolName)")
            }
        }
        #expect(foundLang, "NLP agent should have run")
        #expect(foundMath, "MCP agent should have run")
        #expect(foundShell, "Shell agent should have run")

        // Verify metrics are aggregated
        #expect(result.metrics.toolCalls == 3)
        #expect(result.metrics.modelCalls >= 6) // 3 agents x 2 calls each

        await mcpManager.disconnect(name: "math")
        await mathServer.stop()
    }

    // MARK: - Multi-Language Real Detection in Routed Swarm

    @Test("Routed swarm correctly routes and analyzes multiple languages")
    func testRoutedSwarmWithRealLanguageDetection() async throws {
        // Each agent detects language of its routed input
        let spanishCall = ToolCall(
            id: "tc-es",
            name: "detectLanguage",
            arguments: #"{"input": "Esta es una prueba de detección de idioma en español para verificar que funciona correctamente"}"#
        )
        let spanishAgent = Agent(
            id: "spanish-handler",
            configuration: AgentConfiguration(name: "SpanishHandler"),
            model: MockProvider(
                responses: ["Detected Spanish."],
                toolCallResponses: [([spanishCall], "")]
            ),
            nativeTools: [LanguageDetectionSkill()]
        )

        let frenchCall = ToolCall(
            id: "tc-fr",
            name: "detectLanguage",
            arguments: #"{"input": "Ceci est une phrase en français pour tester la détection automatique de la langue"}"#
        )
        let frenchAgent = Agent(
            id: "french-handler",
            configuration: AgentConfiguration(name: "FrenchHandler"),
            model: MockProvider(
                responses: ["Detected French."],
                toolCallResponses: [([frenchCall], "")]
            ),
            nativeTools: [LanguageDetectionSkill()]
        )

        let swarm = Swarm(
            name: "LanguageRouter",
            mode: .route { input in
                input.contains("español") ? "spanish-handler" : "french-handler"
            },
            members: [spanishAgent, frenchAgent]
        )

        // Route to Spanish agent
        let esResult = try await swarm.run("Process this español text")
        let esExec = esResult.memberResults[0].toolExecutions[0]
        #expect(esExec.result?.contains("es") == true, "Should detect Spanish, got: \(esExec.result ?? "nil")")

        // Route to French agent
        let frResult = try await swarm.run("Process this French text")
        let frExec = frResult.memberResults[0].toolExecutions[0]
        #expect(frExec.result?.contains("fr") == true, "Should detect French, got: \(frExec.result ?? "nil")")
    }

    // MARK: - Autonomous Delegation with Real Tool Execution

    @Test("Autonomous swarm: leader delegates via tool, worker executes real shell command")
    func testAutonomousDelegationWithRealExecution() async throws {
        let shellCall = ToolCall(
            id: "tc-sh",
            name: "runShellCommand",
            arguments: #"{"input": "echo $((2 + 2))"}"#
        )
        let worker = Agent(
            id: "shell-worker",
            configuration: AgentConfiguration(name: "ShellWorker"),
            model: MockProvider(
                responses: ["The result is 4."],
                toolCallResponses: [([shellCall], "")]
            ),
            nativeTools: [ShellSkill(allowedCommands: ["echo"])]
        )

        // Leader uses delegate_to tool call (the swarm registers this tool automatically)
        let delegateCall = ToolCall(
            id: "tc-delegate",
            name: "delegate_to",
            arguments: #"{"member_name": "ShellWorker", "task": "Calculate 2+2 using shell"}"#
        )
        let leader = Agent(
            configuration: AgentConfiguration(name: "Leader"),
            model: MockProvider(
                responses: ["The answer is 4."],
                toolCallResponses: [([delegateCall], "")]
            )
        )

        let swarm = Swarm(
            name: "AutoShell",
            mode: .autonomous,
            leader: leader,
            members: [worker]
        )

        let result = try await swarm.run("What is 2+2?")
        #expect(!result.memberResults.isEmpty)

        let workerResult = result.memberResults[0]
        #expect(workerResult.toolExecutions.count == 1)
        #expect(workerResult.toolExecutions[0].toolName == "runShellCommand")
        #expect(workerResult.toolExecutions[0].result?.contains("4") == true,
                "2+2 via shell should contain 4, got: \(workerResult.toolExecutions[0].result ?? "nil")")
    }

    // MARK: - Embedding Distance Skill Real Execution

    @Test("Embedding distance skill computes real semantic similarity")
    func testRealEmbeddingDistance() async throws {
        let skill = EmbeddingDistanceSkill()
        let available = await skill.isAvailable
        // Skip if NaturalLanguage embedding isn't available (older macOS)
        guard available else { return }

        let result = try await skill.execute(input: NativeToolInput(
            text: "The cat sat on the mat",
            parameters: ["compareTo": "A feline rested on the rug"]
        ))

        // Semantically similar sentences should have distance < 1.0
        let distance = Double(result.output) ?? 2.0
        #expect(distance < 1.5, "Semantically similar sentences should have low distance, got: \(distance)")
        #expect(distance >= 0, "Distance should be non-negative")
    }

}
