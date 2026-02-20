import SwiftUI
import SBBender

struct TeamWorkspaceView: View {
    let teamID: String
    @Environment(AppState.self) private var appState
    @State private var viewModel = TeamWorkspaceViewModel()

    private var config: TeamConfig? {
        appState.teamConfig(for: teamID)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let config {
                teamHeader(config)
                Divider()
            }

            HSplitView {
                // Left: Input + Results
                VStack(spacing: 0) {
                    if !viewModel.resultContent.isEmpty {
                        resultSection
                    }

                    Spacer()

                    if let metrics = viewModel.metrics {
                        MetricsBar(metrics: metrics, statusMessage: viewModel.statusMessage)
                    }

                    Divider()
                    inputBar
                }
                .frame(minWidth: 500)

                // Right: Activity feed
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Activity")
                            .font(.headline)
                        Spacer()
                    }
                    .padding(12)
                    Divider()

                    if viewModel.activityEvents.isEmpty {
                        ContentUnavailableView(
                            "No Activity",
                            systemImage: "person.3",
                            description: Text("Run the team to see activity.")
                        )
                    } else {
                        ActivityFeedView(events: viewModel.activityEvents)
                    }
                }
                .frame(minWidth: 260, maxWidth: 360)
                .background(.ultraThinMaterial)
            }
        }
        .navigationTitle(config?.name ?? "Team Workspace")
    }

    private func teamHeader(_ config: TeamConfig) -> some View {
        HStack(spacing: 12) {
            AgentAvatar(emoji: config.emoji, gradientHex: config.gradientHex, size: 36)
            VStack(alignment: .leading) {
                Text(config.name)
                    .font(.headline)
                Text(config.mode.capitalized)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.purple.opacity(0.1))
                    .clipShape(Capsule())
            }
            Spacer()

            // Member avatars
            HStack(spacing: -6) {
                ForEach(config.memberIDs.prefix(6), id: \.self) { memberID in
                    if let member = appState.agentConfig(for: memberID) {
                        AgentAvatar(emoji: member.emoji, gradientHex: member.gradientHex, size: 28)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var resultSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Combined result
                GroupBox("Result") {
                    Text(viewModel.resultContent)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Per-member results
                if !viewModel.memberResults.isEmpty {
                    GroupBox("Member Results") {
                        ForEach(viewModel.memberResults) { result in
                            DisclosureGroup {
                                Text(result.content)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                            } label: {
                                HStack {
                                    Text(result.agentName)
                                        .font(.body.bold())
                                    Spacer()
                                    Text("\(String(format: "%.1f", result.latency))s")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if result.toolCalls > 0 {
                                        Text("\(result.toolCalls) actions")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextEditor(text: $viewModel.inputText)
                .font(.body)
                .frame(minHeight: 36, maxHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Button {
                guard let config else { return }
                Task { await viewModel.run(teamConfig: config, appState: appState) }
            } label: {
                if viewModel.isRunning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .buttonStyle(.plain)
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isRunning)
        }
        .padding(12)
    }
}
