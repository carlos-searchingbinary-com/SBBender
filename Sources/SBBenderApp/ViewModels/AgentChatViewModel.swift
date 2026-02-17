import Foundation
import SwiftUI
import SBBender

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

    private var streamTask: Task<Void, Never>?

    func sendMessage(agent: Agent, agentName: String) async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }

        inputText = ""
        messages.append(ChatMessage(role: "user", content: text))
        isGenerating = true
        status = .thinking
        activityEvents.append(ActivityEvent(kind: .thinking, agentName: agentName))

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
                    case .modelRequestStarted:
                        status = .thinking
                    case .modelRequestCompleted:
                        break
                    case .completed(let result):
                        // Replace streaming message with final
                        if let idx = messages.lastIndex(where: { $0.role == "assistant-streaming" }) {
                            messages[idx] = ChatMessage(
                                role: "assistant",
                                content: result.content,
                                toolCalls: result.messages.compactMap(\.toolCalls).flatMap { $0 }
                            )
                        } else if !result.content.isEmpty {
                            messages.append(ChatMessage(
                                role: "assistant",
                                content: result.content,
                                toolCalls: result.messages.compactMap(\.toolCalls).flatMap { $0 }
                            ))
                        }
                        metrics = result.metrics
                        toolOutputEntries = await agent.toolOutputStore.allEntries
                        let latency = result.metrics.totalLatency
                        let tools = result.metrics.toolCalls
                        activityEvents.append(ActivityEvent(
                            kind: .completed(latency: latency, toolCalls: tools),
                            agentName: agentName
                        ))
                        status = .done
                        if tools > 0 {
                            statusMessage = "\(tools) tool call(s), \(String(format: "%.1f", latency))s"
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
        }
        self.streamTask = task
    }

    func cancel() {
        streamTask?.cancel()
        isGenerating = false
        status = .idle
    }

    func loadConversation(storage: (any StorageBackend)?, agentID: String) async {
        guard let storage else { return }
        do {
            guard let session = try await storage.getSession(id: agentID) else { return }
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
            if !loaded.isEmpty {
                messages = loaded
            }
        } catch {
            // Session load failed — start fresh
        }
    }

    func clearChat(agent: Agent?, storage: (any StorageBackend)?, agentID: String?) async {
        messages.removeAll()
        metrics = nil
        toolOutputEntries = []
        activityEvents = []
        statusMessage = ""
        status = .idle
        if let agent {
            await agent.reset()
        }
        if let storage, let agentID {
            try? await storage.deleteSession(id: agentID)
        }
    }
}
