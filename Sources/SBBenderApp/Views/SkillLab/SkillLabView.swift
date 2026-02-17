import SwiftUI
import SBBender

struct SkillLabView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = SkillLabViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Mode picker
            Picker("Lab Mode", selection: $viewModel.labMode) {
                ForEach(SkillLabViewModel.LabMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            .frame(maxWidth: 300)

            Divider()

            if viewModel.labMode == .skill {
                skillLabContent
            } else {
                nativeToolLabContent
            }
        }
        .navigationTitle("Skill Lab")
        .task { await viewModel.loadInstalledSkills(appState: appState) }
    }

    // MARK: - Skill Lab (SKILL.md through agent)

    @ViewBuilder
    private var skillLabContent: some View {
        HSplitView {
            // Left: Configuration
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    skillPicker
                    modelSelector
                    toolSelector
                    skillInput
                    skillRunButton
                }
                .padding()
            }
            .frame(minWidth: 300, idealWidth: 350)

            // Right: Output
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    skillOutput
                    skillMetadata
                    skillMetrics
                }
                .padding()
            }
            .frame(minWidth: 300)
        }
    }

    @ViewBuilder
    private var skillPicker: some View {
        GroupBox("Skill") {
            if viewModel.installedSkills.isEmpty {
                VStack(spacing: 8) {
                    Text("No skills installed")
                        .foregroundStyle(.secondary)
                    Text("Install skills from the Marketplace tab")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                Picker("Select Skill", selection: $viewModel.selectedSkillID) {
                    Text("Choose...").tag(nil as String?)
                    ForEach(viewModel.installedSkills) { skill in
                        Text(skill.name).tag(skill.id as String?)
                    }
                }
                .onChange(of: viewModel.selectedSkillID) {
                    viewModel.onSkillSelected(appState: appState)
                }

                if let id = viewModel.selectedSkillID,
                   let skill = viewModel.installedSkills.first(where: { $0.id == id }) {
                    Text(skill.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var modelSelector: some View {
        GroupBox("Model") {
            Picker("Provider", selection: $viewModel.selectedProvider) {
                ForEach(ProviderType.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .onChange(of: viewModel.selectedProvider) {
                viewModel.selectedModelID = viewModel.selectedProvider.defaultModelID
            }

            TextField("Model ID", text: $viewModel.selectedModelID)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
        }
    }

    @ViewBuilder
    private var toolSelector: some View {
        GroupBox("Native Tools") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(AppState.skillCategories, id: \.name) { category in
                    let categorySkills = appState.nativeSkills.filter { category.skillIDs.contains($0.id) }
                    if !categorySkills.isEmpty {
                        Text(category.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)

                        ForEach(categorySkills, id: \.id) { tool in
                            Toggle(tool.name, isOn: Binding(
                                get: { viewModel.enabledToolIDs.contains(tool.id) },
                                set: { enabled in
                                    if enabled {
                                        viewModel.enabledToolIDs.insert(tool.id)
                                    } else {
                                        viewModel.enabledToolIDs.remove(tool.id)
                                    }
                                }
                            ))
                            .toggleStyle(.checkbox)
                            .font(.callout)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var skillInput: some View {
        GroupBox("Input") {
            TextEditor(text: $viewModel.inputText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 80)
        }
    }

    @ViewBuilder
    private var skillRunButton: some View {
        Button {
            Task { await viewModel.runSkill(appState: appState) }
        } label: {
            HStack {
                if viewModel.isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
                Text("Run Skill")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(
            viewModel.selectedSkillID == nil ||
            viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            viewModel.isRunning
        )

        if let error = viewModel.errorMessage {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var skillOutput: some View {
        GroupBox("Agent Response") {
            ScrollView {
                Text(viewModel.agentResponse.isEmpty ? "Run a skill to see results..." : viewModel.agentResponse)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 200)
        }
    }

    @ViewBuilder
    private var skillMetadata: some View {
        if let id = viewModel.selectedSkillID,
           let skill = viewModel.installedSkills.first(where: { $0.id == id }) {
            GroupBox("Skill Info") {
                LabeledContent("Name", value: skill.name)
                LabeledContent("Source", value: skill.source)
                if !skill.scripts.isEmpty {
                    LabeledContent("Scripts", value: skill.scripts.map(\.name).joined(separator: ", "))
                }
                if let tools = skill.allowedTools, !tools.isEmpty {
                    LabeledContent("Allowed Tools", value: tools.joined(separator: ", "))
                }
            }
        }
    }

    @ViewBuilder
    private var skillMetrics: some View {
        if viewModel.responseLatency > 0 {
            GroupBox("Metrics") {
                LabeledContent("Latency", value: String(format: "%.2fs", viewModel.responseLatency))
                if viewModel.responseTokens > 0 {
                    LabeledContent("Output Tokens", value: "\(viewModel.responseTokens)")
                }
            }
        }
    }

    // MARK: - Native Tool Lab (direct execution)

    @ViewBuilder
    private var nativeToolLabContent: some View {
        HSplitView {
            // Left: Input
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Native Tool") {
                    Picker("Select Tool", selection: $viewModel.selectedNativeToolID) {
                        Text("Choose...").tag(nil as String?)
                        ForEach(appState.nativeSkills, id: \.id) { skill in
                            Text(skill.name).tag(skill.id as String?)
                        }
                    }

                    if let id = viewModel.selectedNativeToolID,
                       let skill = appState.nativeSkills.first(where: { $0.id == id }) {
                        Text(skill.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("Input") {
                    TextEditor(text: $viewModel.nativeToolInput)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 100)
                }

                // Extra parameters for specific tools
                if viewModel.selectedNativeToolID == "embedding-distance" {
                    GroupBox("Compare To") {
                        TextField("Second text for comparison", text: Binding(
                            get: { viewModel.nativeToolParameters["compareTo"] ?? "" },
                            set: { viewModel.nativeToolParameters["compareTo"] = $0 }
                        ))
                    }
                }

                if viewModel.selectedNativeToolID == "tokenization" {
                    GroupBox("Unit") {
                        Picker("Tokenization Unit", selection: Binding(
                            get: { viewModel.nativeToolParameters["unit"] ?? "word" },
                            set: { viewModel.nativeToolParameters["unit"] = $0 }
                        )) {
                            Text("Word").tag("word")
                            Text("Sentence").tag("sentence")
                            Text("Paragraph").tag("paragraph")
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Button {
                    Task { await viewModel.runNativeTool(nativeTools: appState.nativeSkills) }
                } label: {
                    HStack {
                        if viewModel.isRunning {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Run Tool")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.selectedNativeToolID == nil || viewModel.nativeToolInput.isEmpty || viewModel.isRunning)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Spacer()
            }
            .padding()
            .frame(minWidth: 300)

            // Right: Output
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Output") {
                    ScrollView {
                        Text(viewModel.nativeToolOutput.isEmpty ? "Run a tool to see results..." : viewModel.nativeToolOutput)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 100)
                }

                if !viewModel.nativeToolStructuredData.isEmpty {
                    GroupBox("Structured Data") {
                        ForEach(viewModel.nativeToolStructuredData.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            LabeledContent(key, value: value)
                        }
                    }
                }

                if viewModel.nativeToolLatency > 0 {
                    GroupBox("Metrics") {
                        LabeledContent("Confidence", value: String(format: "%.2f", viewModel.nativeToolConfidence))
                        LabeledContent("Latency", value: String(format: "%.1fms", viewModel.nativeToolLatency * 1000))
                    }
                }

                Spacer()
            }
            .padding()
            .frame(minWidth: 300)
        }
    }
}
