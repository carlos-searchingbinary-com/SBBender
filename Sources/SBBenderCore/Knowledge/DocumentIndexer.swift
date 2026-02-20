import Foundation
import NaturalLanguage
import os
#if canImport(PDFKit)
import PDFKit
#endif

// MARK: - Document Chunking

/// Strategies for splitting documents into searchable chunks.
public enum ChunkingStrategy: Sendable {
    /// Fixed-size chunks with overlap.
    case fixedSize(size: Int, overlap: Int)
    /// Split on sentences, grouping up to maxTokens.
    case sentence(maxTokens: Int)
    /// Split on paragraphs (double newline).
    case paragraph
}

/// A chunk of text extracted from a document.
public struct DocumentChunk: Sendable, Codable, Identifiable {
    public let id: String
    public let content: String
    public let sourceID: String
    public let sourceTitle: String
    public let chunkIndex: Int
    public let metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        content: String,
        sourceID: String,
        sourceTitle: String,
        chunkIndex: Int,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.content = content
        self.sourceID = sourceID
        self.sourceTitle = sourceTitle
        self.chunkIndex = chunkIndex
        self.metadata = metadata
    }
}

/// Splits text into chunks using configurable strategies.
public struct TextChunker: Sendable {
    public let strategy: ChunkingStrategy

    public init(strategy: ChunkingStrategy = .fixedSize(size: 256, overlap: 32)) {
        self.strategy = strategy
    }

    /// Split text into chunks.
    public func chunk(
        _ text: String,
        sourceID: String,
        sourceTitle: String,
        metadata: [String: String] = [:]
    ) -> [DocumentChunk] {
        let rawChunks: [String]

        switch strategy {
        case .fixedSize(let size, let overlap):
            rawChunks = chunkBySize(text, size: size, overlap: overlap)
        case .sentence(let maxTokens):
            rawChunks = chunkBySentence(text, maxTokens: maxTokens)
        case .paragraph:
            rawChunks = chunkByParagraph(text)
        }

        return rawChunks.enumerated().map { index, content in
            DocumentChunk(
                content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                sourceID: sourceID,
                sourceTitle: sourceTitle,
                chunkIndex: index,
                metadata: metadata
            )
        }.filter { !$0.content.isEmpty }
    }

    private func chunkBySize(_ text: String, size: Int, overlap: Int) -> [String] {
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !words.isEmpty else { return [] }

        var chunks: [String] = []
        var start = 0
        let step = max(size - overlap, 1)

        while start < words.count {
            let end = min(start + size, words.count)
            chunks.append(words[start..<end].joined(separator: " "))
            start += step
        }
        return chunks
    }

    private func chunkBySentence(_ text: String, maxTokens: Int) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        var chunks: [String] = []
        var currentChunk: [String] = []
        var currentCount = 0

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range])
            let wordCount = sentence.split(separator: " ").count

            if currentCount + wordCount > maxTokens && !currentChunk.isEmpty {
                chunks.append(currentChunk.joined(separator: " "))
                currentChunk = []
                currentCount = 0
            }

            currentChunk.append(sentence)
            currentCount += wordCount
            return true
        }

        if !currentChunk.isEmpty {
            chunks.append(currentChunk.joined(separator: " "))
        }
        return chunks
    }

    private func chunkByParagraph(_ text: String) -> [String] {
        text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - BM25 Scorer

/// Okapi BM25 keyword relevance scorer.
///
/// Implements the classic BM25 ranking function for keyword-based retrieval.
/// Used as the keyword component in hybrid search alongside vector similarity.
public struct BM25Index: Sendable {
    /// Term frequency per document: [docIndex: [term: count]]
    private let termFreqs: [[String: Int]]
    /// Inverse document frequency: [term: idf]
    private let idf: [String: Double]
    /// Document lengths (in terms)
    private let docLengths: [Int]
    /// Average document length
    private let avgDocLength: Double
    /// BM25 parameters
    private let k1: Double
    private let b: Double

    public init(documents: [String], k1: Double = 1.2, b: Double = 0.75) {
        self.k1 = k1
        self.b = b

        let n = documents.count
        var tfs: [[String: Int]] = []
        var docFreq: [String: Int] = [:]
        var lengths: [Int] = []

        for doc in documents {
            let terms = Self.tokenize(doc)
            lengths.append(terms.count)

            var tf: [String: Int] = [:]
            var seen: Set<String> = []
            for term in terms {
                tf[term, default: 0] += 1
                if !seen.contains(term) {
                    docFreq[term, default: 0] += 1
                    seen.insert(term)
                }
            }
            tfs.append(tf)
        }

        self.termFreqs = tfs
        self.docLengths = lengths
        self.avgDocLength = lengths.isEmpty ? 0 : Double(lengths.reduce(0, +)) / Double(n)

        // Compute IDF
        var computedIDF: [String: Double] = [:]
        let nDouble = Double(n)
        for (term, df) in docFreq {
            computedIDF[term] = log((nDouble - Double(df) + 0.5) / (Double(df) + 0.5) + 1.0)
        }
        self.idf = computedIDF
    }

    /// Score all documents against a query. Returns array of scores indexed by document.
    public func score(query: String) -> [Double] {
        let queryTerms = Self.tokenize(query)
        guard !queryTerms.isEmpty else {
            return Array(repeating: 0, count: termFreqs.count)
        }

        return (0..<termFreqs.count).map { i in
            var docScore = 0.0
            let dl = Double(docLengths[i])
            let tf = termFreqs[i]

            for term in queryTerms {
                guard let termIDF = idf[term], let freq = tf[term] else { continue }
                let fDouble = Double(freq)
                let numerator = fDouble * (k1 + 1)
                let denominator = fDouble + k1 * (1 - b + b * dl / avgDocLength)
                docScore += termIDF * numerator / denominator
            }
            return docScore
        }
    }

    /// Tokenize text into lowercase terms, removing short tokens.
    static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }
    }
}

// MARK: - HNSW Graph (Pure Swift)

