import Testing
import Foundation
@testable import SBBender

@Suite("TextKnowledge Tests")
struct TextKnowledgeTests {

    @Test("Insert and search documents")
    func testInsertAndSearch() async throws {
        let knowledge = TextKnowledge()

        try await knowledge.insert(content: "Swift is a programming language by Apple", metadata: ["topic": "programming"])
        try await knowledge.insert(content: "Python is a programming language", metadata: ["topic": "programming"])
        try await knowledge.insert(content: "Hiking is a great outdoor activity", metadata: ["topic": "sports"])

        let results = try await knowledge.search(query: "programming language", limit: 5)
        #expect(results.count == 2) // Both programming docs match
        #expect(results.allSatisfy { $0.content.contains("programming") })
    }

    @Test("Search returns empty for no matches")
    func testNoMatches() async throws {
        let knowledge = TextKnowledge()
        try await knowledge.insert(content: "Swift programming", metadata: [:])

        let results = try await knowledge.search(query: "quantum physics", limit: 5)
        #expect(results.isEmpty)
    }

    @Test("Delete documents")
    func testDelete() async throws {
        let knowledge = TextKnowledge()
        try await knowledge.insert(content: "To be deleted", metadata: [:])

        let before = try await knowledge.search(query: "deleted", limit: 5)
        #expect(before.count == 1)

        let id = before.first!.id
        try await knowledge.delete(id: id)

        let after = try await knowledge.search(query: "deleted", limit: 5)
        #expect(after.isEmpty)
    }

    @Test("Respects search limit")
    func testSearchLimit() async throws {
        let knowledge = TextKnowledge()
        for i in 0..<10 {
            try await knowledge.insert(content: "Document \(i) about Swift", metadata: [:])
        }

        let results = try await knowledge.search(query: "Swift", limit: 3)
        #expect(results.count == 3)
    }
}

@Suite("PageTree Tests")
struct PageTreeTests {

    func makeTestTree() -> PageTree {
        PageTree(
            title: "Test Meeting",
            root: PageNode(
                title: "Root",
                content: "Meeting transcript",
                children: [
                    PageNode(
                        title: "Introduction",
                        summary: "Opening remarks",
                        content: "Welcome everyone to the quarterly review meeting",
                        startIndex: 0, endIndex: 50,
                        timeRange: 0...120,
                        speakers: ["Alice"],
                        children: []
                    ),
                    PageNode(
                        title: "Budget Discussion",
                        summary: "Financial overview",
                        content: "Our budget for Q3 shows a 15% increase in revenue",
                        startIndex: 50, endIndex: 100,
                        timeRange: 120...300,
                        speakers: ["Bob", "Alice"],
                        children: [
                            PageNode(
                                title: "Revenue Details",
                                summary: "Revenue breakdown",
                                content: "Cloud services revenue grew by 25% while hardware declined",
                                startIndex: 70, endIndex: 100,
                                timeRange: 200...300,
                                speakers: ["Bob"]
                            ),
                        ]
                    ),
                    PageNode(
                        title: "Action Items",
                        summary: "Next steps",
                        content: "Alice will prepare the Q4 forecast by Friday",
                        startIndex: 100, endIndex: 150,
                        timeRange: 300...420,
                        speakers: ["Alice", "Charlie"]
                    ),
                ]
            )
        )
    }

    @Test("Tree node count")
    func testNodeCount() {
        let tree = makeTestTree()
        #expect(tree.nodeCount == 5) // root + 3 children + 1 grandchild
    }

    @Test("Leaf nodes")
    func testLeafNodes() {
        let tree = makeTestTree()
        #expect(tree.leafNodes.count == 3) // Introduction, Revenue Details, Action Items
    }

    @Test("All speakers")
    func testAllSpeakers() {
        let tree = makeTestTree()
        let speakers = tree.allSpeakers
        #expect(speakers.contains("Alice"))
        #expect(speakers.contains("Bob"))
        #expect(speakers.contains("Charlie"))
    }

    @Test("Search by keyword")
    func testSearch() {
        let tree = makeTestTree()
        let results = tree.search(query: "revenue budget", limit: 3)
        #expect(!results.isEmpty)
        #expect(results.first?.title == "Budget Discussion" || results.first?.title == "Revenue Details")
    }

    @Test("Find node by ID")
    func testFindByID() {
        let tree = makeTestTree()
        let introNode = tree.root.children[0]
        let found = tree.root.find(id: introNode.id)
        #expect(found?.title == "Introduction")
    }

    @Test("Path to node")
    func testPathTo() {
        let tree = makeTestTree()
        let revenueNode = tree.root.children[1].children[0]
        let path = tree.root.pathTo(id: revenueNode.id)
        #expect(path?.count == 3) // root -> budget -> revenue
        #expect(path?.last?.title == "Revenue Details")
    }

    @Test("PageNode Codable roundtrip")
    func testCodable() throws {
        let node = PageNode(
            title: "Test",
            summary: "A test node",
            content: "Content here",
            startIndex: 0, endIndex: 10,
            timeRange: 0...5.5,
            speakers: ["Speaker1"],
            confidence: 0.95
        )

        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(PageNode.self, from: data)

        #expect(decoded.title == "Test")
        #expect(decoded.timeRange == 0...5.5)
        #expect(decoded.speakers == ["Speaker1"])
        #expect(decoded.confidence == 0.95)
    }
}

@Suite("PageTreeKnowledge Tests")
struct PageTreeKnowledgeTests {

    @Test("PageTree as KnowledgeSource")
    func testAsKnowledgeSource() async throws {
        let tree = PageTree(
            title: "Meeting",
            root: PageNode(
                title: "Root",
                content: "Root content",
                children: [
                    PageNode(title: "Section 1", content: "Discussion about Swift programming"),
                    PageNode(title: "Section 2", content: "Discussion about Python"),
                ]
            )
        )

        let knowledge = PageTreeKnowledge(tree: tree)
        let results = try await knowledge.search(query: "Swift", limit: 5)
        #expect(results.count >= 1)
        #expect(results.first?.content.contains("Swift") == true)
    }
}
