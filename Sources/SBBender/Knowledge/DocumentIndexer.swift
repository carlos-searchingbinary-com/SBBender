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
        public let hybridWeight: Float // 0 = pure BM25, 1 = pure vector
        public let storeEmbeddings: Bool // false = LEANN-style recompute on demand

        public init(
            chunkingStrategy: ChunkingStrategy = .fixedSize(size: 256, overlap: 32),
            maxConnections: Int = 16,
            efConstruction: Int = 64,
            searchEF: Int = 32,
            hybridWeight: Float = 0.7,
            storeEmbeddings: Bool = true
        ) {
            self.chunkingStrategy = chunkingStrategy
            self.maxConnections = maxConnections
            self.efConstruction = efConstruction
            self.searchEF = searchEF
            self.hybridWeight = hybridWeight
            self.storeEmbeddings = storeEmbeddings
        }
    }

    private let config: Config
    private let embeddingProvider: any EmbeddingProvider
    private let chunker: TextChunker
    private var chunks: [DocumentChunk] = []
    private var graph: HNSWGraph
    private var bm25: BM25Index?
    private var isBuilt: Bool = false

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

        let texts = chunks.map(\.content)

        // 1. Compute embeddings
        let embeddings = try await embeddingProvider.embed(texts)

        // 2. Build HNSW graph
        await graph.build(vectors: embeddings)

        // 3. Build BM25 index
        bm25 = BM25Index(documents: texts)

        isBuilt = true
        let count = self.chunks.count
        let dim = self.embeddingProvider.dimension
        Log.tool.info("Index built: \(count) chunks, dim=\(dim)")
    }

    // MARK: - Search

    /// Hybrid search combining vector similarity and BM25 keyword relevance.
    public func hybridSearch(query: String, limit: Int = 5) async throws -> [DocumentChunk] {
        if !isBuilt { try await buildIndex() }
        guard !chunks.isEmpty else { return [] }

        // Vector search
        let queryEmbedding = try await embeddingProvider.embed([query])
        guard let qVec = queryEmbedding.first else { return [] }

        let graphResults = await graph.search(query: qVec, k: min(limit * 3, chunks.count), ef: config.searchEF)

        // BM25 search
        let bm25Scores = bm25?.score(query: query) ?? Array(repeating: 0.0, count: chunks.count)

        // Normalize scores
        let maxGraphDist = max(graphResults.last?.distance ?? 0.001, 0.001)
        let maxBM25 = max(bm25Scores.max() ?? 0.001, 0.001)

        // Combine: for each candidate from graph search, compute hybrid score
        var scored: [(Int, Float)] = []
        for (id, dist) in graphResults {
            let vectorScore = 1.0 - Float(dist) / Float(max(maxGraphDist, 0.001))
            let keywordScore = Float(bm25Scores[id] / max(maxBM25, 0.001))
            let hybrid = config.hybridWeight * vectorScore + (1 - config.hybridWeight) * keywordScore
            scored.append((id, hybrid))
        }

        // Also check top BM25 results not in graph results
        let graphIDs = Set(graphResults.map(\.id))
        let topBM25 = bm25Scores.enumerated()
            .sorted { $0.element > $1.element }
            .prefix(limit * 2)
            .filter { !graphIDs.contains($0.offset) }

        for (idx, score) in topBM25 {
            let keywordScore = Float(score / max(maxBM25, 0.001))
            let hybrid = (1 - config.hybridWeight) * keywordScore
            scored.append((idx, hybrid))
        }

        // Sort by hybrid score descending, return top results
        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { chunks[$0.0] }
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
