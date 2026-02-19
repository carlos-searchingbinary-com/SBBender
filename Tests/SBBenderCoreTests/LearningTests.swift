import Testing
import Foundation
@testable import SBBenderCore

@Suite("LearningEngine Tests")
struct LearningEngineTests {

    @Test("Recall returns empty when no data")
    func testEmptyRecall() async throws {
        let storage = InMemoryStorage()
        let engine = LearningEngine(storage: storage, userID: "user-1")

        let context = try await engine.recall(sessionID: "s1")
        #expect(context.isEmpty)
    }

    @Test("Set and recall user profile attributes")
    func testUserProfile() async throws {
        let storage = InMemoryStorage()
        let engine = LearningEngine(storage: storage, userID: "user-1")

        try await engine.setProfileAttribute(key: "name", value: "Alice")
        try await engine.setProfileAttribute(key: "language", value: "English")

        let context = try await engine.recall(sessionID: "s1")
        #expect(context.contains("name"))
        #expect(context.contains("Alice"))
        #expect(context.contains("language"))
    }

    @Test("Add and recall memories")
    func testMemories() async throws {
        let storage = InMemoryStorage()
        let engine = LearningEngine(storage: storage, userID: "user-1")

        try await engine.addMemory("User prefers dark mode", category: "preferences")
        try await engine.addMemory("User works at Acme Inc", category: "work")

        let context = try await engine.recall(sessionID: "s1")
        #expect(context.contains("dark mode"))
        #expect(context.contains("Acme"))
    }

    @Test("Entity memory storage")
    func testEntityMemory() async throws {
        let storage = InMemoryStorage()
        let engine = LearningEngine(
            storage: storage,
            userID: "user-1",
            entityMemory: .enabled
        )

        try await engine.setEntityMemory(entity: "Acme Inc", fact: "A software company in San Francisco")

        let context = try await engine.recall(sessionID: "s1")
        #expect(context.contains("Acme Inc"))
        #expect(context.contains("San Francisco"))
    }

    @Test("Process extracts explicit memory requests")
    func testProcessExplicitMemory() async throws {
        let storage = InMemoryStorage()
        let engine = LearningEngine(storage: storage, userID: "user-1")

        let messages = [
            Message.user("Remember that I prefer Python over JavaScript"),
            Message.assistant("Got it! I'll remember that you prefer Python."),
        ]

        let result = RunResult(sessionID: "s1")
        try await engine.process(messages: messages, runResult: result)

        let memories = try await storage.getMemories(userID: "user-1")
        #expect(memories.count >= 1)
    }

    @Test("Disabled stores don't produce context")
    func testDisabledStores() async throws {
        let storage = InMemoryStorage()
        let engine = LearningEngine(
            storage: storage,
            userID: "user-1",
            userProfile: .disabled,
            userMemory: .disabled,
            sessionContext: .disabled,
            entityMemory: .disabled
        )

        // Even if we add data directly to storage, disabled stores won't recall
        try await storage.upsertLearning(LearningRecord(
            userID: "user-1", store: "user_profile", key: "name", value: "Alice"
        ))

        let context = try await engine.recall(sessionID: "s1")
        #expect(context.isEmpty)
    }

    @Test("Session context updates")
    func testSessionContext() async throws {
        let storage = InMemoryStorage()
        let engine = LearningEngine(storage: storage, userID: "user-1")

        let messages = [
            Message.user("Let's discuss the quarterly revenue numbers for Q3"),
        ]

        let result = RunResult(sessionID: "session-abc")
        try await engine.process(messages: messages, runResult: result)

        let records = try await storage.getLearnings(userID: "user-1", store: "session_context")
        #expect(!records.isEmpty)
        #expect(records.first?.value.contains("quarterly") == true)
    }
}
