import Testing
import Foundation
@testable import SBBender

/// Integration tests that run a real MLX swarm with Apple NLP skills.
///
/// These tests require:
/// - Apple Silicon (MLX inference)
/// - Metal shaders built (`scripts/build-metallib.sh`)
/// - Qwen3-4B-4bit downloaded in HuggingFace cache
///
/// They are disabled by default (tagged .disabled) since they take ~30s+ to run.
/// Run explicitly with: swift test --filter SwarmIntegrationTests

/// Integration tests with real MLX require Metal shaders that SwiftPM's test
/// runner cannot load (the `.xctest` bundle doesn't include the compiled metallib).
///
/// To run the real demo with MLX:
///   1. `scripts/build-metallib.sh`
///   2. `swift run SwarmDemo`
///
/// The NLP skill tests below run without MLX — they use Apple's NaturalLanguage
/// framework directly and verify real on-device inference (just not LLM inference).

@Suite("Real Apple NLP Integration Tests")
struct RealNLPIntegrationTests {

    static let inputText = """
    Apple announced today that its new M4 Ultra chip delivers \
    unprecedented performance for AI workloads. CEO Tim Cook \
    presented the results at Apple Park in Cupertino, California. \
    The chip features a 32-core Neural Engine capable of 38 TOPS, \
    making on-device machine learning faster than ever. \
    Developers at Google, Microsoft, and Meta have already begun \
    optimizing their frameworks for the new silicon. \
    This is a game-changer for the entire industry.
    """

    @Test("Full NLP pipeline — language, sentiment, entities, tokens in parallel")
    func testFullNLPPipeline() async throws {
        let langSkill = LanguageDetectionSkill()
        let sentimentSkill = SentimentSkill()
        let entitySkill = EntityExtractionSkill()
        let tokenSkill = TokenizationSkill()

        async let lang = langSkill.execute(input: .text(Self.inputText))
        async let sentiment = sentimentSkill.execute(input: .text(Self.inputText))
        async let entities = entitySkill.execute(input: .text(Self.inputText))
        async let tokens = tokenSkill.execute(input: NativeToolInput(
            text: Self.inputText,
            parameters: ["unit": "sentence"]
        ))

        let langResult = try await lang
        #expect(langResult.output == "en")
        #expect(langResult.confidence > 0.9)
        #expect(langResult.latency < 1.0)

        let sentimentResult = try await sentiment
        let label = sentimentResult.structuredData["label"] ?? ""
        #expect(["positive", "negative", "neutral"].contains(label))
        #expect(sentimentResult.structuredData["score"] != nil)

        let entityResult = try await entities
        #expect(entityResult.structuredData["people"]?.contains("Tim Cook") == true)
        #expect(entityResult.structuredData["organizations"]?.contains("Apple") == true)
        #expect(entityResult.structuredData["organizations"]?.contains("Google") == true)
        #expect(entityResult.structuredData["organizations"]?.contains("Microsoft") == true)
        #expect(entityResult.structuredData["organizations"]?.contains("Meta") == true)
        #expect(entityResult.structuredData["places"]?.contains("Cupertino") == true)
        #expect(entityResult.structuredData["places"]?.contains("California") == true)

        let tokenResult = try await tokens
        let sentenceCount = Int(tokenResult.structuredData["count"] ?? "0") ?? 0
        #expect(sentenceCount == 5)
    }

    @Test("Entity extraction finds entities in tech news")
    func testComplexEntities() async throws {
        let skill = EntityExtractionSkill()
        // Use the same text that works in the demo
        let result = try await skill.execute(input: .text(Self.inputText))
        let people = result.structuredData["people"] ?? ""
        let orgs = result.structuredData["organizations"] ?? ""
        #expect(people.contains("Tim Cook"))
        #expect(orgs.contains("Apple"))
    }

    @Test("Language detection across 5 languages")
    func testMultiLanguage() async throws {
        let skill = LanguageDetectionSkill()

        let cases: [(String, String)] = [
            ("This is a straightforward English sentence for testing purposes.", "en"),
            ("Esta es una oración en español para pruebas de detección.", "es"),
            ("Dies ist ein deutscher Satz zur Erkennung der Sprache.", "de"),
            ("Ceci est une phrase en français pour tester la détection.", "fr"),
            ("Questa è una frase in italiano per testare il rilevamento.", "it"),
        ]

        for (text, expected) in cases {
            let result = try await skill.execute(input: .text(text))
            #expect(result.output == expected, "Expected \(expected) for: \(text.prefix(30))...")
            #expect(result.confidence > 0.5)
        }
    }

