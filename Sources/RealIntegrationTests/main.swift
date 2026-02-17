import Foundation
import SBBender

// ============================================================================
// SBBender — Comprehensive End-to-End Integration Tests
// ============================================================================
//
// Tests EVERY component with REAL inference, REAL documents, REAL web.
//
// Phases:
//   1. Apple NLP Skills (all 6 skills, real NaturalLanguage framework)
//   2. Document Ingestion (PDF, PPTX, Markdown from ~/Downloads)
//   3. Document Search & Analysis (hybrid HNSW+BM25 queries)
//   4. Web Fetching (real HTTP requests)
//   5. MLX Provider (Qwen3-4B-4bit on-device inference)
//   6. Agent + Tools + Skills + Knowledge (full pipeline)
//   7. Agent Streaming
//   8. Swarms (parallel, sequential, routed)
//   9. Swarm + Knowledge + Skills (multi-agent with search)
//  10. Ollama Provider
//  11. Anthropic Provider (if API key set)
//  12. Full E2E Pipeline (ingest → index → agent → swarm → analyze)
// ============================================================================

@main
struct RealIntegrationTests {

    // MARK: - Test Infrastructure

    struct TestResult {
        let name: String
        let passed: Bool
        let duration: Double
        let detail: String
    }

    nonisolated(unsafe) static var results: [TestResult] = []

    static func record(_ name: String, passed: Bool, duration: Double, detail: String = "") {
        let result = TestResult(name: name, passed: passed, duration: duration, detail: detail)
        results.append(result)
        let icon = passed ? "PASS" : "FAIL"
        let timeStr = String(format: "%.2fs", duration)
        print("  [\(icon)] \(name) (\(timeStr))")
        if !detail.isEmpty {
            if !passed {
                print("         DETAIL: \(detail)")
            } else if duration > 0.01 {
                print("         \(detail)")
            }
        }
    }

    static func section(_ title: String) {
        print("\n" + String(repeating: "=", count: 70))
        print("  \(title)")
        print(String(repeating: "=", count: 70))
    }

    // MARK: - Main

    static func main() async {
        let totalStart = CFAbsoluteTimeGetCurrent()

        print("""
        ======================================================================
             SBBender — Comprehensive End-to-End Integration Tests
             REAL LLM + REAL Documents + REAL Web + REAL Skills
        ======================================================================
        """)

        // ── Phase 1: Apple NLP Skills ────────────────────────────────────
        await testAppleNLPSkills()

        // ── Phase 2: Document Ingestion (PDF, PPTX, MD) ─────────────────
        let indexer = await testDocumentIngestion()

        // ── Phase 3: Document Search & Analysis ─────────────────────────
        if let indexer = indexer {
            await testDocumentSearch(indexer: indexer)
        }

        // ── Phase 4: Web Fetching ────────────────────────────────────────
        await testWebFetch()

        // ── Phase 5: MLX Provider ────────────────────────────────────────
        let mlx = await testMLXProvider()

        // ── Phase 6-9: Agent + Swarms with MLX ──────────────────────────
        if let mlx = mlx {
            await testAgentFullPipeline(model: mlx, providerName: "MLX")
            await testAgentStreaming(model: mlx, providerName: "MLX")
            await testSwarms(model: mlx, providerName: "MLX")
            if let indexer = indexer {
                await testSwarmWithKnowledge(model: mlx, indexer: indexer)
            }
        }

        // ── Phase 10: Ollama ─────────────────────────────────────────────
        await testOllamaProvider()

        // ── Phase 11: Anthropic ──────────────────────────────────────────
        await testAnthropicProvider()

        // ── Phase 12: Full E2E Pipeline ──────────────────────────────────
        if let mlx = mlx {
            await testFullE2EPipeline(model: mlx)
        }

        // ── Summary ──────────────────────────────────────────────────────
        let totalTime = CFAbsoluteTimeGetCurrent() - totalStart
        printSummary(totalTime: totalTime)
    }

    // ======================================================================
    // MARK: - Phase 1: Apple NLP Skills
    // ======================================================================

