import Testing
import Foundation
@testable import SBBenderCore

@Suite("AgentTemplateEntry schema")
struct AgentTemplateEntryTests {

    @Test("decodes tagline from JSON")
    func testDecodesTagline() throws {
        let json = """
        [{
          "id": "test",
          "name": "Test",
          "emoji": "🧪",
          "gradientHex": ["#000", "#fff"],
          "description": "A test template",
          "tagline": "Just tell me what it says",
          "skillIDs": [],
          "instructions": "Be helpful.",
          "temperature": 0.5,
          "enableThinking": false,
          "knowledgeEnabled": false,
          "learningEnabled": false,
          "recommendedModelsByTier": {
            "small": "mlx-community/Qwen3-4B-4bit",
            "medium": "mlx-community/Qwen3-8B-4bit",
            "large": "mlx-community/Qwen3-8B-4bit"
          }
        }]
        """.data(using: .utf8)!

        let entries = try JSONDecoder().decode([AgentTemplateEntry].self, from: json)
        #expect(entries.count == 1)
        #expect(entries[0].tagline == "Just tell me what it says")
    }

    @Test("decodes recommendedModelsByTier from JSON")
    func testDecodesRecommendedModelsByTier() throws {
        let json = """
        [{
          "id": "test",
          "name": "Test",
          "emoji": "🧪",
          "gradientHex": ["#000", "#fff"],
          "description": "A test template",
          "tagline": "Test tagline",
          "skillIDs": [],
          "instructions": "Be helpful.",
          "temperature": 0.5,
          "enableThinking": false,
          "knowledgeEnabled": false,
          "learningEnabled": false,
          "recommendedModelsByTier": {
            "small": "mlx-community/Qwen3-4B-4bit",
            "medium": "mlx-community/Qwen3-8B-4bit",
            "large": "mlx-community/Qwen3-8B-4bit"
          }
        }]
        """.data(using: .utf8)!

        let entries = try JSONDecoder().decode([AgentTemplateEntry].self, from: json)
        #expect(entries[0].recommendedModelsByTier["small"] == "mlx-community/Qwen3-4B-4bit")
        #expect(entries[0].recommendedModelsByTier["medium"] == "mlx-community/Qwen3-8B-4bit")
    }

    @Test("tagline is optional — decodes without it")
    func testTaglineOptional() throws {
        let json = """
        [{
          "id": "test",
          "name": "Test",
          "emoji": "🧪",
          "gradientHex": ["#000", "#fff"],
          "description": "A test template",
          "skillIDs": [],
          "instructions": "Be helpful.",
          "temperature": 0.5,
          "enableThinking": false,
          "knowledgeEnabled": false,
          "learningEnabled": false
        }]
        """.data(using: .utf8)!

        let entries = try JSONDecoder().decode([AgentTemplateEntry].self, from: json)
        #expect(entries[0].tagline == nil)
        #expect(entries[0].recommendedModelsByTier.isEmpty)
    }
}