    @Test("Skill-to-Tool bridge works for all NLP skills")
    func testAllSkillsAsTool() async throws {
        let skills: [any NativeTool] = [
            LanguageDetectionSkill(),
            SentimentSkill(),
            EntityExtractionSkill(),
            TokenizationSkill(),
        ]

        for skill in skills {
            let tool = skill.asTool()
            #expect(!tool.name.isEmpty)
            #expect(!tool.description.isEmpty)

            let result = try await tool.execute(
                arguments: #"{"input": "Hello world, this is a test sentence."}"#,
                context: ToolContext()
            )
            #expect(!result.isEmpty)
        }
    }

    @Test("Agent with NLP skills registered as tools")
    func testAgentWithSkillTools() async throws {
        let provider = MockProvider(responses: ["Analysis complete. Language: English. Sentiment: positive."])
        let agent = Agent(
            configuration: AgentConfiguration(
                name: "NLPAgent",
                instructions: "You are an NLP analysis agent with Apple-native skills."
            ),
            model: provider,
            nativeTools: [
                LanguageDetectionSkill(),
                SentimentSkill(),
                EntityExtractionSkill(),
                TokenizationSkill(),
            ]
        )

        let result = try await agent.run("Analyze this text for language and sentiment")
        #expect(result.status == .completed)
        #expect(!result.content.isEmpty)
    }

    @Test("Parallel swarm with mock agents and real skills")
    func testSwarmWithRealSkills() async throws {
        // Agent 1: NLP analyzer with real skills
        let nlpAgent = Agent(
            configuration: AgentConfiguration(
                name: "NLPAnalyzer",
                instructions: "Analyze the text using your NLP skills."
            ),
            model: MockProvider(responses: ["Language: English. Entities: Tim Cook, Apple."]),
            nativeTools: [LanguageDetectionSkill(), SentimentSkill(), EntityExtractionSkill()]
        )

        // Agent 2: Summarizer
        let summaryAgent = Agent(
            configuration: AgentConfiguration(
                name: "Summarizer",
                instructions: "Summarize the key points."
            ),
            model: MockProvider(responses: ["Apple M4 Ultra chip announced with 38 TOPS performance."])
        )

        // Agent 3: Critic
        let criticAgent = Agent(
            configuration: AgentConfiguration(
                name: "Critic",
                instructions: "Evaluate the text quality."
            ),
            model: MockProvider(responses: ["Well-written tech announcement with strong claims."])
        )

        let swarm = Swarm(
            name: "AnalysisSwarm",
            mode: .parallel,
            members: [nlpAgent, summaryAgent, criticAgent]
        )

        let result = try await swarm.run(Self.inputText)
        #expect(result.memberResults.count == 3)
        for member in result.memberResults {
            #expect(member.status == .completed)
            #expect(!member.content.isEmpty)
        }
    }

    @Test("Sequential swarm chains output correctly")
    func testSequentialChaining() async throws {
        let step1 = Agent(
            configuration: AgentConfiguration(name: "Step1"),
            model: MockProvider(responses: ["Summary: Apple M4 Ultra announced."])
        )
        let step2 = Agent(
            configuration: AgentConfiguration(name: "Step2"),
            model: MockProvider(responses: ["Expanded: The M4 Ultra features 38 TOPS Neural Engine, adopted by Google, Microsoft, and Meta."])
        )

        let swarm = Swarm(
            name: "Chain",
            mode: .sequential,
            members: [step1, step2]
        )

        let result = try await swarm.run(Self.inputText)
        #expect(result.memberResults.count == 2)
        #expect(result.memberResults[0].content.contains("Summary"))
        #expect(result.memberResults[1].content.contains("Expanded"))
    }

    @Test("Routed swarm dispatches to correct agent")
    func testRoutedSwarm() async throws {
        let codeAgent = Agent(
            id: "coder",
            configuration: AgentConfiguration(name: "Coder"),
            model: MockProvider(responses: ["```swift\nprint(\"hello\")```"])
        )
        let writerAgent = Agent(
            id: "writer",
            configuration: AgentConfiguration(name: "Writer"),
            model: MockProvider(responses: ["A beautifully crafted narrative."])
        )

        let swarm = Swarm(
            name: "Router",
            mode: .route { input in
                input.contains("code") ? "coder" : "writer"
            },
            members: [codeAgent, writerAgent]
        )

        let codeResult = try await swarm.run("Write some code for me")
        #expect(codeResult.content.contains("swift"))

        let writeResult = try await swarm.run("Write me an essay")
        #expect(writeResult.content.contains("narrative"))
    }
}
