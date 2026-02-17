import Testing
import Foundation
@testable import SBBender

@Suite("Tool Tests")
struct ToolTests {

    @Test("Create and execute a tool")
    func testToolExecution() async throws {
        let tool = Tool(
            name: "add",
            description: "Add two numbers",
            parameters: JSONSchema(
                properties: [
                    "a": .integer("First number"),
                    "b": .integer("Second number"),
                ],
                required: ["a", "b"]
            )
        ) { arguments, _ in
            struct Args: Decodable { let a: Int; let b: Int }
            let args = try JSONDecoder().decode(Args.self, from: Data(arguments.utf8))
            return String(args.a + args.b)
        }

        let result = try await tool.execute(
            arguments: #"{"a": 3, "b": 4}"#,
            context: ToolContext()
        )
        #expect(result == "7")
    }

    @Test("Tool to definition conversion")
    func testToolDefinition() {
        let tool = Tool(
            name: "search",
            description: "Search the web",
            parameters: JSONSchema(
                properties: ["query": .string("Search query")],
                required: ["query"]
            )
        ) { _, _ in "results" }

        let def = tool.toDefinition()
        #expect(def.name == "search")
        #expect(def.description == "Search the web")

        let params = def.parameters
        #expect(params["type"] as? String == "object")
        #expect((params["required"] as? [String])?.contains("query") == true)
    }

    @Test("Tool with stopAfterCall")
    func testStopAfterCall() {
        let tool = Tool(
            name: "done",
            description: "Mark as done",
            stopAfterCall: true
        ) { _, _ in "completed" }

        #expect(tool.stopAfterCall == true)
    }
}

@Suite("ToolRegistry Tests")
struct ToolRegistryTests {

    @Test("Register and retrieve tools")
    func testRegistry() {
        var registry = ToolRegistry()
        let tool = Tool(name: "test", description: "A test tool") { _, _ in "ok" }

        registry.register(tool)
        #expect(registry.get("test")?.name == "test")
        #expect(registry.get("nonexistent") == nil)
    }

    @Test("Register from ToolKit")
    func testToolKit() {
        struct MyKit: ToolKit {
            let name = "mykit"
            let description = "A test toolkit"
            var tools: [Tool] {
                [
                    Tool(name: "tool_a", description: "Tool A") { _, _ in "a" },
                    Tool(name: "tool_b", description: "Tool B") { _, _ in "b" },
                ]
            }
        }

        var registry = ToolRegistry()
        registry.register(contentsOf: MyKit())

        #expect(registry.allTools.count == 2)
        #expect(registry.get("tool_a") != nil)
        #expect(registry.get("tool_b") != nil)
    }

    @Test("Definitions for model API")
    func testDefinitions() {
        let registry = ToolRegistry(tools: [
            Tool(name: "a", description: "A") { _, _ in "a" },
            Tool(name: "b", description: "B") { _, _ in "b" },
        ])

        #expect(registry.definitions.count == 2)
    }
}

@Suite("JSONSchema Tests")
struct JSONSchemaTests {

    @Test("Schema toDictionary")
    func testToDictionary() {
        let schema = JSONSchema(
            properties: [
                "name": .string("User name"),
                "age": .integer("User age"),
                "tags": .array(items: .string(), description: "Tags"),
            ],
            required: ["name"]
        )

        let dict = schema.toDictionary()
        #expect(dict["type"] as? String == "object")
        #expect((dict["required"] as? [String])?.contains("name") == true)

        let props = dict["properties"] as? [String: Any]
        #expect(props != nil)
        #expect((props?["name"] as? [String: Any])?["type"] as? String == "string")
    }

    @Test("PropertySchema Codable roundtrip")
    func testPropertySchemaCodable() throws {
        let schema = PropertySchema.array(items: .string("item"), description: "list")
        let data = try JSONEncoder().encode(schema)
        let decoded = try JSONDecoder().decode(PropertySchema.self, from: data)

        #expect(decoded.type == "array")
        #expect(decoded.items?.type == "string")
    }
}
