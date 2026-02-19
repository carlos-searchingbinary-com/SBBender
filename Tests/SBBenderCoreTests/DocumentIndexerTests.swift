import Testing
import Foundation
@testable import SBBenderCore

@Suite("DocumentIndexer Tests")
struct DocumentIndexerTests {

    // MARK: - Text Chunking

    @Suite("TextChunker")
    struct ChunkerTests {

        @Test("Fixed-size chunking splits text correctly")
        func fixedSizeChunking() {
            let chunker = TextChunker(strategy: .fixedSize(size: 5, overlap: 1))
            let text = "one two three four five six seven eight nine ten"

            let chunks = chunker.chunk(text, sourceID: "s1", sourceTitle: "Test")
            #expect(chunks.count >= 2)
            #expect(chunks[0].content.split(separator: " ").count <= 5)
            #expect(chunks[0].chunkIndex == 0)
            #expect(chunks[0].sourceTitle == "Test")
        }

        @Test("Sentence-based chunking respects token limit")
        func sentenceChunking() {
            let chunker = TextChunker(strategy: .sentence(maxTokens: 10))
            let text = "Hello world. This is a test. Another sentence here. And one more for good measure."

            let chunks = chunker.chunk(text, sourceID: "s1", sourceTitle: "Doc")
            #expect(chunks.count >= 1)
            for chunk in chunks {
                #expect(!chunk.content.isEmpty)
            }
        }

        @Test("Paragraph chunking splits on double newlines")
        func paragraphChunking() {
            let chunker = TextChunker(strategy: .paragraph)
            let text = "First paragraph.\n\nSecond paragraph.\n\nThird paragraph."

            let chunks = chunker.chunk(text, sourceID: "s1", sourceTitle: "Doc")
            #expect(chunks.count == 3)
            #expect(chunks[0].content == "First paragraph.")
            #expect(chunks[2].content == "Third paragraph.")
        }

        @Test("Empty text produces no chunks")
        func emptyText() {
            let chunker = TextChunker(strategy: .paragraph)
            let chunks = chunker.chunk("", sourceID: "s1", sourceTitle: "Empty")
            #expect(chunks.isEmpty)
        }

        @Test("Metadata is preserved in chunks")
        func metadataPreserved() {
            let chunker = TextChunker(strategy: .paragraph)
            let chunks = chunker.chunk(
                "Content here",
                sourceID: "src-1",
                sourceTitle: "My Doc",
                metadata: ["author": "Alice"]
            )
            #expect(chunks.count == 1)
            #expect(chunks[0].metadata["author"] == "Alice")
            #expect(chunks[0].sourceID == "src-1")
        }
    }

    // MARK: - BM25

    @Suite("BM25Index")
    struct BM25Tests {

        @Test("BM25 scores relevant documents higher")
        func relevantDocumentsScoreHigher() {
            let docs = [
                "Swift is a powerful programming language for Apple platforms",
                "Python is widely used in data science and machine learning",
                "The Swift programming language was created by Apple in 2014",
                "Weather today is sunny with clear skies",
            ]

            let bm25 = BM25Index(documents: docs)
            let scores = bm25.score(query: "Swift programming Apple")

            // Swift-related docs should score higher than weather
            #expect(scores[0] > scores[3])
            #expect(scores[2] > scores[3])
        }

        @Test("Empty query returns zero scores")
        func emptyQuery() {
            let bm25 = BM25Index(documents: ["hello world"])
            let scores = bm25.score(query: "")
            #expect(scores[0] == 0)
        }

        @Test("Unrelated query scores near zero")
        func unrelatedQuery() {
            let bm25 = BM25Index(documents: [
                "Swift programming language",
                "Machine learning with Python",
            ])
            let scores = bm25.score(query: "basketball tournament results")
            #expect(scores[0] < 0.1)
            #expect(scores[1] < 0.1)
        }

        @Test("BM25 tokenization works correctly")
        func tokenization() {
            let tokens = BM25Index.tokenize("Hello, World! This is a test.")
            #expect(tokens.contains("hello"))
            #expect(tokens.contains("world"))
            #expect(tokens.contains("this"))
            #expect(tokens.contains("test"))
            // Single-char tokens filtered
            #expect(!tokens.contains("a"))
        }
    }

    // MARK: - HNSW Graph

    @Suite("HNSWGraph")
    struct HNSWTests {

        @Test("Build and search simple graph")
        func buildAndSearch() async {
            let graph = HNSWGraph(maxConnections: 4, efConstruction: 16)

            let vectors: [[Float]] = [
                [1, 0, 0],
                [0, 1, 0],
                [0, 0, 1],
                [0.9, 0.1, 0],
                [0.1, 0.9, 0],
            ]

            await graph.build(vectors: vectors)
            let count = await graph.nodeCount
            #expect(count == 5)

            // Search for something close to [1, 0, 0]
            let results = await graph.search(query: [1, 0, 0], k: 2)
            #expect(results.count == 2)
            #expect(results[0].id == 0) // exact match
        }

        @Test("Empty graph returns no results")
        func emptyGraph() async {
            let graph = HNSWGraph()
            let results = await graph.search(query: [1, 0, 0], k: 5)
            #expect(results.isEmpty)
        }