/// Hierarchical Navigable Small World graph for approximate nearest neighbor search.
///
/// This is a pure Swift implementation inspired by LEANN's graph-based selective
/// recomputation strategy. Unlike traditional vector databases, embeddings are
/// recomputed on demand rather than stored, achieving massive storage savings.
///
/// The graph stores only the connectivity structure and passage text.
/// At query time, embeddings are computed for the query and traversed neighbors.
public actor HNSWGraph {
    /// A node in the graph with connections at each layer.
    struct Node: Sendable {
        let id: Int
        var connections: [[Int]] // connections per layer
    }

    private var nodes: [Node] = []
    private var vectors: [[Float]] = [] // cached during build, can be released
    private let maxConnections: Int // M parameter
    private let maxLayers: Int
    private let efConstruction: Int
    private var entryPoint: Int = 0
    private var maxLevel: Int = 0

    public init(maxConnections: Int = 16, efConstruction: Int = 64, maxLayers: Int = 4) {
        self.maxConnections = maxConnections
        self.efConstruction = efConstruction
        self.maxLayers = maxLayers
    }

    /// Build the graph from vectors.
    public func build(vectors: [[Float]]) {
        guard !vectors.isEmpty else { return }

        self.vectors = vectors
        self.nodes = []

        for i in 0..<vectors.count {
            let level = randomLevel()
            var node = Node(id: i, connections: Array(repeating: [], count: level + 1))

            if nodes.isEmpty {
                nodes.append(node)
                maxLevel = level
                entryPoint = 0
                continue
            }

            // Insert into graph: traverse from top to bottom
            var ep = entryPoint

            // Traverse upper layers (above node's level) greedily
            for l in stride(from: maxLevel, through: level + 1, by: -1) {
                ep = greedySearch(query: vectors[i], startNode: ep, layer: l)
            }

            // Insert at each layer the node belongs to
            for l in stride(from: min(level, maxLevel), through: 0, by: -1) {
                let candidates = searchLayer(query: vectors[i], entryPoint: ep, layer: l, ef: efConstruction)
                let neighbors = selectNeighbors(candidates, maxCount: maxConnections)

                node.connections[l] = neighbors.map(\.0)

                // Add bidirectional connections
                for (neighborID, _) in neighbors {
                    nodes[neighborID].connections[l].append(i)
                    // Prune if over limit
                    if nodes[neighborID].connections[l].count > maxConnections * 2 {
                        let pruned = pruneConnections(nodeID: neighborID, layer: l)
                        nodes[neighborID].connections[l] = pruned
                    }
                }

                if !candidates.isEmpty {
                    ep = candidates[0].0
                }
            }

            nodes.append(node)

            if level > maxLevel {
                maxLevel = level
                entryPoint = i
            }
        }
    }

    /// Search for k nearest neighbors.
    public func search(query: [Float], k: Int, ef: Int = 32) -> [(id: Int, distance: Float)] {
        guard !nodes.isEmpty else { return [] }

        var ep = entryPoint

        // Greedy traversal of upper layers
        for l in stride(from: maxLevel, through: 1, by: -1) {
            ep = greedySearch(query: query, startNode: ep, layer: l)
        }

        // Search bottom layer with ef candidates
        let candidates = searchLayer(query: query, entryPoint: ep, layer: 0, ef: max(ef, k))
        return Array(candidates.prefix(k))
    }

    /// Number of nodes in the graph.
    public var nodeCount: Int { nodes.count }

    /// Import graph connectivity from CSR format.
    /// Rebuilds graph nodes from stored topology (layer 0 only).
    public func importCSR(offsets: [Int], neighbors: [Int], nodeCount: Int) {
        self.nodes = []
        self.vectors = []
        for i in 0..<nodeCount {
            let start = offsets[i]
            let end = offsets[i + 1]
            let connections = Array(neighbors[start..<end])
            let node = Node(id: i, connections: [connections])
            nodes.append(node)
        }
        if !nodes.isEmpty {
            entryPoint = 0
            maxLevel = 0
        }
    }

    /// Export graph connectivity as CSR (Compressed Sparse Row) format.
    /// This is the storage-efficient format — no embeddings needed.
    public func exportCSR() -> (offsets: [Int], neighbors: [Int]) {
        var offsets: [Int] = [0]
        var neighbors: [Int] = []

        for node in nodes {
            let layer0 = node.connections.isEmpty ? [] : node.connections[0]
            neighbors.append(contentsOf: layer0)
            offsets.append(neighbors.count)
        }

        return (offsets, neighbors)
    }

    // MARK: - Private Helpers

    private func randomLevel() -> Int {
        var level = 0
        while Double.random(in: 0..<1) < 1.0 / Double(maxConnections) && level < maxLayers - 1 {
            level += 1
        }
        return level
    }

    private func greedySearch(query: [Float], startNode: Int, layer: Int) -> Int {
        var current = startNode
        var currentDist = distance(query, vectors[current])

        while true {
            var changed = false
            let neighbors = current < nodes.count ? nodes[current].connections[safe: layer] ?? [] : []

            for neighborID in neighbors where neighborID < vectors.count {
                let d = distance(query, vectors[neighborID])
                if d < currentDist {
                    current = neighborID
                    currentDist = d
                    changed = true
                }
            }

            if !changed { break }
        }

        return current
    }

    private func searchLayer(query: [Float], entryPoint: Int, layer: Int, ef: Int) -> [(Int, Float)] {
        var visited: Set<Int> = [entryPoint]
        var candidates: [(Int, Float)] = [(entryPoint, distance(query, vectors[entryPoint]))]
        var results: [(Int, Float)] = candidates

        while !candidates.isEmpty {
            candidates.sort { $0.1 < $1.1 }
            let (currentID, _) = candidates.removeFirst()

            let worstResult = results.max(by: { $0.1 < $1.1 })?.1 ?? Float.infinity

            let neighbors = currentID < nodes.count ? nodes[currentID].connections[safe: layer] ?? [] : []
            for neighborID in neighbors where neighborID < vectors.count {
                guard !visited.contains(neighborID) else { continue }
                visited.insert(neighborID)

                let d = distance(query, vectors[neighborID])
                if d < worstResult || results.count < ef {
                    candidates.append((neighborID, d))
                    results.append((neighborID, d))
                    results.sort { $0.1 < $1.1 }
                    if results.count > ef {
                        results.removeLast()
                    }
                }
            }
        }

        return results.sorted { $0.1 < $1.1 }
    }

    private func selectNeighbors(_ candidates: [(Int, Float)], maxCount: Int) -> [(Int, Float)] {
        Array(candidates.sorted { $0.1 < $1.1 }.prefix(maxCount))
    }

    private func pruneConnections(nodeID: Int, layer: Int) -> [Int] {
        let connections = nodes[nodeID].connections[layer]
        guard connections.count > maxConnections else { return connections }

        let scored = connections.map { neighborID -> (Int, Float) in
            let d = distance(vectors[nodeID], vectors[neighborID])
            return (neighborID, d)
        }

        return scored.sorted { $0.1 < $1.1 }.prefix(maxConnections).map(\.0)
    }

    /// L2 distance between two vectors.
    private func distance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return Float.infinity }
        var sum: Float = 0
        for i in 0..<a.count {
            let diff = a[i] - b[i]
            sum += diff * diff
        }
        return sum
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Embedding Provider Protocol

