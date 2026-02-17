import Foundation

/// A document returned from knowledge search.
public struct KnowledgeDocument: Sendable {
    public let id: String
    public let content: String
    public let metadata: [String: String]
    public let score: Float

    public init(
        id: String = UUID().uuidString,
        content: String,
        metadata: [String: String] = [:],
        score: Float = 1.0
    ) {
        self.id = id
        self.content = content
        self.metadata = metadata
        self.score = score
    }
}

/// Protocol for knowledge sources that provide context to agents.
///
/// Implementations can range from simple text stores to full RAG pipelines
/// with vector search. The PageTree from nolitai is a prime example.
public protocol KnowledgeSource: Sendable {
    /// Insert content into the knowledge base.
    func insert(content: String, metadata: [String: String]) async throws

    /// Search the knowledge base for relevant documents.
    func search(query: String, limit: Int) async throws -> [KnowledgeDocument]

    /// Delete a document by ID.
    func delete(id: String) async throws
}

// MARK: - PageTree Knowledge Source

/// A hierarchical document tree, inspired by nolitai's PageTree.
///
/// Organizes content into a tree of nodes with summaries, time ranges,
/// and speaker attribution. Supports hierarchical search without vector DB.
public struct PageTree: Sendable, Codable {
    public let id: String
    public let title: String
    public var root: PageNode
    public let totalDuration: TimeInterval?

    public init(
        id: String = UUID().uuidString,
        title: String,
        root: PageNode,
        totalDuration: TimeInterval? = nil
    ) {
        self.id = id
        self.title = title
        self.root = root
        self.totalDuration = totalDuration
    }

    public var nodeCount: Int {
        root.flatten().count
    }

    public var leafNodes: [PageNode] {
        root.flatten().filter { $0.children.isEmpty }
    }

    public var allSpeakers: [String] {
        Array(Set(root.flatten().flatMap(\.speakers)))
    }

    /// Search the tree for nodes matching a query (keyword-based).
    public func search(query: String, limit: Int = 5) -> [PageNode] {
        let queryWords = query.lowercased().split(separator: " ").map(String.init)
        let allNodes = root.flatten()

        let scored = allNodes.map { node -> (PageNode, Int) in
            let text = (node.content + " " + node.summary).lowercased()
            let score = queryWords.reduce(0) { acc, word in
                acc + (text.contains(word) ? 1 : 0)
            }
            return (node, score)
        }

        return scored
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }
}

/// A node in a PageTree.
public struct PageNode: Sendable, Codable, Identifiable {
    public let id: String
    public let title: String
    public let summary: String
    public let content: String
    public let startIndex: Int
    public let endIndex: Int
    public let timeRange: ClosedRange<TimeInterval>?
    public let speakers: [String]
    public var children: [PageNode]
    public let confidence: Float

    public init(
        id: String = UUID().uuidString,
        title: String,
        summary: String = "",
        content: String,
        startIndex: Int = 0,
        endIndex: Int = 0,
        timeRange: ClosedRange<TimeInterval>? = nil,
        speakers: [String] = [],
        children: [PageNode] = [],
        confidence: Float = 1.0
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.content = content
        self.startIndex = startIndex
        self.endIndex = endIndex
        self.timeRange = timeRange
        self.speakers = speakers
        self.children = children
        self.confidence = confidence
    }

    /// Flatten the tree into a list of all nodes (pre-order traversal).
    public func flatten() -> [PageNode] {
        var result = [self]
        for child in children {
            result.append(contentsOf: child.flatten())
        }
        return result
    }

    /// Find a node by ID in the subtree.
    public func find(id: String) -> PageNode? {
        if self.id == id { return self }
        for child in children {
            if let found = child.find(id: id) { return found }
        }
        return nil
    }

    /// Get the path from root to a target node.
    public func pathTo(id: String) -> [PageNode]? {
        if self.id == id { return [self] }
        for child in children {
            if var path = child.pathTo(id: id) {
                path.insert(self, at: 0)
                return path
            }
        }
        return nil
    }
}

