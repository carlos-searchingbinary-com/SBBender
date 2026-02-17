import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var selectedTab: SettingsTab = .models

    enum SettingsTab: String, CaseIterable {
        case models = "Models"
        case mcpServers = "MCP Servers"
        case general = "General"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Settings", selection: $selectedTab) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            switch selectedTab {
            case .models:
                ModelsSettingsView()
                    .environment(appState)
            case .mcpServers:
                MCPSettingsView()
                    .environment(appState)
            case .general:
                GeneralSettingsContent()
                    .environment(appState)
            }
        }
        .navigationTitle("Settings")
    }
}

// MARK: - General Settings

private struct GeneralSettingsContent: View {
    @Environment(AppState.self) private var appState

    @State private var showClearConfirm = false

    var body: some View {
        Form {
            Section("Storage") {
                LabeledContent("Agents", value: "\(appState.agents.count)")
                LabeledContent("Teams", value: "\(appState.teams.count)")
                LabeledContent("Custom Tools", value: "\(appState.toolConfigs.count)")
                LabeledContent("MCP Servers", value: "\(appState.mcpServerConfigs.count)")

                Button("Clear All Data", role: .destructive) {
                    showClearConfirm = true
                }
                .confirmationDialog(
                    "Clear All Data?",
                    isPresented: $showClearConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Delete Everything", role: .destructive) {
                        clearAllData()
                    }
                } message: {
                    Text("This will permanently delete all agents, teams, and chat history.")
                }
            }

            Section("About") {
                LabeledContent("App", value: "SBBender")
                LabeledContent("Runtime", value: "Swift 6.2")
                LabeledContent("Platform", value: "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
                LabeledContent("Hardware", value: appState.hardwareInfo.chipName)
                LabeledContent("Tier", value: appState.hardwareInfo.modelTier.displayName)
            }
        }
        .formStyle(.grouped)
    }

    private func clearAllData() {
        Task {
            try? await appState.persistence?.clearAll()
            appState.agents.removeAll()
            appState.teams.removeAll()
            appState.toolConfigs.removeAll()
            appState.mcpServerConfigs.removeAll()
        }
    }
}