/// Protocol for computing text embeddings.
///
/// Implementations can use NaturalLanguage framework, MLX models,
/// or external APIs for embedding computation.
public protocol EmbeddingProvider: Sendable {
    /// Compute embedding vectors for a batch of texts.
    func embed(_ texts: [String]) async throws -> [[Float]]

    /// Embedding dimension.
    var dimension: Int { get }
}

/// Apple NaturalLanguage framework embedding provider.
///
/// Uses `NLEmbedding` for fast, on-device word/sentence embeddings.
/// No model download required — uses built-in Apple embeddings.
public struct NLEmbeddingProvider: EmbeddingProvider, Sendable {
    public let dimension: Int
    private let language: NLLanguage

    public init(language: NLLanguage = .english) {
        self.language = language
        // NLEmbedding.sentenceEmbedding dimension is 512 for English
        self.dimension = 512
    }

    public func embed(_ texts: [String]) async throws -> [[Float]] {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: language) else {
            throw SBBenderError.skillNotAvailable("NLEmbedding not available for \(language.rawValue)")
        }

        return texts.map { text in
            if let vector = embedding.vector(for: text) {
                return vector.map { Float($0) }
            }
            // Fallback: zero vector for texts that can't be embedded
            return Array(repeating: Float(0), count: dimension)
        }
    }
}

// MARK: - Ingestion Progress

/// Progress updates during document ingestion and index building.
public struct IngestionProgress: Sendable {
    public enum Phase: Sendable, Equatable {
        case chunking
        case embedding(current: Int, total: Int)
        case buildingIndex
        case done
    }
    public let phase: Phase
    public let fileName: String

    public init(phase: Phase, fileName: String = "") {
        self.phase = phase
        self.fileName = fileName
    }
}

// MARK: - Document Indexer (LEANN-inspired)

