import Testing
import Foundation
@testable import SBBenderCore

@Suite("ContextManager Tests")
struct ContextManagerTests {

    // MARK: - Tool Output Store

    @Test("Store and retrieve tool outputs")
    func storeAndRetrieve() {
        let store = ToolOutputStore()
        store.store(ToolOutputEntry(
            callID: "call-1",
            toolName: "search",
            fullOutput: "Result: found 42 items with very long content...",
            timestamp: Date()
        ))

        let entry = store.get(callID: "call-1")
        #expect(entry != nil)
        #expect(entry?.toolName == "search")
        #expect(entry?.fullOutput.contains("42 items") == true)
        #expect(store.count == 1)
    }

    @Test("Store evicts oldest entries when over limit")
    func eviction() {
        let store = ToolOutputStore(maxEntries: 3)

        for i in 0..<5 {
            store.store(ToolOutputEntry(
                callID: "call-\(i)",
                toolName: "tool",
                fullOutput: "output \(i)",
                timestamp: Date()
            ))
        }

        #expect(store.count == 3)
        #expect(store.get(callID: "call-0") == nil) // evicted
        #expect(store.get(callID: "call-1") == nil) // evicted
        #expect(store.get(callID: "call-2") != nil)
        #expect(store.get(callID: "call-4") != nil)
    }

    @Test("All entries in chronological order")
    func chronologicalOrder() {
        let store = ToolOutputStore()
        store.store(ToolOutputEntry(callID: "a", toolName: "first", fullOutput: "1", timestamp: Date()))
        store.store(ToolOutputEntry(callID: "b", toolName: "second", fullOutput: "2", timestamp: Date()))
        store.store(ToolOutputEntry(callID: "c", toolName: "third", fullOutput: "3", timestamp: Date()))

        let entries = store.allEntries
        #expect(entries.count == 3)
        #expect(entries[0].callID == "a")
        #expect(entries[2].callID == "c")
    }

    @Test("Recent entries")
    func recentEntries() {
        let store = ToolOutputStore()
        for i in 0..<10 {
            store.store(ToolOutputEntry(callID: "\(i)", toolName: "t", fullOutput: "\(i)", timestamp: Date()))
        }

        let recent = store.recent(3)
        #expect(recent.count == 3)
        #expect(recent[0].callID == "7")
        #expect(recent[2].callID == "9")
    }

    @Test("Clear store")
    func clearStore() {
        let store = ToolOutputStore()
        store.store(ToolOutputEntry(callID: "x", toolName: "t", fullOutput: "data", timestamp: Date()))
        #expect(store.count == 1)

        store.clear()
        #expect(store.count == 0)
        #expect(store.allEntries.isEmpty)
    }

    // MARK: - Process Tool Output

    @Test("Short output passes through without truncation")
    func shortOutput() {
        let store = ToolOutputStore()
        let result = ContextManager.processToolOutput(
            "Short output",
            maxLength: 1000,
            toolName: "test",
            callID: "c1",
            store: store
        )
        #expect(result == "Short output")
        #expect(store.count == 1)
        #expect(store.get(callID: "c1")?.fullOutput == "Short output")
    }

    @Test("Long output is summarized but full version is stored")
    func longOutput() {
        let store = ToolOutputStore()
        let longText = String(repeating: "x", count: 5000)

        let result = ContextManager.processToolOutput(
            longText,
            maxLength: 100,
            toolName: "search",
            callID: "c2",
            store: store
        )

        // Model sees truncated version
        #expect(result.count < longText.count)
        #expect(result.contains("truncated"))
        #expect(result.contains("5000 chars"))

        // Store has full version
        let stored = store.get(callID: "c2")
        #expect(stored?.fullOutput.count == 5000)
        #expect(stored?.toolName == "search")
    }

    // MARK: - History Trimming

    @Test("Trim messages keeps system messages")
    func trimKeepsSystem() {
        let messages: [Message] = [
            .system("System prompt"),
            .user("msg 1"),
            .assistant("reply 1"),
            .user("msg 2"),
            .assistant("reply 2"),
            .user("msg 3"),
            .assistant("reply 3"),
        ]

        let trimmed = ContextManager.trimHistory(messages, maxMessages: 2, maxToolResults: nil)
        #expect(trimmed.count == 3) // system + 2 most recent
        #expect(trimmed[0].role == .system)
        #expect(trimmed[1].text == "msg 3")
    }

    @Test("Trim tool results keeps most recent")
    func trimToolResults() {
        let messages: [Message] = [
            .user("q1"),
            .tool(id: "t1", result: "r1", name: "tool1"),
            .tool(id: "t2", result: "r2", name: "tool2"),
            .tool(id: "t3", result: "r3", name: "tool3"),
            .user("q2"),
        ]

        let trimmed = ContextManager.trimHistory(messages, maxMessages: nil, maxToolResults: 2)
        let toolMessages = trimmed.filter { $0.role == .tool }
        #expect(toolMessages.count == 2)
    }

    @Test("No trimming when within limits")
    func noTrimming() {
        let messages: [Message] = [
            .user("hello"),
            .assistant("hi"),
        ]

        let trimmed = ContextManager.trimHistory(messages, maxMessages: 10, maxToolResults: 10)
        #expect(trimmed.count == 2)
    }

    @Test("Nil limits means no trimming")
    func nilLimits() {
        let messages: [Message] = (0..<100).map { i in
            Message.user("msg \(i)")
        }

        let trimmed = ContextManager.trimHistory(messages, maxMessages: nil, maxToolResults: nil)
        #expect(trimmed.count == 100)
    }

    // MARK: - Token Estimation

    @Test("Estimate tokens from text messages")
    func estimateTokens() {
        let messages: [Message] = [
            .user("Hello world"), // 11 chars -> ~2-3 tokens
            .assistant("How can I help you today?"), // 25 chars -> ~6 tokens
        ]

        let estimate = ContextManager.estimateTokens(messages)
        #expect(estimate > 0)
        #expect(estimate == 9) // (11 + 25) / 4
    }
}
