import Foundation
import MCP
import os

/// Browser automation skill powered by the Playwright MCP server.
///
/// BrowserSkill launches a Playwright MCP server as a subprocess and exposes
/// all browser automation tools (navigate, click, fill, snapshot, screenshot, etc.)
/// as both SBBender Tools (for LLM-driven automation) and a NativeTool (for direct use).
///
/// Usage:
/// ```swift
/// let browser = BrowserSkill()
/// try await browser.connect()
///
/// // Use as a skill directly
/// let result = try await browser.execute(input: .text("https://example.com"))
///
/// // Or give to an agent for autonomous browsing
/// let agent = Agent(model: mlx, nativeTools: [browser], toolKits: [browser])
/// ```
///
/// The skill uses the `@anthropic-ai/mcp-server-playwright` MCP server by default.
/// Alternatively, use `@playwright/mcp` for the official Playwright MCP server.
public actor BrowserSkill: NativeTool, ToolKit {
    public nonisolated let id = "browser"
    public nonisolated let name = "browser"
    public nonisolated let description = "Browse the web: navigate, click, fill forms, take snapshots, and extract content"

    private let mcpManager: MCPManager
    private let serverCommand: String
    private let serverArgs: [String]
    private var connected: Bool = false
    private let _cachedTools = OSAllocatedUnfairLock(initialState: [Tool]())

    /// Create a BrowserSkill.
    ///
    /// - Parameters:
    ///   - command: The command to launch the MCP server. Default: "npx".
    ///   - serverPackage: The npm package for the MCP server. Default: "@anthropic-ai/mcp-server-playwright".
    ///   - extraArgs: Additional arguments to pass to the server.
    ///   - mcpManager: An existing MCPManager to share. If nil, creates a new one.
    public init(
        command: String = "npx",
        serverPackage: String = "@anthropic-ai/mcp-server-playwright",
        extraArgs: [String] = [],
        mcpManager: MCPManager? = nil
    ) {
        self.mcpManager = mcpManager ?? MCPManager()
        self.serverCommand = command
        self.serverArgs = [serverPackage] + extraArgs
    }

    /// Connect to the Playwright MCP server.
    ///
    /// Must be called before using the skill or its tools.
    public func connect() async throws {
        guard !connected else { return }

        try await mcpManager.connect(
            name: "browser",
            command: serverCommand,
            args: serverArgs
        )
        connected = true

        // Cache tools for thread-safe synchronous access
        let tools = await mcpManager.tools(for: "browser")
        _cachedTools.withLock { $0 = tools }
        Log.tool.info("BrowserSkill connected with \(tools.count) tools")
    }

    /// Disconnect from the browser server.
    public func disconnect() async {
        await mcpManager.disconnect(name: "browser")
        connected = false
        _cachedTools.withLock { $0 = [] }
    }

    // MARK: - NativeTool Protocol

    public nonisolated var isAvailable: Bool {
        get async { true }
    }

    /// Execute a browser action directly.
    ///
    /// The input text is treated as a URL to navigate to, and returns the page snapshot.
    public func execute(input: NativeToolInput) async throws -> NativeToolResult {
        guard connected else {
            throw SBBenderError.skillNotAvailable("BrowserSkill not connected. Call connect() first.")
        }

        guard let url = input.text, !url.isEmpty else {
            throw SBBenderError.skillExecutionFailed(skill: name, reason: "No URL provided")
        }

        let start = CFAbsoluteTimeGetCurrent()

        // Navigate to the URL
        let navigateArgs: [String: MCP.Value] = ["url": .string(url)]
        let _ = try await mcpManager.callTool(
            server: "browser",
            name: "browser_navigate",
            arguments: navigateArgs
        )

        // Take a snapshot for the content
        let snapshot = try await mcpManager.callTool(
            server: "browser",
            name: "browser_snapshot",
            arguments: [:]
        )

        return NativeToolResult(
            output: snapshot,
            structuredData: ["url": url],
            confidence: 1.0,
            latency: CFAbsoluteTimeGetCurrent() - start
        )
    }

    // MARK: - ToolKit Protocol

    /// Browser automation tools exposed for LLM use.
    ///
    /// Returns cached MCP tools. Empty until `connect()` is called.
    /// Thread-safe via `OSAllocatedUnfairLock`.
    public nonisolated var tools: [Tool] {
        _cachedTools.withLock { $0 }
    }

    /// Asynchronously get the current browser tools.
    public func fetchTools() -> [Tool] {
        _cachedTools.withLock { $0 }
    }

    /// The underlying MCPManager for advanced usage.
    public func getManager() -> MCPManager {
        mcpManager
    }

    // MARK: - NativeTool → Tool Bridge Override

    public nonisolated var toolParameters: JSONSchema {
        JSONSchema(
            properties: [
                "input": .string("URL to navigate to and capture a snapshot of"),
            ],
            required: ["input"]
        )
    }

    public nonisolated func asTool() -> Tool {
        let skill = self
        return Tool(
            name: "browser_navigate_and_snapshot",
            description: "Navigate to a URL and return the page content as an accessibility snapshot",
            parameters: toolParameters
        ) { arguments, _ in
            struct Args: Decodable { let input: String }
            let args = try JSONDecoder().decode(Args.self, from: Data(arguments.utf8))
            let result = try await skill.execute(input: .text(args.input))
            return result.output
        }
    }
}

