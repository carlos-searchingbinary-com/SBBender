import Foundation
import MCP

/// The core agent actor — the primary building block of SBBender.
///
/// An Agent wraps a `ModelProvider` with tools, native tools, knowledge, and memory
/// to create an autonomous AI entity that can reason, plan, and act.
///
/// Thread safety is guaranteed by Swift's `actor` isolation.
public actor Agent {
    public let id: String
    public let configuration: AgentConfiguration
    public let model: any ModelProvider

    private var toolRegistry: ToolRegistry
    private var nativeTools: [any NativeTool]
    private var skills: [Skill]
    private var storage: (any StorageBackend)?
    private var knowledge: (any KnowledgeSource)?
    private var learning: LearningEngine?
    private var mcpManager: MCPManager?
    private var sessionID: String
    private var sessionState: [String: String]
    private var chatHistory: [Message]
    private var isCancelled: Bool = false

    /// Store for full tool outputs — the model sees summarized versions,
    /// but the full output is always available for inspection.
    public let toolOutputStore: ToolOutputStore

    public init(
        id: String = UUID().uuidString,
        configuration: AgentConfiguration = AgentConfiguration(),
        model: any ModelProvider,
        tools: [Tool] = [],
        toolKits: [any ToolKit] = [],
        nativeTools: [any NativeTool] = [],
        skills: [Skill] = [],
        storage: (any StorageBackend)? = nil,
        knowledge: (any KnowledgeSource)? = nil,
        learning: LearningEngine? = nil,
        mcpManager: MCPManager? = nil,
        sessionID: String = UUID().uuidString,
        sessionState: [String: String] = [:]
    ) {
        self.id = id
        self.configuration = configuration
        self.model = model

        var registry = ToolRegistry(tools: tools)
        for kit in toolKits {
            registry.register(contentsOf: kit)
        }
        // Auto-register native tools so the LLM can call them
        for nativeTool in nativeTools {
            registry.register(nativeTool.asTool())
        }
        self.toolRegistry = registry
        self.nativeTools = nativeTools
        self.skills = skills
        self.storage = storage
        self.knowledge = knowledge
        self.learning = learning
        self.mcpManager = mcpManager
        self.sessionID = sessionID
        self.sessionState = sessionState
        self.chatHistory = []
        self.toolOutputStore = ToolOutputStore()
    }

    // MARK: - Public API

    /// Run the agent with a text input and return the complete result.
    public func run(_ input: String) async throws -> RunResult {
        try await run(messages: [.user(input)])
    }

    /// Run the agent with a multimodal input.
    public func run(messages userMessages: [Message]) async throws -> RunResult {
        try await run(messages: userMessages, eventHandler: nil)
    }

    /// Internal run with optional event handler for streaming.
    private func run(
        messages userMessages: [Message],
        eventHandler: ((RunEvent) -> Void)?
    ) async throws -> RunResult {
        isCancelled = false
        let runID = UUID().uuidString
        let start = CFAbsoluteTimeGetCurrent()

        Log.agent.info("Run started: \(runID) on agent \(self.configuration.name)")
        eventHandler?(.started(runID: runID))

        // 1. Restore session if storage is available
        if let storage {
            if let session = try await storage.getSession(id: sessionID) {
                chatHistory = session.messages
                sessionState = session.state
            }
        }

        // 1b. Register MCP tools if connected
        if let mcpManager {
            let mcpTools = await mcpManager.allTools()
            for tool in mcpTools {
                toolRegistry.register(tool)
            }
        }

        // 1c. Warn if model doesn't support tool calling but tools are registered
        if !self.model.supportsToolCalling && !self.toolRegistry.allTools.isEmpty {
            let toolCount = self.toolRegistry.allTools.count
            let modelName = self.model.displayName
            Log.agent.warning("Model \(modelName) does not support tool calling, but \(toolCount) tools are registered. Tools will not work.")
        }

        // 2. Build system prompt with knowledge and learning context
        let knowledgeContext = try await buildKnowledgeContext(for: userMessages)
        let learningContext = try await buildLearningContext()

        let systemPrompt = configuration.buildSystemPrompt(
            nativeTools: nativeTools,
            skills: skills,
            knowledgeContext: knowledgeContext,
            learningContext: learningContext
        )

        // 3. Build message list (apply context trimming)
        let trimmedHistory = ContextManager.trimHistory(
            chatHistory,
            maxMessages: configuration.maxHistoryMessages,
            maxToolResults: configuration.maxHistoryToolResults
        )
        if trimmedHistory.count < chatHistory.count {
            Log.agent.info("Context trimmed: \(self.chatHistory.count) → \(trimmedHistory.count) messages")
        }

        var runMessages: [Message] = [.system(systemPrompt)]
        runMessages.append(contentsOf: trimmedHistory)
        runMessages.append(contentsOf: userMessages)

        // 4. Add user messages to history
        chatHistory.append(contentsOf: userMessages)

        // 5. Execute the run loop
        var result = RunResult(
            runID: runID,
            agentID: id,
            sessionID: sessionID,
            sessionState: sessionState
        )

        let toolDefs = toolRegistry.definitions
        var iterations = 0
        var totalToolCalls = 0

        while iterations < configuration.maxIterations {
            guard !isCancelled else {
                result.status = .cancelled
                eventHandler?(.cancelled)
                break
            }

            iterations += 1
            Log.agent.debug("Iteration \(iterations)/\(self.configuration.maxIterations)")

            // Call the model
            eventHandler?(.modelRequestStarted)

            let response: ModelResponse

            if eventHandler != nil {
                // Streaming path: emit tokens as they arrive so the UI can show progress
                var accumulatedText = ""
                var accumulatedToolCalls: [ToolCall] = []
                var finalMetrics = ModelMetrics()

                let stream = model.generateStream(
                    messages: runMessages,
                    config: configuration.generationConfig,
                    tools: toolDefs
                )
                for try await delta in stream {
                    switch delta {
                    case .text(let fragment):
                        accumulatedText += fragment
                        eventHandler?(.contentDelta(fragment))
                    case .toolCall(let tc):
                        accumulatedToolCalls.append(tc)
                    case .done(let metrics):
                        finalMetrics = metrics
                    }
                }

                let message = Message(
                    role: .assistant,
                    content: [.text(accumulatedText)],
                    toolCalls: accumulatedToolCalls.isEmpty ? nil : accumulatedToolCalls
                )
                response = ModelResponse(
                    message: message,
                    metrics: finalMetrics,
                    finishReason: accumulatedToolCalls.isEmpty ? .stop : .toolCall
                )
            } else {
                // Non-streaming path: blocking generate for programmatic callers
                response = try await model.generate(
                    messages: runMessages,
                    config: configuration.generationConfig,
                    tools: toolDefs
                )
            }

            eventHandler?(.modelRequestCompleted(response.metrics))

            result.metrics.accumulate(response.metrics)

            // Add assistant response to messages
            runMessages.append(response.message)
            chatHistory.append(response.message)

            // If no tool calls, we're done
            guard let toolCalls = response.message.toolCalls, !toolCalls.isEmpty else {
                result.content = response.message.text
                result.status = .completed
                break
            }

            // Check tool call limit
            totalToolCalls += toolCalls.count
            if totalToolCalls > configuration.toolCallLimit {
                throw SBBenderError.toolCallLimitExceeded(configuration.toolCallLimit)
            }

            // Execute tool calls
            let toolContext = ToolContext(
                agentID: id,
                sessionID: sessionID,
                runID: runID,
                sessionState: sessionState
            )

            var shouldStop = false

            for tc in toolCalls {
                guard let tool = toolRegistry.get(tc.name) else {
                    let errMsg = "Tool '\(tc.name)' not found"
                    Log.tool.error("\(errMsg)")
                    eventHandler?(.toolCallError(name: tc.name, error: errMsg))
                    let toolResult = Message.tool(id: tc.id, result: "Error: \(errMsg)", name: tc.name)
                    runMessages.append(toolResult)
                    chatHistory.append(toolResult)
                    result.toolExecutions.append(ToolExecution(
                        toolName: tc.name, callID: tc.id, arguments: tc.arguments,
                        error: errMsg
                    ))
                    continue
                }

                eventHandler?(.toolCallStarted(name: tc.name, id: tc.id))
                let toolStart = CFAbsoluteTimeGetCurrent()

                do {
                    Log.tool.info("Executing tool: \(tc.name)")
                    let rawToolOutput = try await tool.execute(arguments: tc.arguments, context: toolContext)
                    let toolLatency = CFAbsoluteTimeGetCurrent() - toolStart

                    // Store full output and get model-facing version
                    let toolOutput: String
                    if let maxLen = tool.maxContentLength, rawToolOutput.count > maxLen {
                        Log.tool.info("Tool output stored (\(rawToolOutput.count) chars), model sees \(maxLen) chars")
                        toolOutput = ContextManager.processToolOutput(
                            rawToolOutput,
                            maxLength: maxLen,
                            toolName: tc.name,
                            callID: tc.id,
                            store: toolOutputStore
                        )
                    } else {
                        // Still store for inspection even when not truncated
                        toolOutputStore.store(ToolOutputEntry(
                            callID: tc.id,
                            toolName: tc.name,
                            fullOutput: rawToolOutput,
                            timestamp: Date()
                        ))
                        toolOutput = rawToolOutput
                    }

                    eventHandler?(.toolCallCompleted(name: tc.name, result: rawToolOutput))

                    let toolResult = Message.tool(id: tc.id, result: toolOutput, name: tc.name)
                    runMessages.append(toolResult)
                    chatHistory.append(toolResult)

                    result.toolExecutions.append(ToolExecution(
                        toolName: tc.name, callID: tc.id, arguments: tc.arguments,
                        result: rawToolOutput, latency: toolLatency
                    ))
                    result.metrics.toolCalls += 1

                    if tool.stopAfterCall {
                        result.content = toolOutput
                        shouldStop = true
                    }
                } catch {
                    let toolLatency = CFAbsoluteTimeGetCurrent() - toolStart
                    let errMsg = error.localizedDescription
                    Log.tool.error("Tool \(tc.name) failed: \(errMsg)")

                    eventHandler?(.toolCallError(name: tc.name, error: errMsg))

                    let toolResult = Message.tool(id: tc.id, result: "Error: \(errMsg)", name: tc.name)
                    runMessages.append(toolResult)
                    chatHistory.append(toolResult)

                    result.toolExecutions.append(ToolExecution(
                        toolName: tc.name, callID: tc.id, arguments: tc.arguments,
                        error: errMsg, latency: toolLatency
                    ))
                }
            }

            if shouldStop {
                result.status = .completed
                break
            }
        }

        if result.status == .running {
            // Exhausted iterations without a final response
            result.status = .completed
            if result.content.isEmpty {
                result.content = runMessages.last(where: { $0.role == .assistant })?.text ?? ""
            }
        }

        result.messages = runMessages

        // 6. Persist session
        if let storage {
            let session = Session(
                id: sessionID,
                agentID: id,
                messages: chatHistory,
                state: sessionState,
                createdAt: Date(),
                updatedAt: Date()
            )
            try await storage.upsertSession(session)
        }

        // 7. Process learning
        if let learning {
            try await learning.process(messages: chatHistory, runResult: result)
        }

        let totalLatency = CFAbsoluteTimeGetCurrent() - start
        result.metrics.totalLatency = totalLatency
        Log.agent.info("Run completed: \(runID) in \(String(format: "%.2f", totalLatency))s")

        return result
    }

    /// Stream the agent's response with real-time events for tool calls, model requests, and content.
    public func runStream(_ input: String) -> AsyncThrowingStream<RunEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let result = try await self.run(
                        messages: [.user(input)],
                        eventHandler: { event in
                            continuation.yield(event)
                        }
                    )
                    continuation.yield(.completed(result))
                    continuation.finish()
                } catch {
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    /// Cancel a running agent invocation.
    public func cancel() {
        isCancelled = true
    }

    /// Reset the agent's chat history and session state.
    public func reset() {
        chatHistory = []
        sessionState = [:]
        sessionID = UUID().uuidString
        isCancelled = false
    }

    // MARK: - Mutators

    public func addTool(_ tool: Tool) {
        toolRegistry.register(tool)
    }

    public func addNativeTool(_ nativeTool: any NativeTool) {
        nativeTools.append(nativeTool)
        toolRegistry.register(nativeTool.asTool())
    }

    /// Connect to an MCP server and register its tools.
    public func connectMCP(
        name: String,
        command: String,
        args: [String] = [],
        environment: [String: String]? = nil
    ) async throws {
        let manager: MCPManager
        if let existing = mcpManager {
            manager = existing
        } else {
            let m = MCPManager()
            mcpManager = m
            manager = m
        }

        try await manager.connect(name: name, command: command, args: args, environment: environment)

        let mcpTools = await manager.tools(for: name)
        for tool in mcpTools {
            toolRegistry.register(tool)
        }
    }

    /// Connect to an MCP server via an existing transport (for testing or custom transports).
    public func connectMCP(name: String, transport: any MCP.Transport) async throws {
        let manager: MCPManager
        if let existing = mcpManager {
            manager = existing
        } else {
            let m = MCPManager()
            mcpManager = m
            manager = m
        }

        try await manager.connect(name: name, transport: transport)

        let mcpTools = await manager.tools(for: name)
        for tool in mcpTools {
            toolRegistry.register(tool)
        }
    }

    // MARK: - Private Helpers

    private func buildKnowledgeContext(for messages: [Message]) async throws -> String? {
        guard let knowledge else { return nil }
        let query = messages.compactMap(\.text).last ?? ""
        guard !query.isEmpty else { return nil }

        let docs = try await knowledge.search(query: query, limit: 5)
        guard !docs.isEmpty else { return nil }

        return docs.map { $0.content }.joined(separator: "\n\n---\n\n")
    }

    private func buildLearningContext() async throws -> String? {
        guard let learning else { return nil }
        return try await learning.recall(sessionID: sessionID)
    }
}