/// A storage-efficient document indexer inspired by LEANN.
///
/// Combines HNSW graph search with BM25 keyword scoring for hybrid retrieval.
/// Unlike traditional vector databases, embeddings can be recomputed on demand
/// rather than permanently stored, achieving significant storage savings.
///
/// Architecture (from LEANN):
/// ```
/// Documents → Chunking → Embedding → HNSW Graph Build
///                                         ↓
///                               Graph topology stored (CSR)
///                               Passages stored
///                               Embeddings: optional (recompute on demand)
///                                         ↓
/// Query → Embed Query → Graph Search → BM25 Rerank → Top-K Results
/// ```
public actor DocumentIndexer: KnowledgeSource {
    /// Configuration for the indexer.
    public struct Config: Sendable {
        public let chunkingStrategy: ChunkingStrategy
        public let maxConnections: Int
        public let efConstruction: Int
        public let searchEF: Int
        /// Legacy weight parameter — kept for backward compatibility with persisted configs.
        /// No longer used by the scoring algorithm, which now uses Reciprocal Rank Fusion (RRF).
        public let hybridWeight: Float
        public let storeEmbeddings: Bool // false = LEANN-style recompute on demand

        /// When true, a second-pass NLEmbedding cosine similarity reranker is applied
        /// after initial RRF retrieval. Improves precision at a small latency cost.
        public let enableReranking: Bool

        /// Fetch this many times `limit` during initial retrieval, then rerank down to `limit`.
        /// Higher values give the reranker more candidates to choose from.
        public let initialRetrievalMultiplier: Int

        /// Per-year recency decay applied to older document versions within the same family.
        /// Newer documents score 1.0; each year of age multiplies the score by this factor.
        /// Range: (0, 1]. Default 0.88 means a 2-year-old doc scores ~0.77 vs. the latest.
        public let recencyDecayPerYear: Double

        public init(
            chunkingStrategy: ChunkingStrategy = .fixedSize(size: 256, overlap: 32),
            maxConnections: Int = 16,
            efConstruction: Int = 64,
            searchEF: Int = 32,
            hybridWeight: Float = 0.7,
            storeEmbeddings: Bool = true,
            enableReranking: Bool = true,
            initialRetrievalMultiplier: Int = 4,
            recencyDecayPerYear: Double = 0.88
        ) {
            self.chunkingStrategy = chunkingStrategy
            self.maxConnections = maxConnections
            self.efConstruction = efConstruction
            self.searchEF = searchEF
            self.hybridWeight = hybridWeight
            self.storeEmbeddings = storeEmbeddings
            self.enableReranking = enableReranking
            self.initialRetrievalMultiplier = initialRetrievalMultiplier
            self.recencyDecayPerYear = recencyDecayPerYear
        }
    }

    private let config: Config
    private let embeddingProvider: any EmbeddingProvider
    private let chunker: TextChunker
    private var chunks: [DocumentChunk] = []
    private var graph: HNSWGraph
    private var bm25: BM25Index?
    private var isBuilt: Bool = false

    /// Maps sourceID → parsed document date, populated during buildIndex() from chunk metadata.
    private var documentDates: [String: Date] = [:]

    /// Optional persistence backend for saving/loading index state.
    public var persistence: (any KnowledgeIndexPersistence)?

    /// Set the persistence backend (convenience for actor isolation).
    public func setPersistence(_ backend: any KnowledgeIndexPersistence) {
        persistence = backend
    }

    /// Optional contextual enricher.  When set, each chunk is enriched with a
    /// context description (and entity metadata) before embedding and BM25 indexing.
    /// This implements Anthropic's Contextual Retrieval technique.
    public var contextualEnricher: ContextualEnricher?

    /// Set the contextual enricher (convenience for actor isolation).
    public func setContextualEnricher(_ enricher: ContextualEnricher?) {
        contextualEnricher = enricher
    }

    /// Closure type for HyDE (Hypothetical Document Embeddings).
    ///
    /// Receives the user query and returns a short hypothetical passage that would
    /// answer it — written in the style of the indexed documents.  The passage is
    /// embedded and searched alongside the original query for a significant recall boost.
    /// Return `nil` or an empty string to skip HyDE for a particular query.
    public typealias HyDEGenerator = @Sendable (String) async -> String?

    /// Optional HyDE generator.  When set, ``hybridSearch(query:limit:)`` generates a
    /// hypothetical answer, embeds it, and merges the result into RRF as a third signal.
    public var hydeGenerator: HyDEGenerator?

    /// Set the HyDE generator (convenience for actor isolation).
    public func setHyDEGenerator(_ generator: HyDEGenerator?) {
        hydeGenerator = generator
    }

    /// Optional callback for ingestion progress updates.
    public var onProgress: (@Sendable (IngestionProgress) -> Void)?

    /// Set the progress callback (convenience for actor isolation).
    public func setOnProgress(_ callback: (@Sendable (IngestionProgress) -> Void)?) {
        onProgress = callback
    }

    public init(
        config: Config = Config(),
        embeddingProvider: any EmbeddingProvider = NLEmbeddingProvider()
    ) {
        self.config = config
        self.embeddingProvider = embeddingProvider
        self.chunker = TextChunker(strategy: config.chunkingStrategy)
        self.graph = HNSWGraph(
            maxConnections: config.maxConnections,
            efConstruction: config.efConstruction
        )
    }

    // MARK: - Document Ingestion

    /// Ingest a document by chunking and indexing it.
    public func ingest(
        content: String,
        title: String,
        metadata: [String: String] = [:]
    ) async throws {
        onProgress?(IngestionProgress(phase: .chunking, fileName: title))

        let sourceID = UUID().uuidString
        let newChunks = chunker.chunk(content, sourceID: sourceID, sourceTitle: title, metadata: metadata)
        guard !newChunks.isEmpty else { return }

        chunks.append(contentsOf: newChunks)
        isBuilt = false

        Log.tool.info("Ingested \(newChunks.count) chunks from '\(title)'")
    }

    /// Ingest multiple documents at once.
    public func ingestBatch(_ documents: [(content: String, title: String, metadata: [String: String])]) async throws {
        for doc in documents {
            try await ingest(content: doc.content, title: doc.title, metadata: doc.metadata)
        }
    }

    /// Build or rebuild the search index from all ingested chunks.
    public func buildIndex() async throws {
        guard !chunks.isEmpty else { return }

        // CONTEXTUAL ENRICHMENT — run before embedding so that both the HNSW
        // vectors and the BM25 index are built from context-prefixed text.
        let enrichedTexts: [String]
        if let enricher = contextualEnricher {
            // Reconstruct each document's full text from its chunks so the enricher
            // can use it as a context window for the LLM generator (or fallback).
            var docContents: [String: String] = [:]
            for chunk in chunks {
                docContents[chunk.sourceID, default: ""] += chunk.content + "\n"
            }

            var enriched: [EnrichedChunk] = []
            enriched.reserveCapacity(chunks.count)
            for (i, chunk) in chunks.enumerated() {
                let docContent = docContents[chunk.sourceID] ?? ""
                let ec = await enricher.enrich(
                    chunk: chunk,
                    documentContent: docContent,
                    allChunks: chunks
                )
                enriched.append(ec)

                // Store context description and entities back into the chunk's
                // metadata so they are available at search/citation time.
                var newMeta = chunk.metadata
                newMeta["contextDescription"] = ec.contextDescription
                if !ec.entities.isEmpty {
                    newMeta["entities"] = ec.entities.joined(separator: ", ")
                }
                chunks[i] = DocumentChunk(
                    id: chunk.id,
                    content: chunk.content,
                    sourceID: chunk.sourceID,
                    sourceTitle: chunk.sourceTitle,
                    chunkIndex: chunk.chunkIndex,
                    metadata: newMeta
                )
            }
            enrichedTexts = enriched.map(\.enrichedContent)
        } else {
            enrichedTexts = chunks.map(\.content)
        }

        let total = enrichedTexts.count

        // 1. Compute embeddings in batches with progress
        onProgress?(IngestionProgress(phase: .embedding(current: 0, total: total)))
        let batchSize = 32
        var allEmbeddings: [[Float]] = []
        allEmbeddings.reserveCapacity(total)

        for batchStart in stride(from: 0, to: total, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, total)
            let batch = Array(enrichedTexts[batchStart..<batchEnd])
            let batchEmbeddings = try await embeddingProvider.embed(batch)
            allEmbeddings.append(contentsOf: batchEmbeddings)
            onProgress?(IngestionProgress(phase: .embedding(current: batchEnd, total: total)))
        }

        // 2. Build HNSW graph
        onProgress?(IngestionProgress(phase: .buildingIndex))
        await graph.build(vectors: allEmbeddings)

        // 3. Build BM25 index
        bm25 = BM25Index(documents: enrichedTexts)

        // 4. Compute and stamp recency scores into chunk metadata
        computeRecencyScores()

        isBuilt = true
        onProgress?(IngestionProgress(phase: .done))
        let count = self.chunks.count
        let dim = self.embeddingProvider.dimension
        Log.tool.info("Index built: \(count) chunks, dim=\(dim)")

        // Persist if backend is available
        await saveToPersistence(agentID: nil)
    }

    /// Save current index state to persistence.
    /// If agentID is nil, skips (caller must pass agentID via saveToPersistence(agentID:)).
    private func saveToPersistence(agentID: String?) async {
        guard let persistence, let agentID else { return }
        do {
            try await persistence.saveChunks(chunks, agentID: agentID)
            let csr = await graph.exportCSR()
            let nodeCount = await graph.nodeCount
            try await persistence.saveGraph(agentID: agentID, offsets: csr.offsets, neighbors: csr.neighbors, nodeCount: nodeCount)
            Log.tool.info("Knowledge index persisted for agent \(agentID)")
        } catch {
            Log.tool.error("Failed to persist knowledge index: \(error.localizedDescription)")
        }
    }

    /// Save index to persistence for a specific agent ID.
    public func persistIndex(agentID: String) async {
        await saveToPersistence(agentID: agentID)
    }

    /// Load index from persistence. Returns true if data was loaded.
    public func loadFromPersistence(agentID: String) async throws -> Bool {
        guard let persistence else { return false }

        let savedChunks = try await persistence.loadChunks(agentID: agentID)
        guard !savedChunks.isEmpty else { return false }

        self.chunks = savedChunks

        // Rebuild BM25
        let texts = chunks.map(\.content)
        bm25 = BM25Index(documents: texts)

        // Load graph topology
        if let graphData = try await persistence.loadGraph(agentID: agentID) {
            await graph.importCSR(offsets: graphData.offsets, neighbors: graphData.neighbors, nodeCount: graphData.nodeCount)
        }

        // Recompute embeddings and rebuild graph for proper search
        // (LEANN-style: graph topology guides search, embeddings recomputed on demand)
        let total = texts.count
        onProgress?(IngestionProgress(phase: .embedding(current: 0, total: total)))
        let batchSize = 32
        var allEmbeddings: [[Float]] = []
        allEmbeddings.reserveCapacity(total)

        for batchStart in stride(from: 0, to: total, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, total)
            let batch = Array(texts[batchStart..<batchEnd])
            let batchEmbeddings = try await embeddingProvider.embed(batch)
            allEmbeddings.append(contentsOf: batchEmbeddings)
            onProgress?(IngestionProgress(phase: .embedding(current: batchEnd, total: total)))
        }

        onProgress?(IngestionProgress(phase: .buildingIndex))
        await graph.build(vectors: allEmbeddings)

        isBuilt = true
        onProgress?(IngestionProgress(phase: .done))
        Log.tool.info("Knowledge index loaded from persistence: \(self.chunks.count) chunks")
        return true
    }

    // MARK: - Search

    /// Hybrid search combining HNSW vector recall and BM25 keyword recall via Reciprocal Rank Fusion.
    ///
    /// RRF replaces the former linear score blend. It is more robust to score-scale differences
    /// between the two retrievers because it works on ranks, not raw scores. The formula is:
    ///   `rrfScore(d) = Σ 1 / (k + rank_i(d))`  where k = 60 (standard constant).
    ///
    /// After RRF ranking an optional NLEmbedding cosine-similarity reranker refines the top
    /// candidates (controlled by `config.enableReranking`). A recency boost is then applied
    /// for documents that carry `documentDate` metadata, and same-section chunks from older
    /// versions of the same document family are deduplicated from the final result set.
    public func hybridSearch(query: String, limit: Int = 5) async throws -> [DocumentChunk] {
        if !isBuilt { try await buildIndex() }
        guard !chunks.isEmpty else { return [] }

        // ── 0. HyDE: generate a hypothetical answer and embed it ─────────────────
        // The hypothesis lives in the same embedding space as real document chunks,
        // so searching with it dramatically improves recall for factual queries where
        // the user's vocabulary differs from the indexed text.
        var hydeVec: [Float]? = nil
        if let generator = hydeGenerator {
            let hypothesis = await generator(query)
            if let hyp = hypothesis, !hyp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let hydeEmbedding = try await embeddingProvider.embed([hyp])
                hydeVec = hydeEmbedding.first
                Log.tool.debug("HyDE hypothesis generated (\(hyp.count) chars)")
            }
        }

        // ── 1. Vector recall via HNSW ────────────────────────────────────────────
        let queryEmbedding = try await embeddingProvider.embed([query])
        guard let qVec = queryEmbedding.first else { return [] }

        // Fetch enough HNSW candidates to feed both RRF and the reranker.
        let rrfCandidateCount = min(limit * 3, chunks.count)
        let graphResults = await graph.search(query: qVec, k: rrfCandidateCount, ef: config.searchEF)

        // HyDE HNSW search (separate pass with hypothesis embedding).
        var hydeGraphResults: [(id: Int, distance: Float)] = []
        if let hVec = hydeVec {
            hydeGraphResults = await graph.search(query: hVec, k: rrfCandidateCount, ef: config.searchEF)
        }

        // ── 2. BM25 recall ───────────────────────────────────────────────────────
        let bm25Scores = bm25?.score(query: query) ?? Array(repeating: 0.0, count: chunks.count)

        // ── 3. Reciprocal Rank Fusion ────────────────────────────────────────────
        // k = 60 is the standard RRF constant that balances precision/recall trade-offs.
        let rrfK: Double = 60

        // Build vector rank map: chunkIndex → rank (0 = closest).
        var vectorRank: [Int: Int] = [:]
        for (rank, result) in graphResults.enumerated() {
            vectorRank[result.id] = rank
        }

        // Build HyDE rank map.
        var hydeRank: [Int: Int] = [:]
        for (rank, result) in hydeGraphResults.enumerated() {
            hydeRank[result.id] = rank
        }

        // Build BM25 rank map by sorting all chunks by BM25 score descending.
        let bm25Ranked = bm25Scores.enumerated()
            .sorted { $0.element > $1.element }
            .map(\.offset) // ordered list of chunk indices, best first
        var bm25Rank: [Int: Int] = [:]
        for (rank, idx) in bm25Ranked.enumerated() {
            bm25Rank[idx] = rank
        }

        // Missing-list penalty: a chunk absent from one list gets rank = totalChunks.
        // This is the standard RRF treatment — it still contributes, just weakly.
        let totalChunks = chunks.count

        // Collect the union of all candidates from all lists.
        var candidateSet = Set<Int>(graphResults.map(\.id))
        candidateSet.formUnion(hydeGraphResults.map(\.id))
        // Also include top BM25 hits not already in the vector result set so that
        // pure-keyword matches can still surface via RRF.
        for idx in bm25Ranked.prefix(limit * 2) {
            candidateSet.insert(idx)
        }

        let hydeEnabled = hydeVec != nil

        // Compute RRF score for each candidate, then apply recency boost.
        var rrfScored: [(index: Int, score: Double)] = candidateSet.map { idx in
            let vr = Double(vectorRank[idx] ?? totalChunks)
            let br = Double(bm25Rank[idx] ?? totalChunks)
            var score = 1.0 / (rrfK + vr) + 1.0 / (rrfK + br)
            // Add HyDE signal when available — third independent rank list.
            if hydeEnabled {
                let hr = Double(hydeRank[idx] ?? totalChunks)
                score += 1.0 / (rrfK + hr)
            }

            // Recency boost: multiply by the pre-computed recencyScore (0 < x ≤ 1.0).
            // Chunks without a documentDate metadata key default to 0.95 (slight penalty
            // vs. dated docs so users are nudged to add dates to their documents).
            let recencyScore = chunks[idx].metadata["recencyScore"].flatMap(Double.init) ?? 0.95
            score *= recencyScore

            return (index: idx, score: score)
        }

        rrfScored.sort { $0.score > $1.score }

        // ── 4. Optional reranking ────────────────────────────────────────────────
        let candidatesForReranking: Int
        if config.enableReranking {
            candidatesForReranking = min(limit * config.initialRetrievalMultiplier, rrfScored.count)
        } else {
            candidatesForReranking = min(limit, rrfScored.count)
        }

        let topCandidateChunks = rrfScored.prefix(candidatesForReranking).map { chunks[$0.index] }

        let reranked: [DocumentChunk]
        if config.enableReranking && topCandidateChunks.count > limit {
            reranked = await rerank(query: query, chunks: Array(topCandidateChunks), limit: limit)
        } else {
            reranked = Array(topCandidateChunks.prefix(limit))
        }

        // ── 5. Family deduplication ──────────────────────────────────────────────
        // When the same document section (same family + chunkIndex) appears from multiple
        // versions, keep only the highest-ranked one (already sorted by recency-boosted score).
        var seenFamilySection = Set<String>()
        var deduplicated: [DocumentChunk] = []
        for chunk in reranked {
            let family = chunk.metadata["documentFamily"] ?? ""
            // Key = family:chunkIndex — identifies the same *section* across versions.
            // Empty family means we can't group, so use the unique chunk id to pass through.
            let sectionKey = family.isEmpty ? chunk.id : "\(family):\(chunk.chunkIndex)"
            if seenFamilySection.insert(sectionKey).inserted {
                deduplicated.append(chunk)
            }
            if deduplicated.count >= limit { break }
        }

        return deduplicated
    }

    // MARK: - Private: Reranker

    /// Second-pass reranker using exact NLEmbedding cosine similarity.
    ///
    /// HNSW search is approximate; this pass uses the full NLEmbedding vector to compute
    /// exact cosine similarity between the query and each candidate chunk, providing a more
    /// precise relevance signal at the cost of O(n) embedding lookups (n = candidateCount).
    private func rerank(query: String, chunks: [DocumentChunk], limit: Int) async -> [DocumentChunk] {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else {
            return Array(chunks.prefix(limit))
        }
        guard let queryVec = embedding.vector(for: query) else {
            return Array(chunks.prefix(limit))
        }

        // Score each chunk by cosine similarity to the query.
        // Use the contextDescription prefix when available (Contextual RAG), because that
        // text was specifically generated to describe the chunk's role in its document and
        // tends to encode query-relevant vocabulary more densely than raw chunk text alone.
        let scored: [(DocumentChunk, Float)] = chunks.compactMap { chunk in
            let text: String
            if let ctx = chunk.metadata["contextDescription"], !ctx.isEmpty {
                // Combine context with chunk text (capped to keep embedding quality high).
                text = ctx + " " + String(chunk.content.prefix(400))
            } else {
                text = String(chunk.content.prefix(500))
            }
            guard let chunkVec = embedding.vector(for: text) else { return nil }
            let similarity = cosineSimilarity(queryVec.map { Float($0) }, chunkVec.map { Float($0) })
            return (chunk, similarity)
        }

        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    /// Cosine similarity between two equal-length Float vectors.
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let dot = zip(a, b).reduce(Float(0)) { $0 + $1.0 * $1.1 }
        let magA = sqrt(a.reduce(Float(0)) { $0 + $1 * $1 })
        let magB = sqrt(b.reduce(Float(0)) { $0 + $1 * $1 })
        guard magA > 0, magB > 0 else { return 0 }
        return dot / (magA * magB)
    }

    // MARK: - Private: Recency Scoring

    /// Reads `documentDate` and `documentFamily` metadata from all chunks and stamps a
    /// `recencyScore` (0 < x ≤ 1.0) back into each chunk's metadata.
    ///
    /// Algorithm:
    /// 1. Parse `documentDate` (ISO8601) for every sourceID.
    /// 2. Group sourceIDs by their `documentFamily`.
    /// 3. Within each family, rank documents newest-first. The newest gets 1.0;
    ///    each year of age applies `config.recencyDecayPerYear` multiplicatively.
    /// 4. Chunks with no `documentDate` receive 0.95 — a small penalty that nudges
    ///    users to provide dated documents without outright suppressing undated ones.
    private func computeRecencyScores() {
        let iso = ISO8601DateFormatter()
        let now = Date()
        let secondsPerYear: Double = 365.25 * 24 * 3600

        // ── Collect one date per sourceID ────────────────────────────────────────
        // A sourceID (UUID) maps to one logical document at ingest time.
        // We use the first dated chunk we see for that sourceID.
        var sourceIDToDate: [String: Date] = [:]
        var sourceIDToFamily: [String: String] = [:]

        for chunk in chunks {
            let sid = chunk.sourceID
            if sourceIDToDate[sid] == nil,
               let dateStr = chunk.metadata["documentDate"],
               let date = iso.date(from: dateStr) {
                sourceIDToDate[sid] = date
            }
            if sourceIDToFamily[sid] == nil,
               let family = chunk.metadata["documentFamily"], !family.isEmpty {
                sourceIDToFamily[sid] = family
            }
        }

        // Store for potential future use (e.g. citations).
        documentDates = sourceIDToDate

        // ── Group by family and compute per-sourceID recency scores ──────────────
        // familyToSourceIDs: family → set of sourceIDs that belong to that family
        var familyToSourceIDs: [String: [String]] = [:]
        for (sid, family) in sourceIDToFamily {
            familyToSourceIDs[family, default: []].append(sid)
        }

        var sourceIDRecencyScore: [String: Double] = [:]

        for (_, sourceIDs) in familyToSourceIDs {
            // Sort newest first; undated sources go to the end.
            let sorted = sourceIDs.sorted { a, b in
                let da = sourceIDToDate[a] ?? .distantPast
                let db = sourceIDToDate[b] ?? .distantPast
                return da > db
            }

            // Identify the newest dated source to anchor relative scoring.
            let newestDate = sorted.compactMap { sourceIDToDate[$0] }.first ?? now

            for sid in sorted {
                if let date = sourceIDToDate[sid] {
                    // Age in fractional years relative to the newest document in the family.
                    let ageSecs = newestDate.timeIntervalSince(date)
                    let ageYears = max(ageSecs / secondsPerYear, 0)
                    let score = pow(config.recencyDecayPerYear, ageYears)
                    sourceIDRecencyScore[sid] = score
                } else {
                    // Undated: slight penalty vs. a freshly-dated document.
                    sourceIDRecencyScore[sid] = 0.95
                }
            }
        }

        // ── Stamp recencyScore into every chunk ──────────────────────────────────
        for i in chunks.indices {
            let sid = chunks[i].sourceID
            guard let score = sourceIDRecencyScore[sid] else { continue }

            // Also tag whether this source is the newest in its family so citations
            // can display "← latest" or "← superseded" labels.
            let family = sourceIDToFamily[sid] ?? ""
            let isLatest: Bool
            if !family.isEmpty,
               let familySources = familyToSourceIDs[family],
               let latestSid = familySources.sorted(by: { (sourceIDToDate[$0] ?? .distantPast) > (sourceIDToDate[$1] ?? .distantPast) }).first {
                isLatest = latestSid == sid
            } else {
                isLatest = true // No family context — treat as latest.
            }

            var newMeta = chunks[i].metadata
            newMeta["recencyScore"] = String(format: "%.4f", score)
            newMeta["isLatestVersion"] = isLatest ? "true" : "false"
            chunks[i] = DocumentChunk(
                id: chunks[i].id,
                content: chunks[i].content,
                sourceID: chunks[i].sourceID,
                sourceTitle: chunks[i].sourceTitle,
                chunkIndex: chunks[i].chunkIndex,
                metadata: newMeta
            )
        }
    }

    // MARK: - KnowledgeSource Conformance

    public func insert(content: String, metadata: [String: String]) async throws {
        let title = metadata["title"] ?? "Untitled"
        try await ingest(content: content, title: title, metadata: metadata)
    }

    public func search(query: String, limit: Int) async throws -> [KnowledgeDocument] {
        let results = try await hybridSearch(query: query, limit: limit)
        return results.enumerated().map { index, chunk in
            var meta = chunk.metadata
            meta["sourceTitle"] = chunk.sourceTitle
            meta["chunkIndex"] = String(chunk.chunkIndex)
            return KnowledgeDocument(
                id: chunk.id,
                content: chunk.content,
                metadata: meta,
                score: Float(results.count - index) / Float(max(results.count, 1))
            )
        }
    }

    public func delete(id: String) async throws {
        chunks.removeAll { $0.id == id || $0.sourceID == id }
        isBuilt = false
    }

    // MARK: - Stats

    /// Number of indexed chunks.
    public var chunkCount: Int { chunks.count }

    /// Number of unique source documents.
    public var sourceCount: Int { Set(chunks.map(\.sourceID)).count }

    /// Whether the index has been built.
    public var indexBuilt: Bool { isBuilt }

    /// All indexed chunks.
    public var allChunks: [DocumentChunk] { chunks }
}

