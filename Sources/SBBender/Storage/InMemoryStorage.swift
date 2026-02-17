import Foundation

/// In-memory storage backend for testing and lightweight use cases.
public actor InMemoryStorage: StorageBackend {
    private var sessions: [String: Session] = [:]
    private var memories: [String: UserMemory] = [:]
    private var knowledgeEntries: [String: KnowledgeEntry] = [:]
    private var learnings: [String: LearningRecord] = [:]

    public init() {}

    // MARK: - Sessions

    public func getSession(id: String) async throws -> Session? {
        sessions[id]
    }

    public func upsertSession(_ session: Session) async throws {
        sessions[session.id] = session
    }

    public func deleteSession(id: String) async throws {
        sessions.removeValue(forKey: id)
    }

    public func listSessions(agentID: String?) async throws -> [Session] {
        let all = Array(sessions.values)
        if let agentID {
            return all.filter { $0.agentID == agentID }.sorted { $0.updatedAt > $1.updatedAt }
        }
        return all.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Memories

    public func getMemories(userID: String) async throws -> [UserMemory] {
        memories.values.filter { $0.userID == userID }.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func upsertMemory(_ memory: UserMemory) async throws {
        memories[memory.id] = memory
    }

    public func deleteMemory(id: String) async throws {
        memories.removeValue(forKey: id)
    }

    // MARK: - Knowledge

    public func getKnowledgeEntries() async throws -> [KnowledgeEntry] {
        Array(knowledgeEntries.values).sorted { $0.insertedAt > $1.insertedAt }
    }

    public func upsertKnowledgeEntry(_ entry: KnowledgeEntry) async throws {
        knowledgeEntries[entry.id] = entry
    }

    // MARK: - Learnings

    public func getLearnings(userID: String, store: String) async throws -> [LearningRecord] {
        learnings.values
            .filter { $0.userID == userID && $0.store == store }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func upsertLearning(_ record: LearningRecord) async throws {
        learnings[record.id] = record
    }
}