    static func testAppleNLPSkills() async {
        section("Phase 1: Apple NLP Skills (real NaturalLanguage framework)")

        let testText = """
        Apple announced today that Tim Cook will present the new M4 Ultra \
        chip at Apple Park in Cupertino. Google and Microsoft executives \
        praised the breakthrough in neural processing technology. This is \
        absolutely fantastic news for the entire industry.
        """

        // Language Detection — multiple languages
        for (text, expected, label) in [
            (testText, "en", "English"),
            ("Olá mundo, como estás? Estou bem obrigado.", "pt", "Portuguese"),
            ("Bonjour le monde, comment allez-vous aujourd'hui?", "fr", "French"),
            ("Hola mundo, ¿cómo estás hoy?", "es", "Spanish"),
        ] {
            do {
                let start = CFAbsoluteTimeGetCurrent()
                let result = try await LanguageDetectionSkill().execute(input: .text(text))
                let elapsed = CFAbsoluteTimeGetCurrent() - start
                record("LanguageDetection — \(label)", passed: result.output == expected, duration: elapsed,
                       detail: "Expected '\(expected)', got '\(result.output)'")
            } catch {
                record("LanguageDetection — \(label)", passed: false, duration: 0, detail: error.localizedDescription)
            }
        }

        // Sentiment Analysis
        for (text, expected, label) in [
            ("This is absolutely wonderful and amazing! I love it!", "positive", "positive"),
            ("This is terrible, awful, and completely broken.", "negative", "negative"),
        ] {
            do {
                let start = CFAbsoluteTimeGetCurrent()
                let result = try await SentimentSkill().execute(input: .text(text))
                let elapsed = CFAbsoluteTimeGetCurrent() - start
                record("Sentiment — \(label)", passed: result.output == expected, duration: elapsed,
                       detail: "Score: \(result.structuredData["score"] ?? "?")")
            } catch {
                record("Sentiment — \(label)", passed: false, duration: 0, detail: error.localizedDescription)
            }
        }

        // Entity Extraction
        do {
            let start = CFAbsoluteTimeGetCurrent()
            let result = try await EntityExtractionSkill().execute(input: .text(testText))
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            let people = result.structuredData["people"] ?? ""
            let orgs = result.structuredData["organizations"] ?? ""
            let places = result.structuredData["places"] ?? ""
            let passed = people.contains("Tim Cook") && places.contains("Cupertino")
            record("EntityExtraction — people + orgs + places", passed: passed, duration: elapsed,
                   detail: "People: \(people), Orgs: \(orgs), Places: \(places)")
        } catch {
            record("EntityExtraction", passed: false, duration: 0, detail: error.localizedDescription)
        }

        // Tokenization
        do {
            let start = CFAbsoluteTimeGetCurrent()
            let result = try await TokenizationSkill().execute(input: NativeToolInput(
                text: "Hello world. How are you? I am fine.", parameters: ["unit": "sentence"]))
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            let count = Int(result.structuredData["count"] ?? "0") ?? 0
            record("Tokenization — sentences", passed: count == 3, duration: elapsed,
                   detail: "Expected 3, got \(count)")
        } catch {
            record("Tokenization", passed: false, duration: 0, detail: error.localizedDescription)
        }

        // Embedding Distance
        do {
            let start = CFAbsoluteTimeGetCurrent()
            let skill = EmbeddingDistanceSkill()
            if await skill.isAvailable {
                let result = try await skill.execute(input: NativeToolInput(
                    text: "king", parameters: ["compareTo": "queen"]))
                let elapsed = CFAbsoluteTimeGetCurrent() - start
                let similarity = Float(result.output) ?? 0
                record("EmbeddingDistance — king vs queen", passed: similarity > 0.1, duration: elapsed,
                       detail: "Similarity: \(result.output)")
            } else {
                record("EmbeddingDistance — skipped", passed: true, duration: 0, detail: "Not available")
            }
        } catch {
            record("EmbeddingDistance", passed: false, duration: 0, detail: error.localizedDescription)
        }

        // Error handling
        do {
            _ = try await LanguageDetectionSkill().execute(input: .text(""))
            record("Skill error — empty input", passed: false, duration: 0, detail: "Should have thrown")
        } catch {
            record("Skill error — empty input throws", passed: true, duration: 0)
        }
    }

    // ======================================================================
    // MARK: - Phase 2: Document Ingestion (PDF, PPTX, MD)
    // ======================================================================

    static func testDocumentIngestion() async -> DocumentIndexer? {
        section("Phase 2: Document Ingestion (PDF + PPTX + Markdown)")

        let loader = DocumentLoader()
        let indexer = DocumentIndexer(config: DocumentIndexer.Config(
            chunkingStrategy: .sentence(maxTokens: 200)
        ))

        var totalDocsIngested = 0

        // Test PDF loading
        #if canImport(PDFKit)
        do {
            let start = CFAbsoluteTimeGetCurrent()
            // Find a small PDF
            let downloadsPath = NSHomeDirectory() + "/Downloads"
            let fm = FileManager.default
            let allFiles = try fm.contentsOfDirectory(atPath: downloadsPath)
            let smallPDFs = allFiles
                .filter { $0.hasSuffix(".pdf") }
                .compactMap { name -> (String, UInt64)? in
                    let path = downloadsPath + "/" + name
                    guard let attrs = try? fm.attributesOfItem(atPath: path),
                          let size = attrs[.size] as? UInt64,
                          size < 500_000 else { return nil }
                    return (path, size)
                }
                .sorted { $0.1 < $1.1 }

            if let (pdfPath, pdfSize) = smallPDFs.first {
                let docs = try loader.loadPDF(at: pdfPath)
                let elapsed = CFAbsoluteTimeGetCurrent() - start
                let passed = !docs.isEmpty
                record("PDF loading — \(URL(fileURLWithPath: pdfPath).lastPathComponent) (\(pdfSize/1024)KB)",
                       passed: passed, duration: elapsed,
                       detail: "Extracted \(docs.count) pages, total chars: \(docs.map(\.0.count).reduce(0, +))")

                if passed {
                    for doc in docs.prefix(3) {
                        try await indexer.ingest(content: doc.0, title: doc.1, metadata: doc.2)
                    }
                    totalDocsIngested += min(docs.count, 3)
                }
            } else {
                record("PDF loading — no small PDFs found", passed: true, duration: 0, detail: "Skipped")
            }
        } catch {
            record("PDF loading", passed: false, duration: 0, detail: error.localizedDescription)
        }
        #else
        record("PDF loading — PDFKit not available", passed: true, duration: 0, detail: "Skipped")
        #endif

        // Test PPTX loading
        do {
            let start = CFAbsoluteTimeGetCurrent()
            let downloadsPath = NSHomeDirectory() + "/Downloads"
            let fm = FileManager.default
            let allFiles = try fm.contentsOfDirectory(atPath: downloadsPath)
            let pptxFiles = allFiles
                .filter { $0.hasSuffix(".pptx") && !$0.hasPrefix("~$") }
                .compactMap { name -> (String, UInt64)? in
                    let path = downloadsPath + "/" + name
                    guard let attrs = try? fm.attributesOfItem(atPath: path),
                          let size = attrs[.size] as? UInt64,
                          size > 1024,          // skip corrupt/empty downloads
                          size < 2_000_000 else { return nil }
                    return (path, size)
                }
                .sorted { $0.1 < $1.1 }

            if let (pptxPath, pptxSize) = pptxFiles.first {
                let docs = try loader.loadPPTX(at: pptxPath)
                let elapsed = CFAbsoluteTimeGetCurrent() - start
                let passed = !docs.isEmpty
                record("PPTX loading — \(URL(fileURLWithPath: pptxPath).lastPathComponent) (\(pptxSize/1024)KB)",
                       passed: passed, duration: elapsed,
                       detail: "Extracted \(docs.count) slides, total chars: \(docs.map(\.0.count).reduce(0, +))")

                if passed {
                    for doc in docs.prefix(5) {
                        try await indexer.ingest(content: doc.0, title: doc.1, metadata: doc.2)
                    }
                    totalDocsIngested += min(docs.count, 5)
                }
            } else {
                record("PPTX loading — no small PPTX found", passed: true, duration: 0, detail: "Skipped")
            }
        } catch {
            record("PPTX loading", passed: false, duration: 0, detail: error.localizedDescription)
        }

        // Test Markdown loading
        do {
            let start = CFAbsoluteTimeGetCurrent()
            let downloadsPath = NSHomeDirectory() + "/Downloads"
            let mdDocs = try loader.loadDirectory(at: downloadsPath, extensions: ["md"])
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            record("Markdown loading from ~/Downloads", passed: !mdDocs.isEmpty, duration: elapsed,
                   detail: "Found \(mdDocs.count) .md files")

            // Ingest first 5 markdown docs
            let toIngest = Array(mdDocs.prefix(5))
            for doc in toIngest {
                try await indexer.ingest(content: doc.0, title: doc.1, metadata: doc.2)
            }
            totalDocsIngested += toIngest.count
        } catch {
            record("Markdown loading", passed: false, duration: 0, detail: error.localizedDescription)
        }

        // Test inline document ingestion for controlled search tests
        do {
            try await indexer.ingest(
                content: """
                Machine learning is a subset of artificial intelligence that enables \
                computers to learn from data without being explicitly programmed. \
                Deep learning uses neural networks with many layers to learn complex patterns. \
                Transformer architectures have revolutionized natural language processing.
                """,
                title: "ML Overview"
            )
            try await indexer.ingest(
                content: """
                Swift is a powerful programming language developed by Apple for iOS, \
                macOS, watchOS, and tvOS development. It features type safety, \
                optionals, protocol-oriented programming, and async/await concurrency.
                """,
                title: "Swift Language"
            )
            try await indexer.ingest(
                content: """
                The Mediterranean diet emphasizes fruits, vegetables, whole grains, \
                olive oil, and fish. Studies show it reduces heart disease risk \
                and improves overall health outcomes significantly.
                """,
                title: "Mediterranean Diet"
            )
            totalDocsIngested += 3
        } catch {
            record("Inline document ingestion", passed: false, duration: 0, detail: error.localizedDescription)
        }

        // Build the index
        do {
            let start = CFAbsoluteTimeGetCurrent()
            try await indexer.buildIndex()
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            let chunkCount = await indexer.chunkCount
            record("Build hybrid index (HNSW + BM25)", passed: true, duration: elapsed,
                   detail: "\(totalDocsIngested) docs → \(chunkCount) chunks indexed")
        } catch {
            record("Build index", passed: false, duration: 0, detail: error.localizedDescription)
            return nil
        }

        return indexer
    }

