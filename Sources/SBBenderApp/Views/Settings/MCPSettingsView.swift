import SwiftUI
import SBBender

struct MCPSettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var showConnectionSheet = false
    @State private var editingConfig: MCPServerConfig?
    @State private var curatedServers: [MCPServerEntry] = []
    @State private var loadingCurated = false
    @State private var expandedServerID: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Curated servers — loaded immediately
                curatedSection

                if !appState.mcpServerConfigs.isEmpty {
                    Divider()
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                }

                // Custom servers
                customServersSection
            }
        }
        .task {
            await loadCuratedServers()
        }
        .sheet(isPresented: $showConnectionSheet) {
            MCPConnectionSheet(existingConfig: editingConfig)
                .environment(appState)
        }
    }

    // MARK: - Curated Servers

    private var curatedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recommended")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            if loadingCurated {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading recommendations...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 12)
            } else if curatedServers.isEmpty {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("Could not load recommended plugins. Check your internet connection.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                ForEach(curatedServers) { server in
                    curatedServerCard(server)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }

    // MARK: - Custom Servers

    private var customServersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Your Plugins")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                Spacer()
                Button {
                    editingConfig = nil
                    showConnectionSheet = true
                } label: {
                    Label("Add Custom", systemImage: "plus")
                        .font(.caption)
                }
                .controlSize(.small)
            }

            if appState.mcpServerConfigs.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "puzzlepiece.extension")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text("No plugins configured. Add one above or use a recommended plugin.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                ForEach(appState.mcpServerConfigs) { server in
                    customServerRow(server)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    // MARK: - Curated Server Card

    private func curatedServerCard(_ server: MCPServerEntry) -> some View {
        let alreadyAdded = appState.mcpServerConfigs.contains { $0.name == server.name }
        let isExpanded = expandedServerID == server.id

        return VStack(alignment: .leading, spacing: 0) {
            // Main row
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(server.name)
                            .font(.body.weight(.medium))
                        Text(server.category)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.blue.opacity(0.12)))
                            .foregroundStyle(.blue)
                    }
                    Text(server.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(isExpanded ? nil : 2)
                }

                Spacer()

                if alreadyAdded {
                    Label("Added", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Button("Add") {
                        addCuratedServer(server)
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                }
            }

            // Setup instructions toggle
            if let instructions = server.setupInstructions, !instructions.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedServerID = isExpanded ? nil : server.id
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                        Text("Setup Instructions")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)

                if isExpanded {
                    Text(instructions)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                        .padding(.leading, 2)

                    // Show required binaries
                    if !server.requiredBins.isEmpty {
                        HStack(spacing: 4) {
                            Text("Requires:")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            ForEach(server.requiredBins, id: \.self) { bin in
                                Text(bin)
                                    .font(.system(.caption2, design: .monospaced))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(Color.secondary.opacity(0.1)))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))
    }

    // MARK: - Custom Server Row

    private func customServerRow(_ server: MCPServerConfig) -> some View {
        HStack(spacing: 8) {
            Image(systemName: server.enabled ? "circle.fill" : "circle")
                .foregroundStyle(server.enabled ? .green : .secondary)
                .font(.caption2)

            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                    .font(.body.weight(.medium))
                HStack(spacing: 4) {
                    Text(server.command)
                        .font(.system(.caption2, design: .monospaced))
                    Text(server.arguments.joined(separator: " "))
                        .font(.system(.caption2, design: .monospaced))
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
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
    }

    // MARK: - Actions

    private func loadCuratedServers() async {
        loadingCurated = true
        do {
            curatedServers = try await appState.curatedRegistry.compatibleMCPServers(
                for: appState.hardwareInfo.modelTier
            )
        } catch {
            curatedServers = []
        }
        loadingCurated = false
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
