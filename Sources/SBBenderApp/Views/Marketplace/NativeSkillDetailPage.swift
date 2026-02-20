import SwiftUI
import SBBender

struct NativeSkillDetailPage: View {
    let skillID: String
    @Environment(AppState.self) private var appState
    @State private var isAvailable: Bool?
    @State private var testOutput: String?
    @State private var isRunning = false

    private var skill: (any NativeTool)? {
        appState.nativeSkills.first(where: { $0.id == skillID })
    }

    private var category: (name: String, icon: String, skillIDs: [String])? {
        AppState.skillCategories.first { $0.skillIDs.contains(skillID) }
    }

    var body: some View {
        Group {
            if let skill {
                skillContent(skill)
            } else {
                ContentUnavailableView(
                    "Capability Not Found",
                    systemImage: "questionmark.circle",
                    description: Text("This capability could not be loaded.")
                )
            }
        }
        .navigationTitle(skill?.name ?? "Capability")
    }

    private func skillContent(_ skill: any NativeTool) -> some View {
        VStack(spacing: 0) {
            // Header
            skillHeader(skill)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Overview
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(skill.description)
                                .font(.body)

                            Divider()

                            if appState.showAdvancedFeatures {
                                LabeledContent("Skill ID") {
                                    Text(skill.id)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                            }
                            if let category {
                                LabeledContent("Category") {
                                    Label(category.name, systemImage: category.icon)
                                        .font(.caption)
                                }
                            }
                            LabeledContent("Availability") {
                                if let isAvailable {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(isAvailable ? .green : .red)
                                            .frame(width: 8, height: 8)
                                        Text(isAvailable ? "Available on this device" : "Not available")
                                            .font(.caption)
                                    }
                                } else {
                                    ProgressView()
                                        .controlSize(.mini)
                                }
                            }
                            LabeledContent("Type") {
                                Text("Native Apple Framework")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } label: {
                        Label("Overview", systemImage: "info.circle")
                    }

                    // Tool schema (advanced only)
                    if appState.showAdvancedFeatures {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Technical details for how the AI interacts with this capability:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                let schema = skill.toolParameters
                                if let data = try? JSONEncoder().encode(schema),
                                   let json = String(data: data, encoding: .utf8) {
                                    Text(prettyJSON(json))
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color(.textBackgroundColor).opacity(0.5))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        } label: {
                            Label("Technical Details", systemImage: "curlybraces")
                        }
                    }

                    // Quick test
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Send a test input to verify the skill works on this device.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack {
                                Button {
                                    Task { await runTest(skill) }
                                } label: {
                                    if isRunning {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Label("Run Test", systemImage: "play.fill")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(isRunning || isAvailable == false)
                            }

                            if let output = testOutput {
                                Text(output)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.textBackgroundColor).opacity(0.5))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    } label: {
                        Label("Quick Test", systemImage: "play.circle")
                    }

                    // Usage in agents
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            let usingAgents = appState.agents.filter { agent in
                                agent.enabledSkillIDs.isEmpty || agent.enabledSkillIDs.contains(skillID)
                            }
                            if usingAgents.isEmpty {
                                Text("No assistants are using this capability yet.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("\(usingAgents.count) assistant\(usingAgents.count == 1 ? "" : "s") using this:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ForEach(usingAgents) { agent in
                                    HStack(spacing: 8) {
                                        Text(agent.emoji)
                                            .font(.caption)
                                        Text(agent.name)
                                            .font(.caption.weight(.medium))
                                        Spacer()
                                        Button("Open Chat") {
                                            appState.selectedSidebarItem = .agentChat(agent.id)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.mini)
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Used By", systemImage: "person.2")
                    }
                }
                .padding(20)
            }

            Divider()

            // Bottom bar
            HStack {
                Button {
                    appState.selectedSidebarItem = .marketplace
                } label: {
                    Label("Back to Capability Store", systemImage: "chevron.left")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .task {
            if let s = self.skill {
                isAvailable = await s.isAvailable
            }
        }
    }

    // MARK: - Header

    private func skillHeader(_ skill: any NativeTool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.green.gradient.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: category?.icon ?? "cpu")
                    .font(.title3)
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(skill.name)
                    .font(.headline)
                HStack(spacing: 8) {
                    if let category {
                        Text(category.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Built-in")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.green.opacity(0.15)))
                        .foregroundStyle(.green)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: - Actions

    private func runTest(_ skill: any NativeTool) async {
        isRunning = true
        testOutput = nil
        do {
            let result = try await skill.execute(input: .text("Hello, this is a test input."))
            let confidencePercent = Int(result.confidence * 100)
            testOutput = "Result: \(result.output)\nAccuracy: \(confidencePercent)%\nSpeed: \(String(format: "%.0f", result.latency * 1000))ms"
        } catch {
            testOutput = "Error: \(error.localizedDescription)"
        }
        isRunning = false
    }

    private func prettyJSON(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: pretty, encoding: .utf8) else {
            return json
        }
        return result
    }
}