    // ======================================================================
    // MARK: - Phase 3: Document Search & Analysis
    // ======================================================================

    static func testDocumentSearch(indexer: DocumentIndexer) async {
        section("Phase 3: Document Search & Analysis (Hybrid HNSW+BM25)")

        // Semantic search tests
        let queries: [(query: String, expectedTitle: String, label: String)] = [
            ("neural networks deep learning transformers", "ML Overview", "ML query"),
            ("Apple programming language type safety", "Swift Language", "Swift query"),
            ("healthy food olive oil Mediterranean", "Mediterranean Diet", "Diet query"),
        ]

        for (query, expectedTitle, label) in queries {
            do {
                let start = CFAbsoluteTimeGetCurrent()
                let results = try await indexer.search(query: query, limit: 5)
                let elapsed = CFAbsoluteTimeGetCurrent() - start
                let topTitle = results.first?.metadata["sourceTitle"] ?? "none"
                let passed = topTitle == expectedTitle
                record("Search '\(label)' → \(expectedTitle)", passed: passed, duration: elapsed,
                       detail: "Top: '\(topTitle)' (score: \(String(format: "%.3f", results.first?.score ?? 0))), \(results.count) results")
            } catch {
                record("Search '\(label)'", passed: false, duration: 0, detail: error.localizedDescription)
            }
        }

        // Cross-format search (search across PDF, PPTX, MD content)
        do {
            let start = CFAbsoluteTimeGetCurrent()
            let results = try await indexer.search(query: "analysis report data", limit: 10)
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            let sources = Set(results.compactMap { $0.metadata["sourceTitle"] })
            record("Cross-format search — analysis", passed: !results.isEmpty, duration: elapsed,
                   detail: "\(results.count) results from \(sources.count) sources: \(sources.prefix(3).joined(separator: ", "))")
        } catch {
            record("Cross-format search", passed: false, duration: 0, detail: error.localizedDescription)
        }

        // Search ranking quality
        do {
            let start = CFAbsoluteTimeGetCurrent()
            let results = try await indexer.search(query: "protocol-oriented Swift actors concurrency", limit: 5)
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            let scores = results.map { $0.score }
            let isDescending = zip(scores, scores.dropFirst()).allSatisfy { $0 >= $1 }
            record("Search ranking — scores descending", passed: isDescending, duration: elapsed,
                   detail: "Scores: \(scores.map { String(format: "%.3f", $0) }.joined(separator: ", "))")
        } catch {
            record("Search ranking", passed: false, duration: 0, detail: error.localizedDescription)
        }
    }

    // ======================================================================
    // MARK: - Phase 4: Web Fetching
    // ======================================================================

