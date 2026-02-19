import Foundation
import MCP
import SBBenderCore
import os

#if canImport(System)
    import System
#endif

/// Manages connections to MCP (Model Context Protocol) servers.
///
/// MCPManager allows agents to connect to external tool servers and use their
/// tools as native SBBender tools. Supports both stdio (subprocess) and
/// in-memory transports.
public actor MCPManager {
    /// A connected MCP server with its client and metadata.
    struct ServerConnection: Sendable {
        let client: Client
        let transport: any Transport
        let name: String
        var process: Foundation.Process?
    }

    private var connections: [String: ServerConnection] = [:]
    private var toolCache: [String: [SBTool]] = [:]

    public init() {}

    // MARK: - Connection Management

    /// Connect to an MCP server via stdio transport (launches a subprocess).
    ///
    /// Example:
    /// ```swift
    /// try await manager.connect(
    ///     name: "playwright",
    ///     command: "npx",
    ///     args: ["@anthropic-ai/mcp-server-playwright"]
    /// )
    /// ```
    public func connect(
        name: String,
        command: String,
        args: [String] = [],
        environment: [String: String]? = nil
    ) async throws {
        let client = Client(name: "SBBender", version: "1.0.0")

        let process = Foundation.Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + args
        if let env = environment {
            process.environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new }
        }

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        try process.run()

        #if canImport(System)
        let inputFD = FileDescriptor(rawValue: stdoutPipe.fileHandleForReading.fileDescriptor)
        let outputFD = FileDescriptor(rawValue: stdinPipe.fileHandleForWriting.fileDescriptor)
        let transport = StdioTransport(input: inputFD, output: outputFD)
        #else
        let transport = StdioTransport()
        #endif

        do {
            try await client.connect(transport: transport)
        } catch {
            process.terminate()
            throw error
        }

        let connection = ServerConnection(
            client: client,
            transport: transport,
            name: name,
            process: process
        )
        connections[name] = connection

        // Pre-fetch and cache tools
        try await refreshTools(for: name)

        Log.tool.info("Connected to MCP server: \(name)")
    }

    /// Connect to an MCP server via an existing transport (e.g., InMemoryTransport for testing).
    public func connect(name: String, transport: any Transport) async throws {
        let client = Client(name: "SBBender", version: "1.0.0")
        try await client.connect(transport: transport)

        let connection = ServerConnection(
            client: client,
            transport: transport,
            name: name
        )
        connections[name] = connection

        try await refreshTools(for: name)

        Log.tool.info("Connected to MCP server: \(name)")
    }

    /// Disconnect from a named MCP server.
    public func disconnect(name: String) async {
        guard let connection = connections[name] else { return }
        await connection.client.disconnect()
        if let process = connection.process {
            process.terminate()
            process.waitUntilExit()
        }
        connections.removeValue(forKey: name)
        toolCache.removeValue(forKey: name)
        Log.tool.info("Disconnected from MCP server: \(name)")
    }

    /// Disconnect from all servers.
    public func disconnectAll() async {
        for (_, connection) in connections {
            await connection.client.disconnect()
            if let process = connection.process {
                process.terminate()
                process.waitUntilExit()
            }
        }
        connections.removeAll()
        toolCache.removeAll()
    }

    // MARK: - Tool Discovery

    /// Refresh the tool cache for a specific server.
    public func refreshTools(for serverName: String) async throws {
        guard let connection = connections[serverName] else { return }

        let result = try await connection.client.listTools()
        let sbbenderTools = result.tools.map { mcpTool -> SBTool in
            convertMCPTool(mcpTool, serverName: serverName)
        }
        toolCache[serverName] = sbbenderTools
    }

    /// Get all tools from all connected servers as SBBender tools.
    public func allTools() -> [SBTool] {
        toolCache.values.flatMap { $0 }
    }

    /// Get tools from a specific server.
    public func tools(for serverName: String) -> [SBTool] {
        toolCache[serverName] ?? []
    }

    /// Call a tool on a specific MCP server.
    public func callTool(
        server: String,
        name: String,
        arguments: [String: Value]
    ) async throws -> String {
        guard let connection = connections[server] else {
            throw SBBenderError.toolNotFound("MCP server '\(server)' not connected")
        }

        let result = try await connection.client.callTool(name: name, arguments: arguments)

        if result.isError == true {
            let errorText = result.content.compactMap { content -> String? in
                if case .text(let text) = content { return text }
                return nil
            }.joined(separator: "\n")
            throw SBBenderError.toolExecutionFailed(
                tool: name,
                reason: errorText.isEmpty ? "MCP tool returned error" : errorText
            )
        }

        let textParts = result.content.compactMap { content -> String? in
            switch content {
            case .text(let text):
                return text
            case .image(_, let mimeType, _):
                return "[image: \(mimeType)]"
            case .resource(let uri, _, let text):
                return text ?? "[resource: \(uri)]"
            case .audio(_, let mimeType):
                return "[audio: \(mimeType)]"
            @unknown default:
                return nil
            }
        }

        return textParts.joined(separator: "\n")
    }

    // MARK: - MCP Tool → SBBender Tool Conversion

    /// Convert an MCP Tool to a SBBender Tool.
    private func convertMCPTool(_ mcpTool: MCP.Tool, serverName: String) -> SBTool {
        let toolName = mcpTool.name
        let toolDescription = mcpTool.description ?? "MCP tool: \(toolName)"
        let schema = convertInputSchema(mcpTool.inputSchema)
        let server = serverName
        // Capture self (actor) — the tool closure calls back into the actor
        let mgr = self

        return SBTool(
            name: toolName,
            description: toolDescription,
            parameters: schema
        ) { arguments, _ in
            let mcpArgs = Self.jsonStringToMCPValues(arguments)
            return try await mgr.callTool(server: server, name: toolName, arguments: mcpArgs)
        }
    }

    /// Convert MCP inputSchema (Value) to SBBender JSONSchema.
    private func convertInputSchema(_ schema: Value) -> JSONSchema {
        guard case .object(let dict) = schema else {
            return JSONSchema()
        }

        var properties: [String: PropertySchema] = [:]
        if case .object(let props) = dict["properties"] {
            for (key, value) in props {
                properties[key] = convertValueToPropertySchema(value)
            }
        }

        var required: [String] = []
        if case .array(let reqArray) = dict["required"] {
            required = reqArray.compactMap { $0.stringValue }
        }

        return JSONSchema(type: "object", properties: properties, required: required)
    }

    /// Convert a JSON Value to PropertySchema.
    private func convertValueToPropertySchema(_ value: Value) -> PropertySchema {
        guard case .object(let dict) = value else {
            return PropertySchema(type: "string")
        }
        let type = dict["type"]?.stringValue ?? "string"
        let description = dict["description"]?.stringValue
        let enumValues: [String]?
        if case .array(let arr) = dict["enum"] {
            enumValues = arr.compactMap { $0.stringValue }
        } else {
            enumValues = nil
        }
        return PropertySchema(type: type, description: description, enumValues: enumValues)
    }

    /// Parse a JSON string into MCP Value dictionary.
    static func jsonStringToMCPValues(_ jsonString: String) -> [String: Value] {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json.mapValues { anyToValue($0) }
    }

    /// Convert Any to MCP Value.
    private static func anyToValue(_ any: Any) -> Value {
        switch any {
        case let string as String:
            return .string(string)
        case let bool as Bool:
            return .bool(bool)
        case let int as Int:
            return .int(int)
        case let double as Double:
            return .double(double)
        case let array as [Any]:
            return .array(array.map { anyToValue($0) })
        case let dict as [String: Any]:
            return .object(dict.mapValues { anyToValue($0) })
        default:
            return .string(String(describing: any))
        }
    }

    /// Number of connected servers.
    public var connectionCount: Int {
        connections.count
    }

    /// Names of all connected servers.
    public var connectedServers: [String] {
        Array(connections.keys)
    }
}
