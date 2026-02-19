import Foundation
import MCP
import SBBenderCore

/// MCP integration for Agent — adds `connectMCP` methods and automatic tool registration.
extension Agent {

    /// Connect to an MCP server and register its tools.
    public func connectMCP(
        name: String,
        command: String,
        args: [String] = [],
        environment: [String: String]? = nil
    ) async throws {
        let manager: MCPManager
        if let existing = _mcpManager as? MCPManager {
            manager = existing
        } else {
            let m = MCPManager()
            _mcpManager = m
            manager = m
        }

        try await manager.connect(name: name, command: command, args: args, environment: environment)

        let mcpTools = await manager.tools(for: name)
        for tool in mcpTools {
            toolRegistry.register(tool)
        }

        // Set up the external tool provider so run() also picks up MCP tools
        let capturedManager = manager
        _externalToolProvider = {
            await capturedManager.allTools()
        }
    }

    /// Connect to an MCP server via an existing transport (for testing or custom transports).
    public func connectMCP(name: String, transport: any MCP.Transport) async throws {
        let manager: MCPManager
        if let existing = _mcpManager as? MCPManager {
            manager = existing
        } else {
            let m = MCPManager()
            _mcpManager = m
            manager = m
        }

        try await manager.connect(name: name, transport: transport)

        let mcpTools = await manager.tools(for: name)
        for tool in mcpTools {
            toolRegistry.register(tool)
        }

        // Set up the external tool provider so run() also picks up MCP tools
        let capturedManager = manager
        _externalToolProvider = {
            await capturedManager.allTools()
        }
    }
}