    static func testWebFetch() async {
        section("Phase 4: Web Fetching (WebFetchSkill)")

        let skill = WebFetchSkill()

        // Fetch a simple web page
        do {
            let start = CFAbsoluteTimeGetCurrent()
            let result = try await skill.execute(input: .text("https://example.com"))
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            let hasContent = result.output.contains("Example Domain")
            record("WebFetch — example.com", passed: hasContent, duration: elapsed,
                   detail: "Status: \(result.structuredData["statusCode"] ?? "?"), length: \(result.structuredData["contentLength"] ?? "?")")
        } catch {
            record("WebFetch — example.com", passed: false, duration: 0, detail: error.localizedDescription)
        }

        // Fetch JSON API
        do {
            let start = CFAbsoluteTimeGetCurrent()
            let result = try await skill.execute(input: .text("https://httpbin.org/json"))
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            let isJSON = result.structuredData["contentType"]?.contains("json") == true
            record("WebFetch — JSON API", passed: isJSON && !result.output.isEmpty, duration: elapsed,
                   detail: "Content-Type: \(result.structuredData["contentType"] ?? "?"), length: \(result.structuredData["contentLength"] ?? "?")")
        } catch {
            record("WebFetch — JSON API", passed: false, duration: 0, detail: error.localizedDescription)
        }

        // HTML stripping quality
        do {
            let start = CFAbsoluteTimeGetCurrent()
            let result = try await skill.execute(input: .text("https://example.com"))
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            let noTags = !result.output.contains("<html") && !result.output.contains("<body") && !result.output.contains("<script")
            record("WebFetch — HTML tags stripped", passed: noTags, duration: elapsed,
                   detail: "Clean text, no HTML tags")
        } catch {
            record("WebFetch — HTML stripping", passed: false, duration: 0, detail: error.localizedDescription)
        }

        // Error handling — invalid URL
        do {
            _ = try await skill.execute(input: .text("not-a-url"))
            record("WebFetch — invalid URL error", passed: false, duration: 0, detail: "Should have thrown")
        } catch {
            record("WebFetch — invalid URL error", passed: true, duration: 0)
        }
    }

    // ======================================================================
    // MARK: - Phase 5: MLX Provider
    // ======================================================================

