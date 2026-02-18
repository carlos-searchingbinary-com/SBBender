import Foundation

/// Manages context window size while preserving full tool outputs for inspection.
///
/// The key insight: the **model** has limited context, but **we** don't.
/// Full tool outputs are stored in `ToolOutputStore` for later inspection.
/// Only the model-facing message gets a summarized version when the output
/// is too large for the context window.
public struct ContextManager: Sendable {

    /// Summarize a tool output for the model, preserving the full output
    /// in the store for inspection.
    ///
    /// - Parameters:
    ///   - output: The full tool output text.
    ///   - maxLength: Maximum length for the model-facing version.
    ///   - toolName: Name of the tool (for the store entry).
    ///   - callID: Tool call ID (for the store entry).
    ///   - store: The output store to save the full output in.
    /// - Returns: The model-facing version (may be summarized if too long).
    public static func processToolOutput(
        _ output: String,
        maxLength: Int,
        toolName: String,
        callID: String,
        store: ToolOutputStore
    ) -> String {
        // Always store the full output
        store.store(
            ToolOutputEntry(
                callID: callID,
                toolName: toolName,
                fullOutput: output,
                timestamp: Date()
            )
        )

        // If it fits, return as-is
        guard output.count > maxLength, maxLength > 0 else { return output }

        // Create a summarized version for the model
        let preview = String(output.prefix(maxLength))
        let totalChars = output.count
        return """
        \(preview)

        [Output truncated for context window. Full output: \(totalChars) chars, \
        stored as call_id=\(callID). Use the tool_output_inspector to view the full result.]
        """
    }

    /// Trim chat history to keep only the most recent messages.
    ///
    /// - Parameters:
    ///   - messages: The full chat history.
    ///   - maxMessages: If set, keep only the last N non-system messages.
    ///   - maxToolResults: If set, keep only the last N tool result messages.
    /// - Returns: The trimmed message list, always preserving system messages.
    public static func trimHistory(
        _ messages: [Message],
        maxMessages: Int?,
        maxToolResults: Int?
    ) -> [Message] {
        var result = messages

        // Trim tool results first (they tend to be large and numerous)
        if let maxTool = maxToolResults {
            var toolCount = 0
            var indicesToRemove: [Int] = []
            // Walk backward to count from most recent; indices collected are already descending
            for i in stride(from: result.count - 1, through: 0, by: -1) {
                if result[i].role == .tool {
                    toolCount += 1
                    if toolCount > maxTool {
                        indicesToRemove.append(i)
                    }
                }
            }
            // Remove in descending index order to avoid shifting issues
            for i in indicesToRemove.sorted(by: >) {
                result.remove(at: i)
            }
        }

        // Trim total messages (keep system messages always)
        if let maxMsg = maxMessages {
            let systemMessages = result.filter { $0.role == .system }
            let nonSystem = result.filter { $0.role != .system }
            if nonSystem.count > maxMsg {
                let kept = Array(nonSystem.suffix(maxMsg))
                result = systemMessages + kept
            }
        }

        return result
    }

    /// Estimate token count for a list of messages.
    ///
    /// Uses a rough heuristic of ~4 characters per token.
    public static func estimateTokens(_ messages: [Message]) -> Int {
        let totalChars = messages.reduce(0) { sum, msg in
            sum + msg.content.reduce(0) { s, c in
                switch c {
                case .text(let t): return s + t.count
                default: return s + 100
                }
            }
        }
        return totalChars / 4
    }

    /// Enforce a token budget on run messages by removing older non-system
    /// messages until the estimated token count fits within the budget.
    ///
    /// Preserves: system messages (first), the most recent user message, and
    /// as many recent assistant/tool messages as fit.
    public static func enforceTokenBudget(
        _ messages: [Message],
        maxTokens: Int
    ) -> [Message] {
        let estimated = estimateTokens(messages)
        guard estimated > maxTokens else { return messages }

        // Separate system messages (always kept) from the rest
        let systemMessages = messages.filter { $0.role == .system }
        let nonSystem = messages.filter { $0.role != .system }

        let systemTokens = estimateTokens(systemMessages)
        let budget = maxTokens - systemTokens
        guard budget > 0 else { return systemMessages }

        // Keep as many recent non-system messages as fit within budget
        var kept: [Message] = []
        var usedTokens = 0
        for msg in nonSystem.reversed() {
            let msgTokens = estimateTokens([msg])
            if usedTokens + msgTokens > budget && !kept.isEmpty {
                break
            }
            kept.insert(msg, at: 0)
            usedTokens += msgTokens
        }

        return systemMessages + kept
    }
}

// MARK: - Tool Output Store

/// A single stored tool output entry.
public struct ToolOutputEntry: Sendable {
    public let callID: String
    public let toolName: String
    public let fullOutput: String
    public let timestamp: Date

    public init(callID: String, toolName: String, fullOutput: String, timestamp: Date) {
        self.callID = callID
        self.toolName = toolName
        self.fullOutput = fullOutput
        self.timestamp = timestamp
    }

    public var characterCount: Int { fullOutput.count }
}

/// Thread-safe store for full tool outputs.
///
/// The model sees summarized versions; the full output is stored here
/// for inspection via the SwiftUI app, debugging, or the agent itself
/// (via a `tool_output_inspector` tool).
public final class ToolOutputStore: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: StoreState())

    struct StoreState: Sendable {
        var entries: [String: ToolOutputEntry] = [:] // keyed by callID
        var orderedIDs: [String] = []
    }

    /// Maximum number of entries to keep. Oldest are evicted when exceeded.
    public let maxEntries: Int

    public init(maxEntries: Int = 100) {
        self.maxEntries = maxEntries
    }

    /// Store a tool output entry.
    public func store(_ entry: ToolOutputEntry) {
        lock.withLock { state in
            state.entries[entry.callID] = entry
            state.orderedIDs.append(entry.callID)

            // Evict oldest if over limit
            while state.orderedIDs.count > maxEntries {
                let oldest = state.orderedIDs.removeFirst()
                state.entries.removeValue(forKey: oldest)
            }
        }
    }

    /// Retrieve the full output for a specific tool call.
    public func get(callID: String) -> ToolOutputEntry? {
        lock.withLock { $0.entries[callID] }
    }

    /// Get all stored entries in chronological order.
    public var allEntries: [ToolOutputEntry] {
        lock.withLock { state in
            state.orderedIDs.compactMap { state.entries[$0] }
        }
    }

    /// Get the most recent N entries.
    public func recent(_ count: Int) -> [ToolOutputEntry] {
        lock.withLock { state in
            let ids = state.orderedIDs.suffix(count)
            return ids.compactMap { state.entries[$0] }
        }
    }

    /// Clear all stored outputs.
    public func clear() {
        lock.withLock { state in
            state.entries.removeAll()
            state.orderedIDs.removeAll()
        }
    }

    /// Total number of stored entries.
    public var count: Int {
        lock.withLock { $0.entries.count }
    }
}

import os
