import Foundation

/// Configuration for a learning store.
public struct LearningStoreConfig: Sendable {
    public let enabled: Bool
    public let mode: LearningMode

    public init(enabled: Bool = true, mode: LearningMode = .always) {
        self.enabled = enabled
        self.mode = mode
    }

    public static let disabled = LearningStoreConfig(enabled: false)
    public static let enabled = LearningStoreConfig(enabled: true)
}

/// When the learning engine processes messages.
public enum LearningMode: String, Sendable, Codable {
    /// Learn after every run.
    case always
    /// Agent decides when to learn (via tool calls).
    case agentic
}

/// The learning engine coordinates multiple learning stores to accumulate
/// knowledge across conversations.
///
/// Inspired by Agno's LearningMachine, adapted for Swift concurrency.
public actor LearningEngine {
    private let storage: any StorageBackend
    private let userID: String

    public let userProfile: LearningStoreConfig
    public let userMemory: LearningStoreConfig
    public let sessionContext: LearningStoreConfig
    public let entityMemory: LearningStoreConfig

    public init(
        storage: any StorageBackend,
        userID: String,
        userProfile: LearningStoreConfig = .enabled,
        userMemory: LearningStoreConfig = .enabled,
        sessionContext: LearningStoreConfig = .enabled,
        entityMemory: LearningStoreConfig = .disabled
    ) {
        self.storage = storage
        self.userID = userID
        self.userProfile = userProfile
        self.userMemory = userMemory
        self.sessionContext = sessionContext
        self.entityMemory = entityMemory
    }

    /// Recall all stored context for the current user, formatted for the system prompt.
    public func recall(sessionID: String) async throws -> String {
        var parts: [String] = []

        if userProfile.enabled {
            let records = try await storage.getLearnings(userID: userID, store: "user_profile")
            if !records.isEmpty {
                let items = records.map { "- \($0.key): \($0.value)" }.joined(separator: "\n")
                parts.append("### User Profile\n\(items)")
            }
        }

        if userMemory.enabled {
            let memories = try await storage.getMemories(userID: userID)
            if !memories.isEmpty {
                let items = memories.prefix(10).map { "- \($0.content)" }.joined(separator: "\n")
                parts.append("### User Memories\n\(items)")
            }
        }

        if sessionContext.enabled {
            let records = try await storage.getLearnings(userID: userID, store: "session_context")
            let sessionRecords = records.filter { $0.key.hasPrefix(sessionID) }
            if !sessionRecords.isEmpty {
                let items = sessionRecords.map { "- \($0.value)" }.joined(separator: "\n")
                parts.append("### Session Context\n\(items)")
            }
        }

        if entityMemory.enabled {
            let records = try await storage.getLearnings(userID: userID, store: "entity_memory")
            if !records.isEmpty {
                let items = records.prefix(20).map { "- \($0.key): \($0.value)" }.joined(separator: "\n")
                parts.append("### Known Entities\n\(items)")
            }
        }

        return parts.isEmpty ? "" : parts.joined(separator: "\n\n")
    }

    /// Process messages after a run to extract and store learnings.
    public func process(messages: [Message], runResult: RunResult) async throws {
        // Extract user preferences from conversation
        if userProfile.enabled && userProfile.mode == .always {
            try await extractUserProfile(from: messages)
        }

        // Store important user memories
        if userMemory.enabled && userMemory.mode == .always {
            try await extractUserMemories(from: messages)
        }

        // Update session context
        if sessionContext.enabled {
            try await updateSessionContext(
                sessionID: runResult.sessionID,
                messages: messages
            )
        }
    }

    /// Add a memory directly.
    public func addMemory(_ content: String, category: String = "general") async throws {
        let memory = UserMemory(
            userID: userID,
            content: content,
            category: category
        )
        try await storage.upsertMemory(memory)
        Log.learning.info("Added memory: \(content.prefix(50))...")
    }

    /// Store a user profile attribute.
    public func setProfileAttribute(key: String, value: String) async throws {
        let record = LearningRecord(
            userID: userID,
            store: "user_profile",
            key: key,
            value: value
        )
        try await storage.upsertLearning(record)
    }

    /// Store an entity memory.
    public func setEntityMemory(entity: String, fact: String) async throws {
        let record = LearningRecord(
            userID: userID,
            store: "entity_memory",
            key: entity,
            value: fact
        )
        try await storage.upsertLearning(record)
    }

    // MARK: - Private Extraction

    private func extractUserProfile(from messages: [Message]) async throws {
        let userMessages = messages.filter { $0.role == .user }
        guard !userMessages.isEmpty else { return }

        // Simple heuristic: look for self-referential statements
        for msg in userMessages {
            let text = msg.text.lowercased()

            // Detect preferences
            if text.contains("i prefer") || text.contains("i like") || text.contains("i always") {
                let record = LearningRecord(
                    userID: userID,
                    store: "user_profile",
                    key: "preference_\(UUID().uuidString.prefix(8))",
                    value: msg.text
                )
                try await storage.upsertLearning(record)
            }
        }
    }

    private func extractUserMemories(from messages: [Message]) async throws {
        // Store the last user message as a potential memory trigger
        guard let lastUserMsg = messages.last(where: { $0.role == .user }) else { return }

        let text = lastUserMsg.text
        // Only store substantial messages
        guard text.count > 20 else { return }

        // Check for explicit memory requests
        let lower = text.lowercased()
        if lower.contains("remember that") || lower.contains("don't forget") || lower.contains("keep in mind") {
            try await addMemory(text, category: "explicit")
        }
    }

    private func updateSessionContext(sessionID: String, messages: [Message]) async throws {
        // Store a summary of what was discussed
        let topics = messages
            .filter { $0.role == .user }
            .map(\.text)
            .joined(separator: " | ")

        guard !topics.isEmpty else { return }

        let record = LearningRecord(
            userID: userID,
            store: "session_context",
            key: "\(sessionID)_topics",
            value: String(topics.prefix(500))
        )
        try await storage.upsertLearning(record)
    }
}
