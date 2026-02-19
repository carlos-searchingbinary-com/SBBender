import Foundation

/// Protocol for persisting DocumentIndexer state (chunks + HNSW graph topology).
///
/// Lives in SBBenderCore so DocumentIndexer can reference it without depending on GRDB.
/// The concrete implementation (GRDBStorage) lives in the SBBender target.
public protocol KnowledgeIndexPersistence: Sendable {
    /// Save document chunks for an agent's knowledge index.
    func saveChunks(_ chunks: [DocumentChunk], agentID: String) async throws

    /// Load previously saved chunks for an agent.
    func loadChunks(agentID: String) async throws -> [DocumentChunk]

    /// Save HNSW graph topology in CSR format.
    func saveGraph(agentID: String, offsets: [Int], neighbors: [Int], nodeCount: Int) async throws

    /// Load persisted HNSW graph topology.
    func loadGraph(agentID: String) async throws -> (offsets: [Int], neighbors: [Int], nodeCount: Int)?

    /// Delete all persisted index data for an agent.
    func deleteIndex(agentID: String) async throws
}
