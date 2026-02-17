import Foundation
import SwiftUI
import SBBender

@MainActor
@Observable
final class TeamWorkspaceViewModel {
    var inputText: String = ""
    var isRunning: Bool = false
    var resultContent: String = ""
    var memberResults: [MemberResult] = []
    var activityEvents: [ActivityEvent] = []
    var metrics: RunMetrics?
    var statusMessage: String = ""

    struct MemberResult: Identifiable {
        let id: String
        let agentName: String
        let content: String
        let latency: TimeInterval
        let toolCalls: Int
    }

    func run(
        teamConfig: TeamConfig,
        appState: AppState
    ) async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isRunning else { return }

        inputText = ""
        isRunning = true
        resultContent = ""
        memberResults = []
        activityEvents = []
        metrics = nil

        activityEvents.append(ActivityEvent(kind: .thinking, agentName: teamConfig.name))

        do {
            // Build member agents
            var members: [Agent] = []
            var leader: Agent?

            for memberID in teamConfig.memberIDs {
                guard let config = appState.agentConfig(for: memberID) else { continue }
                let agent = await appState.getOrCreateLiveAgent(for: config)
                members.append(agent)
                if memberID == teamConfig.leaderID {
                    leader = agent
                }
            }

            guard !members.isEmpty else {
                activityEvents.append(ActivityEvent(kind: .error("No valid members found"), agentName: teamConfig.name))
                isRunning = false
                return
            }

            // Determine swarm mode
            let mode: SwarmMode
            switch teamConfig.mode {
            case "parallel": mode = .parallel
            case "autonomous": mode = .autonomous
            default: mode = .sequential
            }

            let swarm = Swarm(
                name: teamConfig.name,
                mode: mode,
                leader: leader,
                members: members
            )

            // Mark members as working
            for memberID in teamConfig.memberIDs {
                if let config = appState.agentConfig(for: memberID) {
                    activityEvents.append(ActivityEvent(
                        kind: .toolCallStarted(name: "running"),
                        agentName: config.name
                    ))
                }
            }

            let result = try await swarm.run(text)

            resultContent = result.content
            metrics = result.metrics

            // Map member results
            for (i, memberResult) in result.memberResults.enumerated() {
                let name: String
                if i < teamConfig.memberIDs.count,
                   let config = appState.agentConfig(for: teamConfig.memberIDs[i]) {
                    name = config.name
                } else {
                    name = "Agent \(i + 1)"
                }
                memberResults.append(MemberResult(
                    id: memberResult.agentID,
                    agentName: name,
                    content: memberResult.content,
                    latency: memberResult.metrics.totalLatency,
                    toolCalls: memberResult.metrics.toolCalls
                ))
                activityEvents.append(ActivityEvent(
                    kind: .completed(latency: memberResult.metrics.totalLatency, toolCalls: memberResult.metrics.toolCalls),
                    agentName: name
                ))
            }

            let latency = result.metrics.totalLatency
            statusMessage = "\(result.memberResults.count) agents, \(String(format: "%.1f", latency))s total"
            activityEvents.append(ActivityEvent(
                kind: .completed(latency: latency, toolCalls: result.metrics.toolCalls),
                agentName: teamConfig.name
            ))
        } catch {
            activityEvents.append(ActivityEvent(
                kind: .error(error.localizedDescription),
                agentName: teamConfig.name
            ))
            resultContent = "Error: \(error.localizedDescription)"
        }

        isRunning = false
    }
}