        @Test("CSR export captures graph structure")
        func csrExport() async {
            let graph = HNSWGraph(maxConnections: 4, efConstruction: 16)
            let vectors: [[Float]] = [
                [1, 0], [0, 1], [1, 1],
            ]
            await graph.build(vectors: vectors)

            let csr = await graph.exportCSR()
            #expect(csr.offsets.count == 4) // n+1 offsets
            #expect(!csr.neighbors.isEmpty)
        }
    }

    // MARK: - NLEmbedding Provider

    @Suite("NLEmbeddingProvider")
    struct EmbeddingTests {

        @Test("Compute sentence embeddings")
        func computeEmbeddings() async throws {
            let provider = NLEmbeddingProvider()
            let embeddings = try await provider.embed(["Hello world", "Goodbye world"])

            #expect(embeddings.count == 2)
            #expect(embeddings[0].count == provider.dimension)
            #expect(embeddings[1].count == provider.dimension)
        }

        @Test("Similar sentences have closer embeddings")
        func similarSentencesCloser() async throws {
            let provider = NLEmbeddingProvider()
            let embeddings = try await provider.embed([
                "The cat sat on the mat",
                "The cat was sitting on the mat",
                "Quantum mechanics explores subatomic particles",
            ])

            let d01 = l2Distance(embeddings[0], embeddings[1])
            let d02 = l2Distance(embeddings[0], embeddings[2])

            // Cat sentences should be closer to each other than to quantum mechanics
            #expect(d01 < d02)
        }

        private func l2Distance(_ a: [Float], _ b: [Float]) -> Float {
            zip(a, b).reduce(Float(0)) { sum, pair in
                let diff = pair.0 - pair.1
                return sum + diff * diff
            }
        }
    }

    // MARK: - DocumentIndexer (Full Pipeline)

    @Suite("DocumentIndexer Integration")
    struct IndexerTests {

        @Test("Ingest and search documents")
        func ingestAndSearch() async throws {
            let indexer = DocumentIndexer(config: .init(
                chunkingStrategy: .paragraph,
                hybridWeight: 0.5
            ))

            try await indexer.ingest(
                content: """
                Swift is a powerful programming language developed by Apple.
                It is used for building iOS, macOS, and server applications.

                Python is a versatile language popular in data science.
                It has extensive libraries for machine learning and AI.

                Rust is known for memory safety and performance.
                It is used in systems programming and WebAssembly.
                """,
                title: "Programming Languages"
            )

            try await indexer.buildIndex()

            let count = await indexer.chunkCount
            #expect(count == 3)

            let results = try await indexer.hybridSearch(query: "Apple programming language", limit: 2)
            #expect(!results.isEmpty)
            #expect(results[0].content.contains("Swift"))
        }

        @Test("KnowledgeSource conformance works")
        func knowledgeSourceSearch() async throws {
            let indexer = DocumentIndexer(config: .init(chunkingStrategy: .paragraph))

            try await indexer.insert(content: "Machine learning uses neural networks for pattern recognition.", metadata: ["title": "ML Basics"])
            try await indexer.insert(content: "Cooking pasta requires boiling water first.", metadata: ["title": "Recipes"])

            let results = try await indexer.search(query: "neural networks", limit: 2)
            #expect(!results.isEmpty)
            #expect(results[0].content.contains("neural"))
        }

        @Test("Delete removes chunks and invalidates index")
        func deleteChunks() async throws {
            let indexer = DocumentIndexer(config: .init(chunkingStrategy: .paragraph))

            try await indexer.insert(content: "Test content", metadata: ["title": "Test"])

            let count = await indexer.chunkCount
            #expect(count == 1)

            let chunks = await indexer.allChunks
            try await indexer.delete(id: chunks[0].sourceID)

            let newCount = await indexer.chunkCount
            #expect(newCount == 0)
        }

        @Test("Multiple documents indexed together")
        func batchIngest() async throws {
            let indexer = DocumentIndexer(config: .init(chunkingStrategy: .paragraph))

            try await indexer.ingestBatch([
                (content: "Document about Swift.", title: "Swift", metadata: [:]),
                (content: "Document about Rust.", title: "Rust", metadata: [:]),
                (content: "Document about Go.", title: "Go", metadata: [:]),
            ])

            let count = await indexer.chunkCount
            #expect(count == 3)
        }
    }

    // MARK: - Document Loader

    @Suite("DocumentLoader")
    struct LoaderTests {

        @Test("Load text file")
        func loadTextFile() throws {
            let tmpDir = FileManager.default.temporaryDirectory
            let file = tmpDir.appendingPathComponent("test_\(UUID().uuidString).txt")
            try "Hello, World!".write(to: file, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: file) }

            let loader = DocumentLoader()
            let (content, title) = try loader.loadText(at: file.path)
            #expect(content == "Hello, World!")
            #expect(title.hasSuffix(".txt"))
        }

        @Test("Load directory of files")
        func loadDirectory() throws {
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            try "File 1 content".write(to: tmpDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
            try "File 2 content".write(to: tmpDir.appendingPathComponent("b.md"), atomically: true, encoding: .utf8)
            try "Ignored file".write(to: tmpDir.appendingPathComponent("c.xyz"), atomically: true, encoding: .utf8)

            let loader = DocumentLoader()
            let results = try loader.loadDirectory(at: tmpDir.path)
            #expect(results.count == 2) // .xyz not in default extensions
        }
    }
}
