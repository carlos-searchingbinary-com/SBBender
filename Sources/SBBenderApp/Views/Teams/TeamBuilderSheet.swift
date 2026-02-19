import SwiftUI

struct TeamBuilderSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let config: TeamConfig?

    @State private var name: String = "New Team"
    @State private var emoji: String = "👥"
    @State private var gradientHex: [String] = ["#7209B7", "#B5179E"]
    @State private var mode: String = "sequential"
    @State private var memberIDs: [String] = []
    @State private var leaderID: String?

    var isEditing: Bool { config != nil }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                AgentAvatar(emoji: emoji, gradientHex: gradientHex, size: 56)
                VStack(alignment: .leading) {
                    Text(name.isEmpty ? "Untitled" : name)
                        .font(.title2.bold())
                    Text(isEditing ? "Edit Team" : "New Team")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Save" : "Create") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || memberIDs.isEmpty)
            }
            .padding()

            Divider()

            Form {
                Section("Identity") {
                    TextField("Name", text: $name)
                    EmojiPickerView(selected: $emoji)
                    GradientPickerView(selectedHex: $gradientHex)
                }

                Section("How They Work Together") {
                    Picker("Mode", selection: $mode) {
                        Text("One at a time").tag("sequential")
                        Text("All at once").tag("parallel")
                        Text("Self-directed").tag("autonomous")
                    }
                    .pickerStyle(.segmented)

                    switch mode {
                    case "sequential":
                        Text("Assistants work one after another, passing context forward.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case "parallel":
                        Text("All assistants work simultaneously on the same input.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case "autonomous":
                        Text("A leader assistant decides which members to delegate to.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    default:
                        EmptyView()
                    }
                }

                Section("Members (\(memberIDs.count))") {
                    ForEach(appState.agents) { agent in
                        Toggle(isOn: Binding(
                            get: { memberIDs.contains(agent.id) },
                            set: { on in
                                if on { memberIDs.append(agent.id) }
                                else { memberIDs.removeAll { $0 == agent.id } }
                            }
                        )) {
                            HStack(spacing: 8) {
                                AgentAvatar(emoji: agent.emoji, gradientHex: agent.gradientHex, size: 28)
                                VStack(alignment: .leading) {
                                    Text(agent.name)
                                    Text(agent.modelID.components(separatedBy: "/").last ?? agent.modelID)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if appState.agents.isEmpty {
                        Text("No assistants created yet. Create an assistant first.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if mode == "autonomous" {
                    Section("Leader") {
                        Picker("Leader", selection: Binding(
                            get: { leaderID ?? "" },
                            set: { leaderID = $0.isEmpty ? nil : $0 }
                        )) {
                            Text("Auto-select").tag("")
                            ForEach(memberIDs, id: \.self) { memberID in
                                if let agent = appState.agentConfig(for: memberID) {
                                    Text(agent.name).tag(memberID)
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 550, minHeight: 500)
        .onAppear { loadConfig() }
    }

    private func loadConfig() {
        guard let c = config else { return }
        name = c.name
        emoji = c.emoji
        gradientHex = c.gradientHex
        mode = c.mode
        memberIDs = c.memberIDs
        leaderID = c.leaderID
    }

    private func save() {
        var team = config ?? TeamConfig()
        team.name = name.trimmingCharacters(in: .whitespaces)
        team.emoji = emoji
        team.gradientHex = gradientHex
        team.mode = mode
        team.memberIDs = memberIDs
        team.leaderID = leaderID
        team.updatedAt = Date()

        appState.saveTeam(team)
        dismiss()
    }
}
