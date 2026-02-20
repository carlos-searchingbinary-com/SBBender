import Foundation
import SwiftUI
import SBBender

/// Lightweight session summary for the session picker (no messages loaded).
struct SessionSummary: Identifiable {
    let id: String
    let title: String
    let updatedAt: Date
}

/// Information about a pending tool confirmation request.
struct ToolConfirmationInfo: Identifiable {
    let id: String
    let toolName: String
    let arguments: [String: String]
    let agent: Agent

    func approve() async {
        await agent.approveToolCall(id: id)
    }

    func deny() async {
        await agent.rejectToolCall(id: id)
    }
}

@MainActor
@Observable
final class AgentChatViewModel {
    var messages: [ChatMessage] = []
    var inputText: String = ""
    var isGenerating: Bool = false
    var status: AgentStatus = .idle
    var statusMessage: String = ""
    var metrics: RunMetrics?
    var toolOutputEntries: [ToolOutputEntry] = []
    var activityEvents: [ActivityEvent] = []
    var elapsedSeconds: Int = 0

    // Tool confirmation
    var pendingConfirmation: ToolConfirmationInfo?

    // Knowledge rehydration
    var isRehydrating: Bool = false
    var rehydrationProgress: IngestionProgress.Phase?

    // Session management
    var currentSessionID: String?
    var sessions: [SessionSummary] = []

    private var streamTask: Task<Void, Never>?
    private var elapsedTimer: Task<Void, Never>?

