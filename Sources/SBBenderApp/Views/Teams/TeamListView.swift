import SwiftUI

struct TeamListView: View {
    @Environment(AppState.self) private var appState
    @State private var showingBuilder = false
    @State private var editingTeam: TeamConfig?

    private let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            if appState.agents.isEmpty {
                ContentUnavailableView(
                    "Create Agents First",
                    systemImage: "brain.head.profile",
                    description: Text("You need at least one agent before creating a team.")
                )
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    // New Team card
                    Button { showingBuilder = true } label: {
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 64, height: 64)
                                Image(systemName: "plus")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                            }
                            Text("New Team")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)

                    ForEach(appState.teams) { team in
                        TeamCard(config: team, agents: appState.agents) {
                            appState.selectedSidebarItem = .teamWorkspace(team.id)
                        } onEdit: {
                            editingTeam = team
                        } onDelete: {
                            appState.deleteTeam(team)
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("My Teams")
        .sheet(isPresented: $showingBuilder) {
            TeamBuilderSheet(config: nil)
                .environment(appState)
        }
        .sheet(item: $editingTeam) { team in
            TeamBuilderSheet(config: team)
                .environment(appState)
        }
    }
}

private struct TeamCard: View {
    let config: TeamConfig
    let agents: [AgentConfig]
    let onRun: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 12) {
            AgentAvatar(emoji: config.emoji, gradientHex: config.gradientHex, size: 64)

            Text(config.name)
                .font(.headline)
                .lineLimit(1)

            Text(config.mode.capitalized)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.purple.opacity(0.1))
                .clipShape(Capsule())

            // Member avatars
            HStack(spacing: -8) {
                ForEach(config.memberIDs.prefix(4), id: \.self) { memberID in
                    if let member = agents.first(where: { $0.id == memberID }) {
                        AgentAvatar(emoji: member.emoji, gradientHex: member.gradientHex, size: 24)
                    }
                }
                if config.memberIDs.count > 4 {
                    Text("+\(config.memberIDs.count - 4)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 12)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isHovered ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 2)
        )
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onRun)
        .contextMenu {
            Button("Run", systemImage: "play", action: onRun)
            Button("Edit", systemImage: "pencil", action: onEdit)
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }
}
