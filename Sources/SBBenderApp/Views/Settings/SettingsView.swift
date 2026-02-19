import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var selectedTab: SettingsTab = .models

    enum SettingsTab: String, CaseIterable {
        case models = "Models"
        case mcpServers = "Plugins"
        case general = "General"
    }

    private var visibleTabs: [SettingsTab] {
        if appState.showAdvancedFeatures {
            return SettingsTab.allCases
        } else {
            return SettingsTab.allCases.filter { $0 != .mcpServers }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Settings", selection: $selectedTab) {
                ForEach(visibleTabs, id: \.self) { tab in
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
        .onChange(of: appState.showAdvancedFeatures) { _, newValue in
            if !newValue && selectedTab == .mcpServers {
                selectedTab = .models
            }
        }
    }
}

// MARK: - General Settings

private struct GeneralSettingsContent: View {
    @Environment(AppState.self) private var appState

    @State private var showClearConfirm = false

    var body: some View {
        @Bindable var state = appState
        Form {
            Section("Interface") {
                Toggle("Advanced Features", isOn: $state.showAdvancedFeatures)
                Text("Shows extra options like custom tools, plugin management, and technical settings. Most users don't need this.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Section("Data") {
                LabeledContent("Assistants", value: "\(appState.agents.count)")
                LabeledContent("Teams", value: "\(appState.teams.count)")
                if appState.showAdvancedFeatures {
                    LabeledContent("Custom Actions", value: "\(appState.toolConfigs.count)")
                    LabeledContent("Plugins", value: "\(appState.mcpServerConfigs.count)")
                }

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
                LabeledContent("Platform", value: "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
                LabeledContent("Hardware", value: "\(appState.hardwareInfo.chipName) — \(appState.hardwareInfo.totalRAMGB) GB")
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
