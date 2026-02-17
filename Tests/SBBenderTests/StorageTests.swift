import Testing
import Foundation
@testable import SBBender

@Suite("InMemoryStorage Tests")
struct InMemoryStorageTests {

    @Test("Session CRUD")
    func testSessionCRUD() async throws {
        let storage = InMemoryStorage()

        // Create
        let session = Session(
            id: "s1",
            agentID: "agent-1",
            messages: [.user("Hello"), .assistant("Hi")],
            state: ["key": "value"]
        )
        try await storage.upsertSession(session)

        // Read
        let fetched = try await storage.getSession(id: "s1")
        #expect(fetched != nil)
        #expect(fetched!.agentID == "agent-1")
        #expect(fetched!.messages.count == 2)
        #expect(fetched!.state["key"] == "value")

        // Update
        var updated = session
        updated.state["key"] = "updated"
        try await storage.upsertSession(updated)
        let refetched = try await storage.getSession(id: "s1")
        #expect(refetched!.state["key"] == "updated")

        // Delete
        try await storage.deleteSession(id: "s1")
        let deleted = try await storage.getSession(id: "s1")
        #expect(deleted == nil)
    }

    @Test("List sessions by agent")
    func testListSessions() async throws {
        let storage = InMemoryStorage()

        try await storage.upsertSession(Session(id: "s1", agentID: "a1"))
        try await storage.upsertSession(Session(id: "s2", agentID: "a1"))
        try await storage.upsertSession(Session(id: "s3", agentID: "a2"))

        let a1Sessions = try await storage.listSessions(agentID: "a1")
        #expect(a1Sessions.count == 2)

        let allSessions = try await storage.listSessions(agentID: nil)
        #expect(allSessions.count == 3)
    }

    @Test("Memory CRUD")
    func testMemoryCRUD() async throws {
        let storage = InMemoryStorage()

        let memory = UserMemory(userID: "user-1", content: "User likes coffee", category: "preferences")
        try await storage.upsertMemory(memory)

        let memories = try await storage.getMemories(userID: "user-1")
        #expect(memories.count == 1)
        #expect(memories.first?.content == "User likes coffee")
        #expect(memories.first?.category == "preferences")

        try await storage.deleteMemory(id: memory.id)
        let after = try await storage.getMemories(userID: "user-1")
        #expect(after.isEmpty)
    }

    @Test("Knowledge entry tracking")
    func testKnowledgeEntries() async throws {
        let storage = InMemoryStorage()

        let entry = KnowledgeEntry(contentHash: "abc123", source: "test.pdf")
        try await storage.upsertKnowledgeEntry(entry)

        let entries = try await storage.getKnowledgeEntries()
        #expect(entries.count == 1)
        #expect(entries.first?.contentHash == "abc123")
    }

    @Test("Learning records")
    func testLearningRecords() async throws {
        let storage = InMemoryStorage()

        let record = LearningRecord(
            userID: "user-1",
            store: "user_profile",
            key: "language",
            value: "English"
        )
        try await storage.upsertLearning(record)

        let records = try await storage.getLearnings(userID: "user-1", store: "user_profile")
        #expect(records.count == 1)
        #expect(records.first?.key == "language")
        #expect(records.first?.value == "English")

        // Different store returns empty
        let other = try await storage.getLearnings(userID: "user-1", store: "entity_memory")
        #expect(other.isEmpty)
    }
}

@Suite("GRDBStorage Tests")
struct GRDBStorageTests {

    @Test("GRDB session CRUD")
    func testSessionCRUD() async throws {
        let storage = try GRDBStorage(inMemory: true)

        let session = Session(
            id: "grdb-s1",
            agentID: "agent-1",
            messages: [.user("Hello"), .assistant("Hi back")],
            state: ["mode": "chat"]
        )
        try await storage.upsertSession(session)

        let fetched = try await storage.getSession(id: "grdb-s1")
        #expect(fetched != nil)
        #expect(fetched!.messages.count == 2)
        #expect(fetched!.messages[0].text == "Hello")
        #expect(fetched!.state["mode"] == "chat")

        try await storage.deleteSession(id: "grdb-s1")
        let deleted = try await storage.getSession(id: "grdb-s1")
        #expect(deleted == nil)
    }

    @Test("GRDB memory operations")
    func testMemoryOperations() async throws {
        let storage = try GRDBStorage(inMemory: true)

        let memory = UserMemory(userID: "u1", content: "Prefers dark mode", category: "prefs")
        try await storage.upsertMemory(memory)

        let memories = try await storage.getMemories(userID: "u1")
        #expect(memories.count == 1)
        #expect(memories.first?.content == "Prefers dark mode")
    }

    @Test("GRDB FTS5 search on memories")
    func testFTS5Search() async throws {
        let storage = try GRDBStorage(inMemory: true)

        try await storage.upsertMemory(UserMemory(userID: "u1", content: "User loves Swift programming"))
        try await storage.upsertMemory(UserMemory(userID: "u1", content: "User enjoys hiking in the mountains"))
        try await storage.upsertMemory(UserMemory(userID: "u1", content: "User prefers dark chocolate"))

        let results = try await storage.searchMemories(query: "programming Swift", userID: "u1")
        #expect(results.count >= 1)
        #expect(results.first?.content.contains("Swift") == true)
    }

    @Test("GRDB learning records")
    func testLearningRecords() async throws {
        let storage = try GRDBStorage(inMemory: true)

        try await storage.upsertLearning(LearningRecord(
            userID: "u1", store: "profile", key: "name", value: "Alice"
        ))
        try await storage.upsertLearning(LearningRecord(
            userID: "u1", store: "profile", key: "language", value: "en"
        ))
        try await storage.upsertLearning(LearningRecord(
            userID: "u1", store: "entity", key: "Company", value: "Acme Inc"
        ))

        let profileRecords = try await storage.getLearnings(userID: "u1", store: "profile")
        #expect(profileRecords.count == 2)

        let entityRecords = try await storage.getLearnings(userID: "u1", store: "entity")
        #expect(entityRecords.count == 1)
    }

    @Test("GRDB knowledge tracking")
    func testKnowledgeTracking() async throws {
        let storage = try GRDBStorage(inMemory: true)

        try await storage.upsertKnowledgeEntry(KnowledgeEntry(
            contentHash: "hash1", source: "doc.pdf"
        ))

        let entries = try await storage.getKnowledgeEntries()
        #expect(entries.count == 1)
        #expect(entries.first?.source == "doc.pdf")
    }
}