// MARK: - Document Loaders

/// Loads documents from various file formats.
public struct DocumentLoader: Sendable {

    public init() {}

    /// Load a plain text file.
    public func loadText(at path: String) throws -> (content: String, title: String) {
        let url = URL(fileURLWithPath: path)
        let content = try String(contentsOf: url, encoding: .utf8)
        let title = url.lastPathComponent
        return (content, title)
    }

    /// Load all text files from a directory.
    public func loadDirectory(
        at path: String,
        extensions: Set<String> = ["txt", "md", "swift", "py", "js", "ts", "json", "yaml", "yml", "toml", "csv", "pdf", "pptx"]
    ) throws -> [(content: String, title: String, metadata: [String: String])] {
        let url = URL(fileURLWithPath: path)
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [(String, String, [String: String])] = []

        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            guard extensions.contains(ext) else { continue }

            do {
                switch ext {
                #if canImport(PDFKit)
                case "pdf":
                    let pdfDocs = try loadPDF(at: fileURL.path)
                    results.append(contentsOf: pdfDocs)
                #endif
                case "pptx":
                    // Skip temp lock files
                    guard !fileURL.lastPathComponent.hasPrefix("~$") else { continue }
                    let pptxDocs = try loadPPTX(at: fileURL.path)
                    results.append(contentsOf: pptxDocs)
                default:
                    let content = try String(contentsOf: fileURL, encoding: .utf8)
                    let relativePath = fileURL.path.replacingOccurrences(of: path, with: "")
                    results.append((
                        content,
                        fileURL.lastPathComponent,
                        ["path": relativePath, "extension": fileURL.pathExtension]
                    ))
                }
            } catch {
                Log.tool.warning("Skipping unreadable file: \(fileURL.lastPathComponent) - \(error.localizedDescription)")
            }
        }

