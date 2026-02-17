import SwiftUI
import SBBender

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @State private var activeSessionIDs: Set<String> = []

    var body: some View {
        @Bindable var state = appState
        NavigationSplitView {
            List(selection: $state.selectedSidebarItem) {
                Section("Agents") {
                    Label("My Agents", systemImage: "brain.head.profile")
                        .tag(SidebarItem.agents)

                    // Active agent chats — always visible
                    ForEach(appState.agents) { agent in
                        Label {
                            HStack(spacing: 6) {
                                Text(agent.name)
                                    .lineLimit(1)
                                if activeSessionIDs.contains(agent.id) {
                                    Circle()
                                        .fill(.green)
                                        .frame(width: 6, height: 6)
                                }
                            }
                        } icon: {
                            Text(agent.emoji)
                                .font(.caption)
                        }
                        .tag(SidebarItem.agentChat(agent.id))
                    }
                }
                Section("Teams") {
                    Label("My Teams", systemImage: "person.3.fill")
                        .tag(SidebarItem.teams)
                }
                Section("Skills") {
                    Label("Marketplace", systemImage: "storefront")
                        .tag(SidebarItem.marketplace)
                    Label("Skill Lab", systemImage: "flask")
                        .tag(SidebarItem.skillLab)
                }
                Section("Tools") {
                    Label("Custom Tools", systemImage: "wrench.and.screwdriver")
                        .tag(SidebarItem.toolManager)
                    Label("MCP Servers", systemImage: "server.rack")
                        .tag(SidebarItem.mcpServers)
                }
                Section {
                    Label("Settings", systemImage: "gear")
                        .tag(SidebarItem.settings)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("SBBender")
            .frame(minWidth: 200)
            .task {
                await loadActiveSessions()
            }
        } detail: {
            detailView
                .environment(appState)
        }
    }

    private func loadActiveSessions() async {
        guard let storage = await appState.persistence?.storage else { return }
        var ids: Set<String> = []
        for agent in appState.agents {
            do {
                if let session = try await storage.getSession(id: agent.id),
                   !session.messages.isEmpty {
                    ids.insert(agent.id)
                }
            } catch {}
        }
        activeSessionIDs = ids
    }

    @ViewBuilder
    private var detailView: some View {
        switch appState.selectedSidebarItem {
        case .agents:
            AgentListView()
        case .agentChat(let id):
            AgentChatView(agentID: id)
        case .teams:
            TeamListView()
        case .teamWorkspace(let id):
            TeamWorkspaceView(teamID: id)
        case .marketplace:
            MarketplaceView()
        case .skillDetail:
            SkillsShSkillPage()
        case .nativeSkillDetail(let id):
            NativeSkillDetailPage(skillID: id)
        case .skillLab:
            SkillLabView()
        case .toolManager:
            ToolManagerView()
        case .mcpServers:
            MCPServersView()
        case .settings:
            SettingsView()
        case .none:
            ContentUnavailableView(
                "Select an Item",
                systemImage: "brain.head.profile",
                description: Text("Choose a section from the sidebar to get started.")
            )
        }
    }
}
