import Testing
import Foundation
@testable import SBBender
import MCP

@Suite("MCP Integration Tests")
struct MCPTests {

    @Test("MCPManager jsonStringToMCPValues parses correctly")
    func testJsonStringToMCPValues() {
        let json = #"{"name": "test", "count": 42, "active": true}"#
        let values = MCPManager.jsonStringToMCPValues(json)

        #expect(values["name"]?.stringValue == "test")
        #expect(values["count"]?.intValue == 42)
        #expect(values["active"]?.boolValue == true)
    }

    @Test("MCPManager jsonStringToMCPValues handles empty input")
    func testJsonStringToMCPValuesEmpty() {
        let values = MCPManager.jsonStringToMCPValues("")
        #expect(values.isEmpty)

        let values2 = MCPManager.jsonStringToMCPValues("{}")
        #expect(values2.isEmpty)
    }

    @Test("MCPManager jsonStringToMCPValues handles nested objects")
    func testJsonStringToMCPValuesNested() {
        let json = #"{"query": "test", "options": {"limit": 10}}"#
        let values = MCPManager.jsonStringToMCPValues(json)

        #expect(values["query"]?.stringValue == "test")
        if case .object(let opts) = values["options"] {
            #expect(opts["limit"]?.intValue == 10)
        } else {
            Issue.record("Expected options to be an object")
        }
    }

    @Test("MCPManager starts with no connections")
    func testInitialState() async {
        let manager = MCPManager()
        let count = await manager.connectionCount
        #expect(count == 0)
        let servers = await manager.connectedServers
        #expect(servers.isEmpty)
    }

    @Test("MCPManager allTools returns empty when no connections")
    func testAllToolsEmpty() async {
        let manager = MCPManager()
        let tools = await manager.allTools()
        #expect(tools.isEmpty)
    }

    @Test("MCPManager connect with InMemoryTransport")
    func testConnectWithInMemoryTransport() async throws {
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()

        let server = Server(name: "TestServer", version: "1.0.0", capabilities: .init(tools: .init()))
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [
                MCP.Tool(
                    name: "echo",
                    description: "Echo input",
                    inputSchema: .object(["type": "object"])
                ),
            ])
        }
        await server.withMethodHandler(CallTool.self) { params in
            let input = params.arguments?["text"]?.stringValue ?? "no input"
            return CallTool.Result(content: [.text(input)])
        }

        Task {
            try await server.start(transport: serverTransport)
        }
        try await Task.sleep(for: .milliseconds(100))

        let manager = MCPManager()
        try await manager.connect(name: "test", transport: clientTransport)

        let count = await manager.connectionCount
        #expect(count == 1)

        let tools = await manager.allTools()
        #expect(tools.count == 1)
        #expect(tools[0].name == "echo")

        let result = try await manager.callTool(
            server: "test",
            name: "echo",
            arguments: ["text": .string("hello")]
        )
        #expect(result == "hello")

        await manager.disconnect(name: "test")
        let countAfter = await manager.connectionCount
        #expect(countAfter == 0)

        await server.stop()
    }

    @Test("MCP tools are usable as SBBender Tools")
    func testMCPToolAsSBBenderTool() async throws {
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()

        let server = Server(name: "CalcServer", version: "1.0.0", capabilities: .init(tools: .init()))
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [
                MCP.Tool(
                    name: "add",
                    description: "Add two numbers",
                    inputSchema: .object([
                        "type": "object",
                        "properties": .object([
                            "a": .object(["type": "number", "description": "First number"]),
                            "b": .object(["type": "number", "description": "Second number"]),
                        ]),
                        "required": .array([.string("a"), .string("b")]),
                    ])
                ),
            ])
        }
        await server.withMethodHandler(CallTool.self) { params in
            let a = params.arguments?["a"]?.doubleValue ?? params.arguments?["a"]?.intValue.map(Double.init) ?? 0
            let b = params.arguments?["b"]?.doubleValue ?? params.arguments?["b"]?.intValue.map(Double.init) ?? 0
            return CallTool.Result(content: [.text(String(a + b))])
        }

        Task {
            try await server.start(transport: serverTransport)
        }
        try await Task.sleep(for: .milliseconds(100))

        let manager = MCPManager()
        try await manager.connect(name: "calc", transport: clientTransport)

        let tools = await manager.allTools()
        #expect(tools.count == 1)

        let addTool = tools[0]
        #expect(addTool.name == "add")
        #expect(addTool.description == "Add two numbers")

        let result = try await addTool.execute(
            arguments: #"{"a": 10, "b": 20}"#,
            context: ToolContext()
        )
        #expect(result == "30.0")

        await manager.disconnect(name: "calc")
        await server.stop()
    }

    @Test("Agent with MCP tools runs autonomously")
    func testAgentWithMCPTools() async throws {
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()

        let server = Server(name: "ToolServer", version: "1.0.0", capabilities: .init(tools: .init()))
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [
                MCP.Tool(
                    name: "greet",
                    description: "Greet someone",
                    inputSchema: .object([
                        "type": "object",
                        "properties": .object([
                            "name": .object(["type": "string"]),
                        ]),
                        "required": .array([.string("name")]),
                    ])
                ),
            ])
        }
        await server.withMethodHandler(CallTool.self) { params in
            let name = params.arguments?["name"]?.stringValue ?? "World"
            return CallTool.Result(content: [.text("Hello, \(name)!")])
        }

        Task {
            try await server.start(transport: serverTransport)
        }
        try await Task.sleep(for: .milliseconds(100))

        let manager = MCPManager()
        try await manager.connect(name: "tools", transport: clientTransport)

        let toolCall = ToolCall(id: "tc-1", name: "greet", arguments: #"{"name": "Alice"}"#)
        let provider = MockProvider(
            responses: ["I greeted Alice for you!"],
            toolCallResponses: [([toolCall], "")]
        )

        let agent = Agent(
            configuration: AgentConfiguration(name: "MCPAgent"),
            model: provider
        )
        // Register MCP tools on the agent
        let mcpTools = await manager.allTools()
        for tool in mcpTools {
            await agent.addTool(tool)
        }

        let result = try await agent.run("Greet Alice")
        #expect(result.status == .completed)
        #expect(result.toolExecutions.count == 1)
        #expect(result.toolExecutions[0].toolName == "greet")
        #expect(result.toolExecutions[0].result == "Hello, Alice!")

        await manager.disconnect(name: "tools")
        await server.stop()
    }
}