        return results
    }

    /// Load a PDF file using PDFKit.
    ///
    /// Extracts text from all pages. Returns per-page content with metadata.
    /// Scanned PDFs without embedded text will return empty results.
    #if canImport(PDFKit)
    public func loadPDF(at path: String) throws -> [(content: String, title: String, metadata: [String: String])] {
        let url = URL(fileURLWithPath: path)
        guard let document = PDFKit.PDFDocument(url: url) else {
            throw SBBenderError.skillExecutionFailed(skill: "DocumentLoader", reason: "Cannot open PDF: \(url.lastPathComponent)")
        }

        let title = url.deletingPathExtension().lastPathComponent
        var results: [(String, String, [String: String])] = []
        let pageCount = document.pageCount

        for pageIndex in 0..<pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            guard let content = page.string, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            results.append((
                content,
                "\(title) (p\(pageIndex + 1))",
                ["page": String(pageIndex + 1), "totalPages": String(pageCount), "extension": "pdf", "path": path]
            ))
        }

        if results.isEmpty {
            Log.tool.warning("PDF has no extractable text (may be scanned): \(url.lastPathComponent)")
        }

        return results
    }
    #endif

    /// Load a PPTX (PowerPoint) file.
    ///
    /// PPTX is a ZIP archive containing XML slide files.
    /// Extracts text from all `<a:t>` tags in slide XML.
    public func loadPPTX(at path: String) throws -> [(content: String, title: String, metadata: [String: String])] {
        let url = URL(fileURLWithPath: path)
        let title = url.deletingPathExtension().lastPathComponent

        // PPTX is a ZIP — use Archive from Foundation
        let data = try Data(contentsOf: url)

        // Find PK signature (ZIP magic number)
        guard data.count > 4, data[0] == 0x50, data[1] == 0x4B else {
            throw SBBenderError.skillExecutionFailed(skill: "DocumentLoader", reason: "Not a valid PPTX/ZIP file: \(url.lastPathComponent)")
        }

        // Extract slide XML entries using Process + unzip
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", path, "ppt/slides/*.xml", "-d", tempDir.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        let slidesDir = tempDir.appendingPathComponent("ppt/slides")
        let fm = FileManager.default

        guard fm.fileExists(atPath: slidesDir.path) else {
            Log.tool.warning("No slides found in PPTX: \(url.lastPathComponent)")
            return []
        }

        let slideFiles = try fm.contentsOfDirectory(at: slidesDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "xml" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        var results: [(String, String, [String: String])] = []

        for (index, slideFile) in slideFiles.enumerated() {
            let xmlData = try Data(contentsOf: slideFile)
            let xmlString = String(data: xmlData, encoding: .utf8) ?? ""

            // Extract text from <a:t> tags
            let texts = Self.extractPPTXText(from: xmlString)
            let content = texts.joined(separator: " ")

            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            results.append((
                content,
                "\(title) (slide \(index + 1))",
                ["slide": String(index + 1), "totalSlides": String(slideFiles.count), "extension": "pptx", "path": path]
            ))
        }

        return results
    }

    // MARK: - Document Versioning Helpers

    /// Attempt to extract the document's effective date from its filename or first-page text.
    ///
    /// Resolution order:
    /// 1. Filename date patterns (ISO, year-quarter, year-month, bare year).
    /// 2. Common "effective / updated / dated" prefixes in the first 1000 characters of text.
    /// 3. File modification date from the filesystem (final fallback).
    ///
    /// Returns `nil` only if no date signal is found anywhere.
    public static func extractDocumentDate(
        from filename: String,
        firstPageText: String,
        fileURL: URL? = nil
    ) -> Date? {
        let calendar = Calendar.current
        let basename = (filename as NSString).lastPathComponent

        // ── 1. Filename patterns ─────────────────────────────────────────────────
        // Try full ISO date first, then progressively coarser patterns.
        struct FilenamePattern {
            let regex: String
            let parse: (String) -> Date?
        }

        let filenamePatterns: [FilenamePattern] = [
            // 2024-01-15 or 2024_01_15
            FilenamePattern(regex: #"(\d{4})[-_](\d{2})[-_](\d{2})"#) { matched in
                let parts = matched.components(separatedBy: CharacterSet(charactersIn: "-_"))
                guard parts.count >= 3,
                      let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
                var comps = DateComponents(); comps.year = y; comps.month = m; comps.day = d
                return calendar.date(from: comps)
            },
            // 2024-Q1 or 2024_Q3
            FilenamePattern(regex: #"(\d{4})[-_](Q[1-4])"#) { matched in
                let parts = matched.components(separatedBy: CharacterSet(charactersIn: "-_"))
                guard parts.count >= 2, let year = Int(parts[0]) else { return nil }
                let qStr = parts[1].uppercased()
                let month: Int
                switch qStr {
                case "Q1": month = 1
                case "Q2": month = 4
                case "Q3": month = 7
                case "Q4": month = 10
                default: return nil
                }
                var comps = DateComponents(); comps.year = year; comps.month = month; comps.day = 1
                return calendar.date(from: comps)
            },
            // 2024-01 or 2024_12
            FilenamePattern(regex: #"(\d{4})[-_](\d{2})(?![-_\d])"#) { matched in
                let parts = matched.components(separatedBy: CharacterSet(charactersIn: "-_"))
                guard parts.count >= 2,
                      let y = Int(parts[0]), let m = Int(parts[1]),
                      m >= 1, m <= 12 else { return nil }
                var comps = DateComponents(); comps.year = y; comps.month = m; comps.day = 1
                return calendar.date(from: comps)
            },
            // Bare 4-digit year between 1990 and 2099
            FilenamePattern(regex: #"(?<!\d)((?:19|20)\d{2})(?!\d)"#) { matched in
                guard let year = Int(matched), year >= 1990, year <= 2099 else { return nil }
                var comps = DateComponents(); comps.year = year; comps.month = 1; comps.day = 1
                return calendar.date(from: comps)
            },
        ]

        for pattern in filenamePatterns {
            if let range = basename.range(of: pattern.regex, options: .regularExpression),
               let date = pattern.parse(String(basename[range])) {
                return date
            }
        }

        // ── 2. First-page text prefixes ──────────────────────────────────────────
        let snippet = String(firstPageText.prefix(1_000))
        let nsSnippet = snippet as NSString

        // Matches patterns like "Effective date: January 2025", "Updated: 2024-01-15",
        // "Dated: March 5, 2024", "Issued: 2024-Q2", etc.
        let textPatternStr = #"(?:effective|updated|dated?|published|issued|revised)[:\s]+([A-Za-z]+\s+\d{1,2},?\s+\d{4}|[A-Za-z]+\s+\d{4}|\d{4}[-/]\d{2}[-/]\d{2}|\d{4}[-_]Q[1-4])"#
        if let regex = try? NSRegularExpression(pattern: textPatternStr, options: .caseInsensitive),
           let match = regex.firstMatch(in: snippet, range: NSRange(location: 0, length: nsSnippet.length)),
           match.numberOfRanges > 1 {
            let dateStr = nsSnippet.substring(with: match.range(at: 1))
            let formatters = ["MMMM d, yyyy", "MMMM d yyyy", "MMMM yyyy", "MMM d, yyyy",
                              "MMM d yyyy", "MMM yyyy", "yyyy-MM-dd", "yyyy/MM/dd"]
            for fmt in formatters {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = fmt
                if let d = f.date(from: dateStr) { return d }
            }
        }

        // ── 3. File modification date fallback ───────────────────────────────────
        if let url = fileURL,
           let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let mtime = attrs[.modificationDate] as? Date {
            return mtime
        }

        return nil
    }

    /// Derive a stable "family name" from a filename by stripping version tokens,
    /// dates, and normalizing whitespace/case.
    ///
    /// Documents in the same family share semantically equivalent content across versions.
    /// Example: "Contract_v2_2024-01.pdf" and "Contract_final_2025.pdf" → "contract".
    public static func extractDocumentFamily(from filename: String) -> String {
        var name = ((filename as NSString).lastPathComponent as NSString).deletingPathExtension

        // Strip common version tokens and date patterns.
        let patterns = [
            #"\bv\d+(\.\d+)*\b"#,                    // v1, v2.1, v10
            #"\b(final|draft|updated|revised|copy|old|new|backup|temp|latest|current)\b"#,
            #"\b(?:19|20)\d{2}[-_]?(?:Q[1-4]|H[12])?\b"#, // years, year-quarter, year-half
            #"\b\d{2}[-_]\d{2}[-_]\d{4}\b"#,          // MM-DD-YYYY
            #"\b\d{4}[-_]\d{2}[-_]\d{2}\b"#,          // YYYY-MM-DD
            #"\b\d{4}[-_]\d{2}\b"#,                   // YYYY-MM
            #"[-_]+"#,                                 // remaining separators → spaces
        ]

        for pattern in patterns {
            name = name.replacingOccurrences(
                of: pattern,
                with: " ",
                options: .regularExpression,
                range: nil
            )
        }

        // Normalize: collapse spaces, trim, lowercase.
        name = name
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
            .lowercased()

        return name.isEmpty ? "unknown" : name
    }

    /// Extract text content from PPTX slide XML by finding `<a:t>` elements.
    private static func extractPPTXText(from xml: String) -> [String] {
        var texts: [String] = []
        var searchRange = xml.startIndex..<xml.endIndex

        let openTag = "<a:t>"
        let closeTag = "</a:t>"

        while let openRange = xml.range(of: openTag, range: searchRange) {
            let contentStart = openRange.upperBound
            guard let closeRange = xml.range(of: closeTag, range: contentStart..<xml.endIndex) else { break }
            let text = String(xml[contentStart..<closeRange.lowerBound])
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                texts.append(text)
            }
            searchRange = closeRange.upperBound..<xml.endIndex
        }

        return texts
    }

    /// Load an Apple Mail mailbox (.mbox format).
    public func loadMbox(at path: String) throws -> [(content: String, title: String, metadata: [String: String])] {
        let url = URL(fileURLWithPath: path)
        let content = try String(contentsOf: url, encoding: .utf8)

        var emails: [(String, String, [String: String])] = []
        let messages = content.components(separatedBy: "\nFrom ")

        for (index, message) in messages.enumerated() {
            let lines = message.components(separatedBy: "\n")
            var subject = "Email #\(index + 1)"
            var from = ""
            var date = ""
            var body = ""
            var headersDone = false

            for line in lines {
                if !headersDone {
                    if line.hasPrefix("Subject: ") {
                        subject = String(line.dropFirst(9))
                    } else if line.hasPrefix("From: ") {
                        from = String(line.dropFirst(6))
                    } else if line.hasPrefix("Date: ") {
                        date = String(line.dropFirst(6))
                    } else if line.isEmpty {
                        headersDone = true
                    }
                } else {
                    body += line + "\n"
                }
            }

            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            emails.append((
                body,
                subject,
                ["from": from, "date": date, "type": "email"]
            ))
        }

        return emails
    }
}
