import Foundation
import SBBender

// ============================================================================
// SBBender Swarm Demo — Real MLX Local LLM + Apple Skills
// ============================================================================
//
// This demo creates a parallel swarm of 3 specialized agents:
//   1. Analyst Agent    — Summarizes and analyzes text using Qwen3-4B
//   2. Linguist Agent   — Detects language, sentiment, entities (Apple NLP skills)
//   3. Creative Agent   — Rewrites text creatively using Qwen3-4B
//
// All agents run in PARALLEL on real local LLM inference (MLX on Apple Silicon).
// ============================================================================

@main
struct SwarmDemo {
    static func main() async throws {
        let startTime = CFAbsoluteTimeGetCurrent()

        print("""
        ╔══════════════════════════════════════════════════════════════╗
        ║           SBBender — Real MLX Swarm Demo                   ║
        ║     3 Agents · Parallel Execution · Apple Silicon          ║
        ╚══════════════════════════════════════════════════════════════╝
        """)

        // The input text our swarm will process
        let inputText = """
        Apple announced today that its new M4 Ultra chip delivers \
        unprecedented performance for AI workloads. CEO Tim Cook \
        presented the results at Apple Park in Cupertino, California. \
        The chip features a 32-core Neural Engine capable of 38 TOPS, \
        making on-device machine learning faster than ever. \
        Developers at Google, Microsoft, and Meta have already begun \
        optimizing their frameworks for the new silicon. \
        This is a game-changer for the entire industry.
        """

        print("📄 Input text:")
        print("   \(inputText)\n")

        // ── Step 1: Run Apple NLP Skills directly (no LLM needed) ──────────

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("  Phase 1: Apple NLP Skills (instant, no LLM)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        let langSkill = LanguageDetectionSkill()
        let sentimentSkill = SentimentSkill()
        let entitySkill = EntityExtractionSkill()
        let tokenSkill = TokenizationSkill()

        // Run all skills in parallel
        async let langResult = langSkill.execute(input: .text(inputText))
        async let sentimentResult = sentimentSkill.execute(input: .text(inputText))
        async let entityResult = entitySkill.execute(input: .text(inputText))
        async let tokenResult = tokenSkill.execute(input: NativeToolInput(
            text: inputText,
            parameters: ["unit": "sentence"]
        ))

        let lang = try await langResult
        let sentiment = try await sentimentResult
        let entities = try await entityResult
        let tokens = try await tokenResult

        print("""

        🌍 Language:   \(lang.output) (confidence: \(String(format: "%.1f%%", lang.confidence * 100)), \(String(format: "%.3f", lang.latency * 1000))ms)
        😊 Sentiment:  \(sentiment.structuredData["label"] ?? "?") (score: \(sentiment.structuredData["score"] ?? "?"), \(String(format: "%.3f", sentiment.latency * 1000))ms)
        👤 People:     \(entities.structuredData["people"] ?? "none")
        🏢 Orgs:       \(entities.structuredData["organizations"] ?? "none")
        📍 Places:     \(entities.structuredData["places"] ?? "none")
        📝 Sentences:  \(tokens.structuredData["count"] ?? "?") (\(String(format: "%.3f", tokens.latency * 1000))ms)
        """)

        // ── Step 2: Load MLX Model ─────────────────────────────────────────

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("  Phase 2: Loading Qwen3-4B-4bit via MLX...")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        let modelStart = CFAbsoluteTimeGetCurrent()
        let mlx = MLXProvider(modelID: "mlx-community/Qwen3-4B-4bit")
        let _ = try await mlx.loadModel()
        let modelLoadTime = CFAbsoluteTimeGetCurrent() - modelStart
        print("  ✅ Model loaded in \(String(format: "%.2f", modelLoadTime))s\n")

        // ── Step 3: Create Specialized Agents ──────────────────────────────

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("  Phase 3: Parallel Swarm — 3 Agents, Same Model")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Agent 1: Analyst — summarize and extract key points
        let analyst = Agent(
            configuration: AgentConfiguration(
                name: "Analyst",
                instructions: """
                You are a precise analyst. Given text, provide:
                1. A one-sentence summary
                2. Three key takeaways as bullet points
                Be concise. No fluff.
                """,
                generationConfig: GenerationConfig(maxTokens: 300, temperature: 0.3)
            ),
            model: mlx
        )

        // Agent 2: Linguist — deep language analysis with Apple skills
        let linguist = Agent(
            configuration: AgentConfiguration(
                name: "Linguist",
                instructions: """
                You are a linguist. Analyze the text for:
                1. Writing style (formal/informal, tone)
                2. Vocabulary complexity
                3. Rhetorical devices used
                Keep it to 3-4 sentences.
                """,
                generationConfig: GenerationConfig(maxTokens: 250, temperature: 0.4)
            ),
            model: mlx,
            nativeTools: [langSkill, sentimentSkill, entitySkill]
        )

        // Agent 3: Creative — rewrite with flair
        let creative = Agent(
            configuration: AgentConfiguration(
                name: "Creative",
                instructions: """
                You are a creative writer. Rewrite the given text as a dramatic \
                movie trailer narration. Make it exciting and cinematic. \
                Keep it to 3-4 sentences max.
                """,
                generationConfig: GenerationConfig(maxTokens: 250, temperature: 0.9)
            ),
            model: mlx
        )

        // ── Step 4: Run the Swarm in Parallel ──────────────────────────────

        let swarm = Swarm(
            name: "AnalysisSwarm",
            mode: .parallel,
            members: [analyst, linguist, creative]
        )

        print("  🚀 Launching 3 agents in parallel...\n")
        let swarmStart = CFAbsoluteTimeGetCurrent()
        let swarmResult = try await swarm.run(inputText)
        let swarmTime = CFAbsoluteTimeGetCurrent() - swarmStart

        // ── Step 5: Display Results ────────────────────────────────────────

        for (i, memberResult) in swarmResult.memberResults.enumerated() {
            let agentName: String
            switch i {
            case 0: agentName = "Analyst"
            case 1: agentName = "Linguist"
            case 2: agentName = "Creative"
            default: agentName = "Agent \(i)"
            }

            print("┌──────────────────────────────────────────────────────────────")
            print("│ 🤖 \(agentName) Agent")
            print("│ Status: \(memberResult.status) | Tokens: \(memberResult.metrics.totalTokens) | Latency: \(String(format: "%.2f", memberResult.metrics.totalLatency))s")
            print("├──────────────────────────────────────────────────────────────")
            let lines = memberResult.content.split(separator: "\n", omittingEmptySubsequences: false)
            for line in lines {
                print("│  \(line)")
            }
            print("└──────────────────────────────────────────────────────────────\n")
        }

        // ── Step 6: Sequential Swarm Demo ──────────────────────────────────

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("  Phase 4: Sequential Chain — Output Feeds Next Agent")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Create a chain: Summarizer → Translator-style rewriter
        let summarizer = Agent(
            configuration: AgentConfiguration(
                name: "Summarizer",
                instructions: "Summarize the input in exactly one sentence. Nothing else.",
                generationConfig: GenerationConfig(maxTokens: 100, temperature: 0.2)
            ),
            model: mlx
        )

        let expander = Agent(
            configuration: AgentConfiguration(
                name: "Expander",
                instructions: """
                Take the one-sentence summary you receive and expand it into \
                exactly 3 bullet points with more detail. Start each bullet with "•".
                """,
                generationConfig: GenerationConfig(maxTokens: 200, temperature: 0.5)
            ),
            model: mlx
        )

        let seqSwarm = Swarm(
            name: "ChainSwarm",
            mode: .sequential,
            members: [summarizer, expander]
        )

        print("  🔗 Running sequential chain: Summarizer → Expander...\n")
        let seqStart = CFAbsoluteTimeGetCurrent()
        let seqResult = try await seqSwarm.run(inputText)
        let seqTime = CFAbsoluteTimeGetCurrent() - seqStart

        for (i, memberResult) in seqResult.memberResults.enumerated() {
            let agentName = i == 0 ? "Summarizer" : "Expander"
            print("┌──────────────────────────────────────────────────────────────")
            print("│ 🔗 \(agentName) (step \(i + 1)/2)")
            print("├──────────────────────────────────────────────────────────────")
            let lines = memberResult.content.split(separator: "\n", omittingEmptySubsequences: false)
            for line in lines {
                print("│  \(line)")
            }
            print("└──────────────────────────────────────────────────────────────\n")
        }

        // ── Step 7: Routed Swarm Demo ──────────────────────────────────────

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("  Phase 5: Routed Swarm — Dynamic Agent Selection")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        let techAgent = Agent(
            id: "tech",
            configuration: AgentConfiguration(
                name: "TechExpert",
                instructions: "You are a tech expert. Explain technical concepts clearly in 2-3 sentences.",
                generationConfig: GenerationConfig(maxTokens: 150, temperature: 0.3)
            ),
            model: mlx
        )

        let poetAgent = Agent(
            id: "poet",
            configuration: AgentConfiguration(
                name: "Poet",
                instructions: "You are a poet. Respond with a short 4-line poem about the topic.",
                generationConfig: GenerationConfig(maxTokens: 150, temperature: 0.9)
            ),
            model: mlx
        )

        let jokeAgent = Agent(
            id: "joke",
            configuration: AgentConfiguration(
                name: "Comedian",
                instructions: "You are a comedian. Respond with a short joke about the topic. One-liner.",
                generationConfig: GenerationConfig(maxTokens: 100, temperature: 0.8)
            ),
            model: mlx
        )

        let routedSwarm = Swarm(
            name: "RouterSwarm",
            mode: .route { input in
                if input.lowercased().contains("poem") || input.lowercased().contains("poetry") {
                    return "poet"
                } else if input.lowercased().contains("joke") || input.lowercased().contains("funny") {
                    return "joke"
                } else {
                    return "tech"
                }
            },
            members: [techAgent, poetAgent, jokeAgent]
        )

        let routeInputs = [
            ("Tell me about neural engines", "tech"),
            ("Write me a poem about AI chips", "poet"),
            ("Tell me something funny about processors", "joke"),
        ]

        for (query, expectedRoute) in routeInputs {
            print("  🔀 Query: \"\(query)\" → routed to: \(expectedRoute)")
            let routeStart = CFAbsoluteTimeGetCurrent()
            let routeResult = try await routedSwarm.run(query)
            let routeTime = CFAbsoluteTimeGetCurrent() - routeStart

            print("┌──────────────────────────────────────────────────────────────")
            print("│ 🎯 \(expectedRoute.capitalized) Agent (\(String(format: "%.2f", routeTime))s)")
            print("├──────────────────────────────────────────────────────────────")
            let lines = routeResult.content.split(separator: "\n", omittingEmptySubsequences: false)
            for line in lines {
                print("│  \(line)")
            }
            print("└──────────────────────────────────────────────────────────────\n")
        }

        // ── Step 6: Tool Calling Agent Demo ──────────────────────────────

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("  Phase 6: Agent with Tools + Skills (Autonomous Calling)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Calculator tool
        let calcTool = Tool(
            name: "calculate",
            description: "Evaluate a math expression",
            parameters: JSONSchema(
                properties: ["expression": .string("Math expression to evaluate, e.g. '15 * 37'")],
                required: ["expression"]
            )
        ) { arguments, _ in
            struct Args: Decodable { let expression: String }
            let args = try JSONDecoder().decode(Args.self, from: Data(arguments.utf8))
            // Simple eval for demo: parse basic arithmetic
            let expr = NSExpression(format: args.expression)
            let result = expr.expressionValue(with: nil, context: nil) as? NSNumber
            return result.map { String(describing: $0) } ?? "Error: could not evaluate '\(args.expression)'"
        }

        // Agent with skills + tools — MLX will inject tool definitions into the prompt
        let toolAgent = Agent(
            configuration: AgentConfiguration(
                name: "SmartAssistant",
                instructions: """
                You are a smart assistant with tools and Apple-native skills.
                Use the 'calculate' tool for any math. Use 'detectLanguage' for language detection.
                Use 'analyzeSentiment' for sentiment analysis.
                Always use tools when available instead of guessing.
                """,
                generationConfig: GenerationConfig(maxTokens: 500, temperature: 0.3)
            ),
            model: mlx,
            tools: [calcTool],
            nativeTools: [langSkill, sentimentSkill, entitySkill]
        )

        print("  🛠️  Agent has \(1 + 3) tools: calculate + 3 NLP skills as tools")
        print("  🧪 Asking: 'What is 42 * 17? Also detect the language of: Bonjour le monde'\n")

        let toolStart = CFAbsoluteTimeGetCurrent()
        let toolResult = try await toolAgent.run(
            "What is 42 * 17? Also detect the language of: Bonjour le monde"
        )
        let toolTime = CFAbsoluteTimeGetCurrent() - toolStart

        print("┌──────────────────────────────────────────────────────────────")
        print("│ 🛠️  SmartAssistant (\(String(format: "%.2f", toolTime))s)")
        print("│ Tool calls: \(toolResult.toolExecutions.count)")
        for exec in toolResult.toolExecutions {
            let status = exec.error == nil ? "✅" : "❌"
            print("│   \(status) \(exec.toolName): \(exec.result ?? exec.error ?? "no output")")
        }
        print("├──────────────────────────────────────────────────────────────")
        let toolLines = toolResult.content.split(separator: "\n", omittingEmptySubsequences: false)
        for line in toolLines {
            print("│  \(line)")
        }
        print("└──────────────────────────────────────────────────────────────\n")

        // ── Final Summary ──────────────────────────────────────────────────

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        let totalModelCalls = swarmResult.metrics.modelCalls + seqResult.metrics.modelCalls + toolResult.metrics.modelCalls
        let totalTokens = swarmResult.metrics.totalTokens + seqResult.metrics.totalTokens + toolResult.metrics.totalTokens

        print("""
        ══════════════════════════════════════════════════════════════
        📊 Demo Complete
        ──────────────────────────────────────────────────────────────
        Model:              Qwen3-4B-4bit (MLX, on-device)
        Model load time:    \(String(format: "%.2f", modelLoadTime))s
        Parallel swarm:     \(String(format: "%.2f", swarmTime))s (3 agents)
        Sequential chain:   \(String(format: "%.2f", seqTime))s (2 agents)
        Tool-calling agent: \(String(format: "%.2f", toolTime))s (\(toolResult.toolExecutions.count) tool calls)
        Total model calls:  \(totalModelCalls)
        Total tokens:       \(totalTokens)
        Total runtime:      \(String(format: "%.2f", totalTime))s
        ══════════════════════════════════════════════════════════════
        """)
    }
}