// Codable conformance for ClosedRange<TimeInterval> via wrapper
extension PageNode {
    private enum CodingKeys: String, CodingKey {
        case id, title, summary, content, startIndex, endIndex
        case timeRangeLower, timeRangeUpper
        case speakers, children, confidence
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        summary = try c.decode(String.self, forKey: .summary)
        content = try c.decode(String.self, forKey: .content)
        startIndex = try c.decode(Int.self, forKey: .startIndex)
        endIndex = try c.decode(Int.self, forKey: .endIndex)
        speakers = try c.decode([String].self, forKey: .speakers)
        children = try c.decode([PageNode].self, forKey: .children)
        confidence = try c.decode(Float.self, forKey: .confidence)

        if let lower = try c.decodeIfPresent(TimeInterval.self, forKey: .timeRangeLower),
           let upper = try c.decodeIfPresent(TimeInterval.self, forKey: .timeRangeUpper) {
            timeRange = lower...upper
        } else {
            timeRange = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(summary, forKey: .summary)
        try c.encode(content, forKey: .content)
        try c.encode(startIndex, forKey: .startIndex)
        try c.encode(endIndex, forKey: .endIndex)
        try c.encode(speakers, forKey: .speakers)
        try c.encode(children, forKey: .children)
        try c.encode(confidence, forKey: .confidence)

        if let range = timeRange {
            try c.encode(range.lowerBound, forKey: .timeRangeLower)
            try c.encode(range.upperBound, forKey: .timeRangeUpper)
        }
    }
}

// MARK: - PageTree as KnowledgeSource

/// Wraps a PageTree to conform to KnowledgeSource.
public actor PageTreeKnowledge: KnowledgeSource {
    private var tree: PageTree

    public init(tree: PageTree) {
        self.tree = tree
    }

    public func insert(content: String, metadata: [String: String]) async throws {
        let node = PageNode(
            title: metadata["title"] ?? "Untitled",
            content: content,
            speakers: metadata["speakers"]?.components(separatedBy: ",") ?? []
        )
        tree.root.children.append(node)
    }

    public func search(query: String, limit: Int) async throws -> [KnowledgeDocument] {
        tree.search(query: query, limit: limit).map { node in
            KnowledgeDocument(
                id: node.id,
                content: node.content,
                metadata: [
                    "title": node.title,
                    "summary": node.summary,
                    "speakers": node.speakers.joined(separator: ", "),
                ],
                score: node.confidence
            )
        }
    }

    public func delete(id: String) async throws {
        func removeNode(from parent: inout PageNode, id: String) -> Bool {
            if let idx = parent.children.firstIndex(where: { $0.id == id }) {
                parent.children.remove(at: idx)
                return true
            }
            for i in parent.children.indices {
                if removeNode(from: &parent.children[i], id: id) {
                    return true
                }
            }
            return false
        }
        _ = removeNode(from: &tree.root, id: id)
    }
}

// MARK: - Simple Text Knowledge

/// A simple in-memory knowledge source backed by text documents.
public actor TextKnowledge: KnowledgeSource {
    private var documents: [KnowledgeDocument] = []

    public init() {}

    public init(documents: [KnowledgeDocument]) {
        self.documents = documents
    }

    public func insert(content: String, metadata: [String: String]) async throws {
        let doc = KnowledgeDocument(content: content, metadata: metadata)
        documents.append(doc)
    }

    public func search(query: String, limit: Int) async throws -> [KnowledgeDocument] {
        let queryWords = query.lowercased().split(separator: " ").map(String.init)

        let scored = documents.map { doc -> (KnowledgeDocument, Int) in
            let text = doc.content.lowercased()
            let score = queryWords.reduce(0) { acc, word in
                acc + (text.contains(word) ? 1 : 0)
            }
            return (doc, score)
        }

        return scored
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    public func delete(id: String) async throws {
        documents.removeAll { $0.id == id }
    }
}