    func sendMessage(agent: Agent, agentName: String, providerType: String? = nil, modelID: String? = nil) async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }

        inputText = ""
        messages.append(ChatMessage(role: "user", content: text))
        isGenerating = true
        status = .thinking
        elapsedSeconds = 0

        if let provider = providerType, let model = modelID {
            activityEvents.append(ActivityEvent(
                kind: .modelRequest(provider: provider, model: model),
                agentName: agentName
            ))
        }
        activityEvents.append(ActivityEvent(kind: .thinking, agentName: agentName))

        // Start elapsed timer
        elapsedTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                self.elapsedSeconds += 1
            }
        }

        let task = Task {
            do {
                var streamedContent = ""
                var tokenCount = 0

                let stream = await agent.runStream(text)
                for try await event in stream {
                    if Task.isCancelled { break }

                    switch event {
                    case .started:
                        break
                    case .contentDelta(let delta):
                        streamedContent += delta
                        tokenCount += 1
                        status = .streaming
                        // Update last message if streaming, or add new one
                        if let last = messages.last, last.role == "assistant-streaming" {
                            messages[messages.count - 1] = ChatMessage(
                                id: last.id,
                                role: "assistant-streaming",
                                content: streamedContent
                            )
                        } else {
                            messages.append(ChatMessage(
                                role: "assistant-streaming",
                                content: streamedContent
                            ))
                        }
                    case .toolCallStarted(let name, _):
                        status = .working
                        activityEvents.append(ActivityEvent(
                            kind: .toolCallStarted(name: name),
                            agentName: agentName
                        ))
                    case .toolCallCompleted(let name, let result):
                        activityEvents.append(ActivityEvent(
                            kind: .toolCallCompleted(name: name, chars: result.count),
                            agentName: agentName
                        ))
                    case .toolCallError(let name, let error):
                        activityEvents.append(ActivityEvent(
                            kind: .toolCallError(name: name, error: error),
                            agentName: agentName
                        ))
                    case .toolConfirmationRequired(let name, let id, let argsJSON):
                        // Parse arguments for display
                        var displayArgs: [String: String] = [:]
                        if let data = argsJSON.data(using: .utf8),
                           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            for (key, value) in dict {
                                displayArgs[key] = "\(value)"
                            }
                        }
                        self.pendingConfirmation = ToolConfirmationInfo(
                            id: id,
                            toolName: name,
                            arguments: displayArgs,
                            agent: agent
                        )
                        activityEvents.append(ActivityEvent(
                            kind: .toolCallStarted(name: "\(name) (needs approval)"),
                            agentName: agentName
                        ))
                    case .modelRequestStarted:
                        status = .thinking
                    case .modelRequestCompleted:
                        break
                    case .completed(let result):
                        toolOutputEntries = await agent.toolOutputStore.allEntries

                        // Inject chart specs from tool outputs into content
                        var finalContent = result.content
                        for entry in toolOutputEntries {
                            if entry.fullOutput.contains("\"__chart__\""),
                               !finalContent.contains("\"__chart__\"") {
                                finalContent += "\n" + entry.fullOutput
                            }
                        }

                        let toolCalls = result.messages.compactMap(\.toolCalls).flatMap { $0 }

                        // Replace streaming message with final
                        if let idx = messages.lastIndex(where: { $0.role == "assistant-streaming" }) {
                            messages[idx] = ChatMessage(
                                role: "assistant",
                                content: finalContent,
                                toolCalls: toolCalls
                            )
                        } else if !finalContent.isEmpty {
                            messages.append(ChatMessage(
                                role: "assistant",
                                content: finalContent,
                                toolCalls: toolCalls
                            ))
                        }
                        metrics = result.metrics
                        let latency = result.metrics.totalLatency
                        let tools = result.metrics.toolCalls
                        activityEvents.append(ActivityEvent(
                            kind: .completed(latency: latency, toolCalls: tools),
                            agentName: agentName
                        ))
                        status = .done
                        if tools > 0 {
                            statusMessage = "\(tools) action\(tools == 1 ? "" : "s"), \(String(format: "%.1f", latency))s"
                        } else {
                            statusMessage = "\(String(format: "%.1f", latency))s"
                        }
                    case .error(let msg):
                        activityEvents.append(ActivityEvent(kind: .error(msg), agentName: agentName))
                        messages.append(ChatMessage(role: "error", content: msg))
                        status = .error
                    case .cancelled:
                        status = .idle
                    }
                }
            } catch {
                if !Task.isCancelled {
                    messages.append(ChatMessage(role: "error", content: error.localizedDescription))
                    activityEvents.append(ActivityEvent(
                        kind: .error(error.localizedDescription),
                        agentName: agentName
                    ))
                    status = .error
                }
            }
            isGenerating = false
            elapsedTimer?.cancel()
        }
        self.streamTask = task
    }

    func cancel() {
        streamTask?.cancel()
        elapsedTimer?.cancel()
        isGenerating = false
        elapsedSeconds = 0
        status = .idle
    }

    // MARK: - Session Management

    /// Load the most recent session for this agent, or start fresh.
    func loadConversation(storage: (any StorageBackend)?, agentID: String) async {
        guard let storage else { return }
        do {
            // Load session list
            let allSessions = try await storage.listSessions(agentID: agentID)
            sessions = allSessions.map { s in
                SessionSummary(id: s.id, title: s.title, updatedAt: s.updatedAt)
            }

            // Load most recent session if we don't have one selected
            if currentSessionID == nil, let latest = allSessions.first {
                currentSessionID = latest.id
                loadMessages(from: latest)
            } else if let sid = currentSessionID,
                      let session = allSessions.first(where: { $0.id == sid }) {
                loadMessages(from: session)
            }
        } catch {
            // Session load failed — start fresh
        }
    }

    /// Switch to a different session.
    func switchSession(to sessionID: String, storage: (any StorageBackend)?) async {
        guard let storage else { return }
        do {
            guard let session = try await storage.getSession(id: sessionID) else { return }
            currentSessionID = sessionID
            loadMessages(from: session)
            metrics = nil
            toolOutputEntries = []
            activityEvents = []
            statusMessage = ""
            status = .idle
        } catch {
            // Switch failed
        }
    }

    /// Create a new chat session (preserving the old one).
    func newChat(agent: Agent?, storage: (any StorageBackend)?, agentID: String?) async {
        messages.removeAll()
        metrics = nil
        toolOutputEntries = []
        activityEvents = []
        statusMessage = ""
        status = .idle
        if let agent {
            await agent.reset()
        }

        // Create a new session ID — old session stays in storage
        let newID = UUID().uuidString
        currentSessionID = newID

        // Set the agent's sessionID to the new session
        if let agent, let agentID {
            await agent.setSessionID(newID)

            // Persist the empty session so it shows in the list
            if let storage {
                let session = Session(id: newID, agentID: agentID, title: "New Chat")
                try? await storage.upsertSession(session)
                // Refresh session list
                await loadSessionList(storage: storage, agentID: agentID)
            }
        }
    }

    /// Delete a specific session.
    func deleteSession(_ sessionID: String, storage: (any StorageBackend)?, agentID: String?) async {
        guard let storage else { return }
        try? await storage.deleteSession(id: sessionID)
        sessions.removeAll { $0.id == sessionID }

        // If we deleted the current session, switch to another or start fresh
        if currentSessionID == sessionID {
            if let next = sessions.first {
                await switchSession(to: next.id, storage: storage)
            } else {
                await newChat(agent: nil, storage: storage, agentID: agentID)
            }
        }
    }

    /// Persist a session title (provided by the caller, e.g. LLM-generated or truncated fallback).
    func updateSessionTitle(to title: String, storage: (any StorageBackend)?, agentID: String) async {
        guard let storage, let sid = currentSessionID else { return }
        do {
            if var session = try await storage.getSession(id: sid) {
                session.title = title
                session.updatedAt = Date()
                try await storage.upsertSession(session)
                if let idx = sessions.firstIndex(where: { $0.id == sid }) {
                    sessions[idx] = SessionSummary(id: sid, title: title, updatedAt: Date())
                }
            }
        } catch {
            // Title update failed — not critical
        }
    }

    // MARK: - Legacy clearChat (for backwards compat)

    func clearChat(agent: Agent?, storage: (any StorageBackend)?, agentID: String?) async {
        await newChat(agent: agent, storage: storage, agentID: agentID)
    }

    // MARK: - Helpers

    private func loadMessages(from session: Session) {
        let loaded: [ChatMessage] = session.messages.compactMap { msg in
            guard msg.role != .system && msg.role != .tool else { return nil }
            let text = msg.content.compactMap { content -> String? in
                if case .text(let s) = content { return s }
                return nil
            }.joined()
            guard !text.isEmpty else { return nil }
            let role = msg.role == .user ? "user" : "assistant"
            return ChatMessage(
                id: msg.id,
                role: role,
                content: text,
                toolCalls: msg.toolCalls
            )
        }
        messages = loaded
    }

    private func loadSessionList(storage: any StorageBackend, agentID: String) async {
        do {
            let allSessions = try await storage.listSessions(agentID: agentID)
            sessions = allSessions.map { s in
                SessionSummary(id: s.id, title: s.title, updatedAt: s.updatedAt)
            }
        } catch {
            // List load failed
        }
    }
}
