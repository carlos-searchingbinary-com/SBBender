import SwiftUI
import SBBender

struct MCPSettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var showConnectionSheet = false
    @State private var editingConfig: MCPServerConfig?
    @State private var showCurated = false
    @State private var curatedServers: [MCPServerEntry] = []
    @State private var loadingCurated = false

    var body: some View {
        Form {
            curatedSection
            customServersSection
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showConnectionSheet) {
            MCPConnectionSheet(existingConfig: editingConfig)
                .environment(appState)
        }
    }

    // MARK: - Curated MCP Servers

    @ViewBuilder
    private var curatedSection: some View {
        Section("Recommended MCP Servers") {
            DisclosureGroup("Browse Curated Servers", isExpanded: $showCurated) {
                if loadingCurated {
                    ProgressView("Loading curated servers...")
                        .font(.caption)
                } else if curatedServers.isEmpty {
                    Text("No curated servers available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(curatedServers) { server in
                        curatedServerRow(server)
                    }
                }
            }
            .onChange(of: showCurated) { _, expanded in
                if expanded && curatedServers.isEmpty {
                    loadCuratedServers()
                }
            }
        }
    }

    // MARK: - Custom Servers

    @ViewBuilder
    private var customServersSection: some View {
        Section {
            if appState.mcpServerConfigs.isEmpty {
                HStack {
                    Image(systemName: "server.rack")
                        .foregroundStyle(.secondary)
                    Text("No custom MCP servers configured.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(appState.mcpServerConfigs) { server in
                    HStack {
                        Image(systemName: server.enabled ? "circle.fill" : "circle")
                            .foregroundStyle(server.enabled ? .green : .secondary)
                            .font(.caption)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(server.name)
                                .font(.body.bold())
                            HStack(spacing: 4) {
                                Text(server.command)
                                    .font(.system(.caption, design: .monospaced))
                                Text(server.arguments.joined(separator: " "))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        Button {
                            editingConfig = server
                            showConnectionSheet = true
                        } label: {
                            Image(systemName: "pencil.circle")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { indices in
                    for index in indices {
                        appState.deleteMCPServerConfig(appState.mcpServerConfigs[index])
                    }
                }
            }
        } header: {
            HStack {
                Text("Custom MCP Servers")
                Spacer()
                Button {
                    editingConfig = nil
                    showConnectionSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Subviews

    private func curatedServerRow(_ server: MCPServerEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(server.name)
                        .font(.body.weight(.medium))
                    tierBadge(server.minModelTier)
                }
                Text(server.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(server.category)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.blue.opacity(0.1)))
                    ForEach(server.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            let alreadyAdded = appState.mcpServerConfigs.contains { $0.name == server.name }
            if alreadyAdded {
                Text("Added")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button("Add") {
                    addCuratedServer(server)
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func tierBadge(_ tier: ModelTier) -> some View {
        Text(tier.rawValue.uppercased())
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(tierColor(tier).opacity(0.15))
            )
            .foregroundStyle(tierColor(tier))
    }

    private func tierColor(_ tier: ModelTier) -> Color {
        switch tier {
        case .small: .green
        case .medium: .blue
        case .large: .purple
        case .xlarge: .orange
        }
    }

    // MARK: - Actions

    private func loadCuratedServers() {
        loadingCurated = true
        Task {
            do {
                curatedServers = try await appState.curatedRegistry.compatibleMCPServers(
                    for: appState.hardwareInfo.modelTier
                )
            } catch {
                curatedServers = []
            }
            loadingCurated = false
        }
    }

    private func addCuratedServer(_ entry: MCPServerEntry) {
        let config = MCPServerConfig(
            name: entry.name,
            command: entry.command,
            arguments: entry.arguments,
            environment: entry.environment ?? [:]
        )
        appState.saveMCPServerConfig(config)
    }
}
