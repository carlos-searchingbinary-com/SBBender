import Foundation

/// The status of an agent run.
public enum RunStatus: String, Sendable, Codable {
    case running
    case completed
    case paused
    case cancelled
    case error
}

/// An event emitted during a streaming agent run.
public enum RunEvent: Sendable {
    case started(runID: String)
    case contentDelta(String)
    case toolCallStarted(name: String, id: String)
    case toolCallCompleted(name: String, result: String)
    case toolCallError(name: String, error: String)
    case modelRequestStarted
    case modelRequestCompleted(ModelMetrics)
    case completed(RunResult)
    case error(String)
    case cancelled
}

/// The result of a complete agent run.
public struct RunResult: Sendable {
    public let runID: String
    public let agentID: String
    public let sessionID: String
    public var content: String
    public var messages: [Message]
    public var toolExecutions: [ToolExecution]
    public var metrics: RunMetrics
    public var status: RunStatus
    public var images: [ImageContent]
    public var audio: [AudioContent]
    public var sessionState: [String: String]

    public init(
        runID: String = UUID().uuidString,
        agentID: String = "",
        sessionID: String = "",
        content: String = "",
        messages: [Message] = [],
        toolExecutions: [ToolExecution] = [],
        metrics: RunMetrics = RunMetrics(),
        status: RunStatus = .running,
        images: [ImageContent] = [],
        audio: [AudioContent] = [],
        sessionState: [String: String] = [:]
    ) {
        self.runID = runID
        self.agentID = agentID
        self.sessionID = sessionID
        self.content = content
        self.messages = messages
        self.toolExecutions = toolExecutions
        self.metrics = metrics
        self.status = status
        self.images = images
        self.audio = audio
        self.sessionState = sessionState
    }
}

/// A record of a tool execution during a run.
public struct ToolExecution: Sendable {
    public let toolName: String
    public let callID: String
    public let arguments: String
    public var result: String?
    public var error: String?
    public var latency: TimeInterval

    public init(
        toolName: String,
        callID: String,
        arguments: String,
        result: String? = nil,
        error: String? = nil,
        latency: TimeInterval = 0
    ) {
        self.toolName = toolName
        self.callID = callID
        self.arguments = arguments
        self.result = result
        self.error = error
        self.latency = latency
    }

    public var succeeded: Bool {
        error == nil
    }
}

/// Aggregated metrics for an entire run (may include multiple model calls).
public struct RunMetrics: Sendable {
    public var totalInputTokens: Int
    public var totalOutputTokens: Int
    public var totalTokens: Int
    public var totalLatency: TimeInterval
    public var modelCalls: Int
    public var toolCalls: Int

    public init(
        totalInputTokens: Int = 0,
        totalOutputTokens: Int = 0,
        totalTokens: Int = 0,
        totalLatency: TimeInterval = 0,
        modelCalls: Int = 0,
        toolCalls: Int = 0
    ) {
        self.totalInputTokens = totalInputTokens
        self.totalOutputTokens = totalOutputTokens
        self.totalTokens = totalTokens
        self.totalLatency = totalLatency
        self.modelCalls = modelCalls
        self.toolCalls = toolCalls
    }

    public mutating func accumulate(_ modelMetrics: ModelMetrics) {
        totalInputTokens += modelMetrics.inputTokens
        totalOutputTokens += modelMetrics.outputTokens
        totalTokens += modelMetrics.totalTokens
        totalLatency += modelMetrics.latency
        modelCalls += 1
    }
}
