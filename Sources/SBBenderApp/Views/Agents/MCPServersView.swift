import SwiftUI

struct MCPServersView: View {
    @Environment(AppState.self) private var appState
    @State private var showConnectionSheet = false
    @State private var editingConfig: MCPServerConfig?

    var body: some View {
        VStack(spacing: 0) {
            if appState.mcpServerConfigs.isEmpty {
                ContentUnavailableView(
                    "No Plugins",
                    systemImage: "puzzlepiece.extension",
                    description: Text("Plugins let your assistants connect to external services and gain new abilities.")
                )
            } else {
                List {
                    ForEach(appState.mcpServerConfigs) { server in
                        HStack {
                            Image(systemName: server.enabled ? "circle.fill" : "circle")
                                .foregroundStyle(server.enabled ? .green : .secondary)
                                .font(.caption)
                                .accessibilityLabel(server.enabled ? "Enabled" : "Disabled")

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
                                if !server.environment.isEmpty {
                                    Text("\(server.environment.count) settings")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
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
                            .accessibilityLabel("Edit \(server.name)")
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { indices in
                        for index in indices {
                            appState.deleteMCPServerConfig(appState.mcpServerConfigs[index])
                        }
                    }
                }
            }
        }
        .navigationTitle("Plugins")
        .toolbar {
            ToolbarItem {
                Button {
                    editingConfig = nil
                    showConnectionSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add Plugin")
                .accessibilityLabel("Add Plugin")
            }
        }
        .sheet(isPresented: $showConnectionSheet) {
            MCPConnectionSheet(existingConfig: editingConfig)
                .environment(appState)
        }
    }
}