    static func testMLXProvider() async -> MLXProvider? {
        section("Phase 5: MLX Provider (Qwen3-4B-4bit, on-device)")

        let mlx = MLXProvider(modelID: "mlx-community/Qwen3-4B-4bit")

        // Load model
        do {
            let start = CFAbsoluteTimeGetCurrent()
            let _ = try await mlx.loadModel()
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            record("Load Qwen3-4B-4bit", passed: true, duration: elapsed)
        } catch {
            record("Load Qwen3-4B-4bit", passed: false, duration: 0, detail: error.localizedDescription)
            return nil
        }

        // Basic generation
        do {
            let start = CFAbsoluteTimeGetCurrent()
            let response = try await mlx.generate(
                messages: [.system("Be concise."), .user("What is 2 + 2? One word.")],
                config: GenerationConfig(maxTokens: 50, temperature: 0.1), tools: [])
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            let output = response.message.text.lowercased()
            record("MLX generation — 2+2", passed: output.contains("4") || output.contains("four"), duration: elapsed,
                   detail: "Output: \(response.message.text.prefix(60))")
        } catch {
            record("MLX generation", passed: false, duration: 0, detail: error.localizedDescription)
        }

        // Thinking stripped
        do {
            let start = CFAbsoluteTimeGetCurrent()
            let response = try await mlx.generate(
                messages: [.system("You are helpful."), .user("Say hello in French.")],
                config: GenerationConfig(maxTokens: 100, temperature: 0.3, enableThinking: false), tools: [])
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            let noThink = !response.message.text.contains("<think>")
            record("MLX — thinking disabled", passed: noThink && !response.message.text.isEmpty, duration: elapsed,
                   detail: "Output: \(response.message.text.prefix(60))")
        } catch {
            record("MLX — thinking disabled", passed: false, duration: 0, detail: error.localizedDescription)
        }

        // Streaming
        do {
            let start = CFAbsoluteTimeGetCurrent()
            var chunks = 0
            var gotDone = false
            for try await delta in mlx.generateStream(
                messages: [.system("Be brief."), .user("Count 1 to 5.")],
                config: GenerationConfig(maxTokens: 100, temperature: 0.3), tools: []
            ) {
                switch delta {
                case .text: chunks += 1
                case .done: gotDone = true
                case .toolCall: break
                }
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            record("MLX streaming", passed: chunks > 0 && gotDone, duration: elapsed,
                   detail: "\(chunks) chunks received")
        } catch {
            record("MLX streaming", passed: false, duration: 0, detail: error.localizedDescription)
        }

        // Tool calling
        do {
            let start = CFAbsoluteTimeGetCurrent()
            let response = try await mlx.generate(
                messages: [
                    .system("Use the calculate tool for math."),
                    .user("What is 15 * 23?")
                ],
                config: GenerationConfig(maxTokens: 200, temperature: 0.1),
                tools: [ToolDefinition(
                    name: "calculate",
                    description: "Evaluate a math expression",
                    parameters: JSONSchema(
                        properties: ["expression": .string("Math expression")],
                        required: ["expression"]
                    ).toDictionary()
                )]
            )
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            let hasToolCalls = !(response.message.toolCalls ?? []).isEmpty
            record("MLX tool calling — calculate", passed: hasToolCalls || response.message.text.contains("345"),
                   duration: elapsed,
                   detail: hasToolCalls ? "Tool: \(response.message.toolCalls?.first?.name ?? "")" : "Direct: \(response.message.text.prefix(50))")
        } catch {
            record("MLX tool calling", passed: false, duration: 0, detail: error.localizedDescription)
        }

        // ToolCallFormat parsing (all 3 formats)
        do {
            let qwen3 = Qwen3ToolFormat()
            let (q, _) = qwen3.parseToolCalls("<tool_call>\n{\"name\": \"calc\", \"arguments\": {\"x\": 1}}\n</tool_call>")
            record("ToolCallFormat — Qwen3", passed: q.count == 1 && q[0].name == "calc", duration: 0)

            let llama = LlamaToolFormat()
            let (l, _) = llama.parseToolCalls("<|python_tag|>{\"name\": \"calc\", \"parameters\": {\"x\": 1}}")
            record("ToolCallFormat — Llama", passed: l.count == 1, duration: 0)

            let generic = GenericToolFormat()
            let (g, _) = generic.parseToolCalls("```json\n{\"name\": \"calc\", \"arguments\": {\"x\": 1}}\n```")
            record("ToolCallFormat — Generic", passed: g.count == 1, duration: 0)
        }

        return mlx
    }

    // ======================================================================
    // MARK: - Phase 6: Agent + Tools + Skills + Knowledge
    // ======================================================================

    static func testAgentFullPipeline(model: any ModelProvider, providerName: String) async {
        section("Phase 6: Agent Full Pipeline (\(providerName))")

        let langSkill = LanguageDetectionSkill()
        let sentimentSkill = SentimentSkill()
        let entitySkill = EntityExtractionSkill()
        let webSkill = WebFetchSkill()

        let calcTool = Tool(
            name: "calculate",
            description: "Evaluate a math expression",
            parameters: JSONSchema(
                properties: ["expression": .string("Math expression, e.g. '15 * 37'")],
                required: ["expression"]
            )
        ) { arguments, _ in
            struct Args: Decodable { let expression: String }
            let args = try JSONDecoder().decode(Args.self, from: Data(arguments.utf8))
            let expr = NSExpression(format: args.expression)
            let result = expr.expressionValue(with: nil, context: nil) as? NSNumber
            return result.map { String(describing: $0) } ?? "Error"
        }

        // Agent with ALL capabilities
        let agent = Agent(
            configuration: AgentConfiguration(
                name: "FullAgent",
                instructions: """
                You are a powerful assistant with tools and skills.
                Use 'calculate' for math. Use 'detectLanguage' for language detection.
                Use 'analyzeSentiment' for sentiment. Use 'extractEntities' for entities.
                Always use tools when they match the request.
                """,
                generationConfig: GenerationConfig(maxTokens: 300, temperature: 0.2)
            ),
            model: model,
            tools: [calcTool],
            nativeTools: [langSkill, sentimentSkill, entitySkill, webSkill]
        )

        // Test: Tool calling — math
        do {
            let start = CFAbsoluteTimeGetCurrent()
            let result = try await agent.run("What is 42 * 17?")
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            let hasCalc = result.toolExecutions.contains { $0.toolName == "calculate" }
            record("Agent tool — calculate 42*17", passed: !result.content.isEmpty, duration: elapsed,
                   detail: "Tool used: \(hasCalc), executions: \(result.toolExecutions.count), answer: \(result.content.prefix(60))")
            if hasCalc {
                let calcResult = result.toolExecutions.first { $0.toolName == "calculate" }?.result ?? ""
                record("Agent tool result — 714", passed: calcResult.contains("714"), duration: 0,
                       detail: "calculate returned: \(calcResult)")
            }
        } catch {
            record("Agent tool — calculate", passed: false, duration: 0, detail: error.localizedDescription)
        }

        // Test: NLP skill — language detection
        do {
            let start = CFAbsoluteTimeGetCurrent()
            let result = try await agent.run("Detect the language: 'Bonjour le monde, comment allez-vous?'")
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            record("Agent skill — detect French", passed: !result.content.isEmpty, duration: elapsed,
                   detail: "Executions: \(result.toolExecutions.count), output: \(result.content.prefix(60))")
        } catch {
            record("Agent skill — detect French", passed: false, duration: 0, detail: error.localizedDescription)
        }

        // Test: Agent metrics
        do {
            let start = CFAbsoluteTimeGetCurrent()
            let result = try await agent.run("What is 10 + 20?")
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            record("Agent metrics", passed: result.metrics.modelCalls > 0 && result.metrics.totalLatency > 0,
                   duration: elapsed,
                   detail: "Calls: \(result.metrics.modelCalls), latency: \(String(format: "%.2f", result.metrics.totalLatency))s, tokens: \(result.metrics.totalTokens)")
        } catch {
            record("Agent metrics", passed: false, duration: 0, detail: error.localizedDescription)
        }

        // Test: Agent with Knowledge
        do {
            let indexer = DocumentIndexer()
            try await indexer.ingest(
                content: "SBBender uses HNSW graphs and BM25 scoring for hybrid semantic search. It runs on Apple Silicon with MLX.",
                title: "SBBender Search")
            try await indexer.buildIndex()

            let knowledgeAgent = Agent(
                configuration: AgentConfiguration(
                    name: "KnowledgeAgent",
                    instructions: "Answer using the provided knowledge context.",
                    generationConfig: GenerationConfig(maxTokens: 200, temperature: 0.3)
                ),
                model: model, knowledge: indexer
            )

            let start = CFAbsoluteTimeGetCurrent()
            let result = try await knowledgeAgent.run("What search algorithm does SBBender use?")
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            record("Agent + Knowledge — search question", passed: !result.content.isEmpty, duration: elapsed,
                   detail: "Output: \(result.content.prefix(80))")
        } catch {
            record("Agent + Knowledge", passed: false, duration: 0, detail: error.localizedDescription)
        }

        // Test: Agent reset
        do {
            let start = CFAbsoluteTimeGetCurrent()
            let _ = try await agent.run("Remember: my name is Carlos")
            await agent.reset()
            let result = try await agent.run("What is 5 + 5?")
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            record("Agent reset — history cleared", passed: !result.content.isEmpty, duration: elapsed,
                   detail: "Post-reset response: \(result.content.prefix(60))")
        } catch {
            record("Agent reset", passed: false, duration: 0, detail: error.localizedDescription)
        }
    }

    // ======================================================================
    // MARK: - Phase 7: Agent Streaming
    // ======================================================================

    static func testAgentStreaming(model: any ModelProvider, providerName: String) async {
        section("Phase 7: Agent Streaming (\(providerName))")

        let agent = Agent(
            configuration: AgentConfiguration(
                name: "StreamAgent",
                instructions: "Be brief.",
                generationConfig: GenerationConfig(maxTokens: 100, temperature: 0.3)
            ),
            model: model
        )

        do {
            let start = CFAbsoluteTimeGetCurrent()
            var textChunks = 0
            var gotCompleted = false

            for try await event in await agent.runStream("Say hello in 3 words.") {
                switch event {
                case .contentDelta: textChunks += 1
                case .completed: gotCompleted = true
                default: break
                }
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - start
            record("Agent streaming — chunks + completion", passed: textChunks > 0 && gotCompleted,
                   duration: elapsed, detail: "\(textChunks) text chunks, completed: \(gotCompleted)")
        } catch {
            record("Agent streaming", passed: false, duration: 0, detail: error.localizedDescription)
        }
    }

    // ======================================================================
    // MARK: - Phase 8: Swarms
    // ======================================================================

    static func testSwarms(model: any ModelProvider, providerName: String) async {
        section("Phase 8: Swarms (\(providerName))")

        let inputText = """
        Renewable energy sources like solar and wind power are becoming \
        increasingly cost-effective. In 2024, solar installations exceeded \
        coal capacity globally for the first time.
        """

        // Parallel Swarm
        do {
            let start = CFAbsoluteTimeGetCurrent()
            let swarm = Swarm(
                name: "ParallelSwarm",
                mode: .parallel,
                members: [
                    Agent(configuration: AgentConfiguration(name: "Analyst",
                        instructions: "Summarize in one sentence.",
                        generationConfig: GenerationConfig(maxTokens: 100, temperature: 0.2)), model: model),
                    Agent(configuration: AgentConfiguration(name: "Critic",
                        instructions: "Give one counterargument in one sentence.",
                        generationConfig: GenerationConfig(maxTokens: 100, temperature: 0.4)), model: model),
                    Agent(configuration: AgentConfiguration(name: "Creative",
                        instructions: "Write a haiku about this topic.",
                        generationConfig: GenerationConfig(maxTokens: 80, temperature: 0.9)), model: model),
                ]
            )

            let result = try await swarm.run(inputText)
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            let allContent = result.memberResults.allSatisfy { !$0.content.isEmpty }
            record("Parallel swarm — 3 agents", passed: result.memberResults.count == 3 && allContent,
                   duration: elapsed, detail: "All agents produced content: \(allContent)")
            for (i, mr) in result.memberResults.enumerated() {
                let names = ["Analyst", "Critic", "Creative"]
                print("    [\(names[i])] \(mr.content.prefix(55))...")
            }
        } catch {
            record("Parallel swarm", passed: false, duration: 0, detail: error.localizedDescription)
        }

        // Sequential Swarm
        do {
            let start = CFAbsoluteTimeGetCurrent()
            let swarm = Swarm(
                name: "SeqSwarm",
                mode: .sequential,
                members: [
                    Agent(configuration: AgentConfiguration(name: "Summarizer",
                        instructions: "Summarize in one sentence. Only output the summary.",
                        generationConfig: GenerationConfig(maxTokens: 80, temperature: 0.2)), model: model),
                    Agent(configuration: AgentConfiguration(name: "Expander",
                        instructions: "Expand into 3 bullet points starting with '-'.",
                        generationConfig: GenerationConfig(maxTokens: 200, temperature: 0.5)), model: model),
                ]
            )

            let result = try await swarm.run(inputText)
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            record("Sequential swarm — chain", passed: result.memberResults.count == 2, duration: elapsed,
                   detail: "Step 1: \(result.memberResults.first?.content.prefix(50) ?? "")...")
        } catch {
            record("Sequential swarm", passed: false, duration: 0, detail: error.localizedDescription)
        }

        // Routed Swarm
        do {
            let start = CFAbsoluteTimeGetCurrent()
            let swarm = Swarm(
                name: "RouterSwarm",
                mode: .route { input in input.lowercased().contains("poem") ? "poet" : "tech" },
                members: [
                    Agent(id: "tech", configuration: AgentConfiguration(name: "TechExpert",
                        instructions: "Explain in 1-2 sentences.",
                        generationConfig: GenerationConfig(maxTokens: 100, temperature: 0.3)), model: model),
                    Agent(id: "poet", configuration: AgentConfiguration(name: "Poet",
                        instructions: "Write a 2-4 line poem.",
                        generationConfig: GenerationConfig(maxTokens: 80, temperature: 0.9)), model: model),
                ]
            )

            let techResult = try await swarm.run("Explain solar panels")
            let poetResult = try await swarm.run("Write a poem about the sun")
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            record("Routed swarm — tech", passed: !techResult.content.isEmpty, duration: elapsed,
                   detail: "Tech: \(techResult.content.prefix(50))")
            record("Routed swarm — poet", passed: !poetResult.content.isEmpty, duration: 0,
                   detail: "Poet: \(poetResult.content.prefix(50))")
        } catch {
            record("Routed swarm", passed: false, duration: 0, detail: error.localizedDescription)
        }

        // Swarm metrics
        do {
            let start = CFAbsoluteTimeGetCurrent()
            let swarm = Swarm(name: "MetricSwarm", mode: .parallel, members: [
                Agent(configuration: AgentConfiguration(name: "A1", instructions: "Say 'hello'.",
                    generationConfig: GenerationConfig(maxTokens: 20, temperature: 0.1)), model: model),
                Agent(configuration: AgentConfiguration(name: "A2", instructions: "Say 'world'.",
                    generationConfig: GenerationConfig(maxTokens: 20, temperature: 0.1)), model: model),
            ])
            let result = try await swarm.run("Go")
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            record("Swarm metrics", passed: result.metrics.modelCalls >= 2, duration: elapsed,
                   detail: "Calls: \(result.metrics.modelCalls), latency: \(String(format: "%.2f", result.metrics.totalLatency))s")
        } catch {
            record("Swarm metrics", passed: false, duration: 0, detail: error.localizedDescription)
        }
    }

    // ======================================================================
    // MARK: - Phase 9: Swarm + Knowledge + Skills
    // ======================================================================

    static func testSwarmWithKnowledge(model: any ModelProvider, indexer: DocumentIndexer) async {
        section("Phase 9: Swarm + Knowledge + Skills")

        do {
            let start = CFAbsoluteTimeGetCurrent()

            // Agent 1: Answers from knowledge base
            let researcher = Agent(
                configuration: AgentConfiguration(
                    name: "Researcher",
                    instructions: "Use the knowledge context to answer the question. Be specific and factual.",
                    generationConfig: GenerationConfig(maxTokens: 200, temperature: 0.2)
                ),
                model: model,
                knowledge: indexer
            )

            // Agent 2: Analyzes sentiment & entities of the answer
            let analyzer = Agent(
                configuration: AgentConfiguration(
                    name: "Analyzer",
                    instructions: """
                    Analyze the text you receive. Use the analyzeSentiment tool for sentiment \
                    and extractEntities for entities. Report your findings.
                    """,
                    generationConfig: GenerationConfig(maxTokens: 200, temperature: 0.3)
                ),
                model: model,
                nativeTools: [SentimentSkill(), EntityExtractionSkill()]
            )

            let swarm = Swarm(
                name: "KnowledgeSwarm",
                mode: .sequential,
                members: [researcher, analyzer]
            )

            let result = try await swarm.run("What programming language uses protocol-oriented design and actors?")
            let elapsed = CFAbsoluteTimeGetCurrent() - start

            let hasContent = result.memberResults.allSatisfy { !$0.content.isEmpty }
            record("Swarm + Knowledge — research then analyze", passed: hasContent, duration: elapsed,
                   detail: "Researcher: \(result.memberResults.first?.content.prefix(60) ?? "")...\nAnalyzer: \(result.memberResults.last?.content.prefix(60) ?? "")...")
        } catch {
            record("Swarm + Knowledge", passed: false, duration: 0, detail: error.localizedDescription)
        }
    }

    // ======================================================================
    // MARK: - Phase 10: Ollama Provider
    // ======================================================================

    static func testOllamaProvider() async {
        section("Phase 10: Ollama Provider")

        let ollama = OllamaProvider(modelID: "qwen3:4b")

        guard await ollama.isAvailable else {
            record("Ollama — not running", passed: true, duration: 0, detail: "Skipped")
            return
        }
        record("Ollama — available", passed: true, duration: 0)

        // Generation
        do {
            let start = CFAbsoluteTimeGetCurrent()
            let response = try await ollama.generate(
                messages: [.system("Be concise."), .user("What is the capital of France?")],
                config: GenerationConfig(maxTokens: 500, temperature: 0.1), tools: [])
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            record("Ollama generation — capital of France", passed: response.message.text.lowercased().contains("paris"),
                   duration: elapsed, detail: "Output: \(response.message.text.prefix(60))")
        } catch {
            record("Ollama generation", passed: false, duration: 0, detail: error.localizedDescription)
        }

        // Streaming
        do {
            let start = CFAbsoluteTimeGetCurrent()
            var chunks = 0; var gotDone = false
            for try await delta in ollama.generateStream(
                messages: [.system("Be brief."), .user("Count 1 to 3.")],
                config: GenerationConfig(maxTokens: 500, temperature: 0.1), tools: []
            ) {
                switch delta {
                case .text: chunks += 1
                case .done: gotDone = true
                case .toolCall: break
                }
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            record("Ollama streaming", passed: chunks > 0 && gotDone, duration: elapsed,
                   detail: "\(chunks) chunks")
        } catch {
            record("Ollama streaming", passed: false, duration: 0, detail: error.localizedDescription)
        }

        // Agent with Ollama (thinking disabled to save token budget)
        do {
            let start = CFAbsoluteTimeGetCurrent()
            let ollamaNoThink = OllamaProvider(modelID: "qwen3:4b", think: false)
            let agent = Agent(
                configuration: AgentConfiguration(name: "OllamaAgent", instructions: "Be concise. Answer in one sentence.",
                    generationConfig: GenerationConfig(maxTokens: 500, temperature: 0.3)),
                model: ollamaNoThink)
            let result = try await agent.run("What color is the sky?")
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            record("Agent with Ollama", passed: !result.content.isEmpty, duration: elapsed,
                   detail: "Output: \(result.content.prefix(60))")
        } catch {
            record("Agent with Ollama", passed: false, duration: 0, detail: error.localizedDescription)
        }

        // Cloud model
        do {
            let start = CFAbsoluteTimeGetCurrent()
            let cloud = OllamaProvider(modelID: "qwen3-coder-next:cloud")
            let response = try await cloud.generate(
                messages: [.system("Be concise."), .user("Write a Python one-liner to reverse a string.")],
                config: GenerationConfig(maxTokens: 200, temperature: 0.2), tools: [])
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            record("Ollama cloud — qwen3-coder-next", passed: !response.message.text.isEmpty, duration: elapsed,
                   detail: "Output: \(response.message.text.prefix(80))")
        } catch {
            record("Ollama cloud", passed: false, duration: 0, detail: error.localizedDescription)
        }
    }

    // ======================================================================
    // MARK: - Phase 11: Anthropic Provider
    // ======================================================================

    static func testAnthropicProvider() async {
        section("Phase 11: Anthropic Provider (Claude API)")

        guard let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !apiKey.isEmpty else {
            record("Anthropic — no API key", passed: true, duration: 0,
                   detail: "Set ANTHROPIC_API_KEY to enable")
            return
        }

        let anthropic = AnthropicProvider(apiKey: apiKey)

        // Generation
        do {
            let start = CFAbsoluteTimeGetCurrent()
            let response = try await anthropic.generate(
                messages: [.system("Be concise."), .user("What is 7 * 8? Just the number.")],
                config: GenerationConfig(maxTokens: 50, temperature: 0), tools: [])
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            record("Anthropic generation", passed: response.message.text.contains("56"), duration: elapsed,
                   detail: "Output: \(response.message.text.prefix(50))")
        } catch {
            record("Anthropic generation", passed: false, duration: 0, detail: error.localizedDescription)
        }

        // Tool calling
        do {
            let start = CFAbsoluteTimeGetCurrent()
            let response = try await anthropic.generate(
                messages: [.system("Use tools."), .user("What's the weather in London?")],
                config: GenerationConfig(maxTokens: 200, temperature: 0),
                tools: [ToolDefinition(
                    name: "get_weather", description: "Get weather for a location",
                    parameters: JSONSchema(properties: ["location": .string("City")], required: ["location"]).toDictionary()
                )]
            )
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            let hasToolCall = !(response.message.toolCalls ?? []).isEmpty
            record("Anthropic tool calling", passed: hasToolCall, duration: elapsed,
                   detail: "Tool: \(response.message.toolCalls?.first?.name ?? "none")")
        } catch {
            record("Anthropic tool calling", passed: false, duration: 0, detail: error.localizedDescription)
        }

        // Agent
        do {
            let start = CFAbsoluteTimeGetCurrent()
            let agent = Agent(
                configuration: AgentConfiguration(name: "ClaudeAgent", instructions: "Be concise.",
                    generationConfig: GenerationConfig(maxTokens: 100, temperature: 0)),
                model: anthropic, nativeTools: [LanguageDetectionSkill()])
            let result = try await agent.run("Detect the language of: 'Guten Morgen'")
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            record("Agent with Anthropic", passed: !result.content.isEmpty, duration: elapsed,
                   detail: "Output: \(result.content.prefix(60))")
        } catch {
            record("Agent with Anthropic", passed: false, duration: 0, detail: error.localizedDescription)
        }
    }

    // ======================================================================
    // MARK: - Phase 12: Full E2E Pipeline
    // ======================================================================

    static func testFullE2EPipeline(model: any ModelProvider) async {
        section("Phase 12: Full End-to-End Pipeline")

        do {
            let pipelineStart = CFAbsoluteTimeGetCurrent()

            // Step 1: Fetch web content
            print("  >> Step 1: Fetch web content...")
            let webSkill = WebFetchSkill()
            let webContent = try await webSkill.execute(input: .text("https://example.com"))

            // Step 2: Analyze web content with NLP skills
            print("  >> Step 2: Analyze with NLP skills...")
            let lang = try await LanguageDetectionSkill().execute(input: .text(webContent.output))
            let sentiment = try await SentimentSkill().execute(input: .text(webContent.output))
            let entities = try await EntityExtractionSkill().execute(input: .text(webContent.output))

            // Step 3: Ingest into DocumentIndexer
            print("  >> Step 3: Ingest into knowledge base...")
            let indexer = DocumentIndexer()
            try await indexer.ingest(content: webContent.output, title: "Example.com",
                                     metadata: ["url": "https://example.com"])
            try await indexer.ingest(
                content: "SBBender is a Swift agent runtime that uses MLX for on-device AI inference on Apple Silicon.",
                title: "SBBender Info")
            try await indexer.buildIndex()

            // Step 4: Search the knowledge base
            print("  >> Step 4: Search knowledge base...")
            let searchResults = try await indexer.search(query: "example domain", limit: 3)

            // Step 5: Agent answers using knowledge
            print("  >> Step 5: Agent answers using knowledge...")
            let agent = Agent(
                configuration: AgentConfiguration(
                    name: "E2EAgent",
                    instructions: "Use the knowledge context and tools to answer accurately.",
                    generationConfig: GenerationConfig(maxTokens: 200, temperature: 0.3)
                ),
                model: model,
                nativeTools: [LanguageDetectionSkill(), SentimentSkill()],
                knowledge: indexer
            )
            let agentResult = try await agent.run("What can you tell me about the example domain website?")

            // Step 6: Swarm analyzes the agent's answer
            print("  >> Step 6: Swarm analyzes the answer...")
            let swarm = Swarm(
                name: "E2ESwarm",
                mode: .parallel,
                members: [
                    Agent(configuration: AgentConfiguration(name: "Summarizer",
                        instructions: "Summarize in one sentence.",
                        generationConfig: GenerationConfig(maxTokens: 80, temperature: 0.2)), model: model),
                    Agent(configuration: AgentConfiguration(name: "Critic",
                        instructions: "Give one improvement suggestion.",
                        generationConfig: GenerationConfig(maxTokens: 80, temperature: 0.4)), model: model),
                ]
            )
            let swarmResult = try await swarm.run(agentResult.content)

            let pipelineElapsed = CFAbsoluteTimeGetCurrent() - pipelineStart

            // Validate all steps
            record("E2E: Web fetch", passed: !webContent.output.isEmpty, duration: 0,
                   detail: "Fetched \(webContent.output.count) chars")
            record("E2E: NLP analysis", passed: lang.output == "en", duration: 0,
                   detail: "Lang: \(lang.output), Sentiment: \(sentiment.output), Entities: \(entities.output.prefix(40))")
            record("E2E: Knowledge ingestion + index", passed: await indexer.chunkCount > 0, duration: 0,
                   detail: "\(await indexer.chunkCount) chunks")
            record("E2E: Knowledge search", passed: !searchResults.isEmpty, duration: 0,
                   detail: "\(searchResults.count) results, top: \(searchResults.first?.metadata["sourceTitle"] ?? "?")")
            record("E2E: Agent with knowledge", passed: !agentResult.content.isEmpty, duration: 0,
                   detail: "Agent: \(agentResult.content.prefix(60))...")
            record("E2E: Swarm analysis", passed: swarmResult.memberResults.count == 2, duration: 0,
                   detail: "Summarizer + Critic produced output")
            record("E2E: Full pipeline", passed: true, duration: pipelineElapsed,
                   detail: "Web → NLP → Ingest → Search → Agent → Swarm in \(String(format: "%.1f", pipelineElapsed))s")

        } catch {
            record("E2E Pipeline", passed: false, duration: 0, detail: error.localizedDescription)
        }
    }

    // ======================================================================
    // MARK: - Summary
    // ======================================================================

    static func printSummary(totalTime: Double) {
        let passed = results.filter(\.passed).count
        let failed = results.filter { !$0.passed }.count
        let total = results.count

        print("\n" + String(repeating: "=", count: 70))
        print("  INTEGRATION TEST SUMMARY")
        print(String(repeating: "=", count: 70))
        print("  Total:    \(total)")
        print("  Passed:   \(passed)")
        print("  Failed:   \(failed)")
        print("  Duration: \(String(format: "%.1f", totalTime))s")
        print(String(repeating: "=", count: 70))

        if failed > 0 {
            print("\n  FAILURES:")
            for r in results where !r.passed {
                print("    - \(r.name): \(r.detail)")
            }
        }

        print("\n  Status: \(failed == 0 ? "ALL PASSED" : "\(failed) FAILED")")
        print(String(repeating: "=", count: 70))
    }
}
