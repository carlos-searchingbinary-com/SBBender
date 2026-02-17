import Foundation

/// A session persisted to storage.
public struct Session: Sendable, Codable, Identifiable {
    public let id: String
    public let agentID: String
    public var messages: [Message]
    public var state: [String: String]
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        agentID: String = "",
        messages: [Message] = [],
        state: [String: String] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.agentID = agentID
        self.messages = messages
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// A user memory persisted to storage.
public struct UserMemory: Sendable, Codable, Identifiable {
    public let id: String
    public let userID: String
    public let content: String
    public let category: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        userID: String,
        content: String,
        category: String = "general",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userID = userID
        self.content = content
        self.category = category
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Protocol for persistent storage backends.
///
/// The primary implementation is `GRDBStorage` (SQLite), but this can
/// be implemented for any backing store.
public protocol StorageBackend: Sendable {
    // Sessions
    func getSession(id: String) async throws -> Session?
    func upsertSession(_ session: Session) async throws
    func deleteSession(id: String) async throws
    func listSessions(agentID: String?) async throws -> [Session]

    // Memories
    func getMemories(userID: String) async throws -> [UserMemory]
    func upsertMemory(_ memory: UserMemory) async throws
    func deleteMemory(id: String) async throws

    // Knowledge tracking
    func getKnowledgeEntries() async throws -> [KnowledgeEntry]
    func upsertKnowledgeEntry(_ entry: KnowledgeEntry) async throws

    // Learning
    func getLearnings(userID: String, store: String) async throws -> [LearningRecord]
    func upsertLearning(_ record: LearningRecord) async throws
}

/// Tracks a piece of content inserted into the knowledge system.
public struct KnowledgeEntry: Sendable, Codable, Identifiable {
    public let id: String
    public let contentHash: String
    public let source: String
    public let insertedAt: Date

    public init(id: String = UUID().uuidString, contentHash: String, source: String, insertedAt: Date = Date()) {
        self.id = id
        self.contentHash = contentHash
        self.source = source
        self.insertedAt = insertedAt
    }
}

/// A learning record persisted to storage.
public struct LearningRecord: Sendable, Codable, Identifiable {
    public let id: String
    public let userID: String
    public let store: String
    public let key: String
    public let value: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        userID: String,
        store: String,
        key: String,
        value: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userID = userID
        self.store = store
        self.key = key
        self.value = value
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
