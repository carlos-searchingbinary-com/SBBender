import Foundation

/// A ToolKit that wraps an MCP server's tools.
///
/// MCPToolKit dynamically provides tools from a connected MCP server.
/// Tools are pre-fetched during initialization, so the synchronous
/// `tools` property always returns the current set.
///
/// Usage:
/// ```swift
/// let manager = MCPManager()
/// try await manager.connect(name: "browser", command: "npx", args: ["@playwright/mcp"])
/// let toolkit = await MCPToolKit(manager: manager, serverName: "browser")
/// let agent = Agent(model: mlx, toolKits: [toolkit])
/// ```
public struct MCPToolKit: ToolKit, @unchecked Sendable {
    public let name: String
    public let description: String
    private let _tools: [Tool]

    /// Create a toolkit backed by an MCP server.
    ///
    /// The MCPManager must already be connected to the named server.
    /// Tools are fetched at initialization time.
    public init(manager: MCPManager, serverName: String, description: String? = nil) async {
        self.name = "\(serverName)MCP"
        self.description = description ?? "Tools from MCP server '\(serverName)'"
        self._tools = await manager.tools(for: serverName)
    }

    public var tools: [Tool] {
        _tools
    }
}
