import SwiftUI

struct ToolManagerView: View {
    @Environment(AppState.self) private var appState
    @State private var showToolBuilder = false
    @State private var editingTool: ToolConfig?

    var body: some View {
        VStack(spacing: 0) {
            if appState.toolConfigs.isEmpty {
                ContentUnavailableView(
                    "No Custom Actions",
                    systemImage: "wrench.and.screwdriver",
                    description: Text("Create custom actions that your assistants can perform — like running shell commands, calling APIs, or executing AppleScript.")
                )
            } else {
                List {
                    ForEach(appState.toolConfigs) { tool in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(tool.name)
                                        .font(.body.bold())
                                    Text(tool.executionType)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(.orange.opacity(0.15)))
                                        .foregroundStyle(.orange)
                                }
                                Text(tool.toolDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !tool.parameters.isEmpty {
                                    Text("Inputs: \(tool.parameters.map(\.name).joined(separator: ", "))")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            if tool.requiresConfirmation {
                                Image(systemName: "exclamationmark.shield")
                                    .font(.caption)
                                    .foregroundStyle(.yellow)
                                    .help("Requires confirmation")
                            }
                            Button {
                                editingTool = tool
                                showToolBuilder = true
                            } label: {
                                Image(systemName: "pencil.circle")
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { indices in
                        for index in indices {
                            appState.deleteToolConfig(appState.toolConfigs[index])
                        }
                    }
                }
            }
        }
        .navigationTitle("Custom Actions")
        .toolbar {
            ToolbarItem {
                Button {
                    editingTool = nil
                    showToolBuilder = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("New Action")
                .accessibilityLabel("Add Custom Action")
            }
        }
        .sheet(isPresented: $showToolBuilder) {
            ToolBuilderSheet(existingConfig: editingTool, agentID: nil)
                .environment(appState)
        }
    }
}
