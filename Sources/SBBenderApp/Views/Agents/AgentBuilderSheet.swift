import SwiftUI
import SBBender

// MARK: - Builder Step Navigation

private enum BuilderStep: Int, CaseIterable {
    case persona = 0
    case capabilities
    case behavior

    var title: String {
        switch self {
        case .persona: "Personality"
        case .capabilities: "Capabilities"
        case .behavior: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .persona: "person.crop.circle"
        case .capabilities: "puzzlepiece.extension"
        case .behavior: "slider.horizontal.3"
        }
    }
}

// MARK: - Main Builder

struct AgentBuilderSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let config: AgentConfig?
    var template: AgentTemplate? = nil

    // Identity
    @State private var name: String = "New AI Assistant"
    @State private var emoji: String = "🤖"
    @State private var gradientHex: [String] = ["#0077B6", "#00B4D8"]
    @State private var instructions: String = "You are a helpful assistant."
    // Model & Generation
    @State private var providerType: ProviderType = .mlx
    @State private var modelID: String = "mlx-community/Qwen3-4B-4bit"
    @State private var temperature: Float = 0.7
    @State private var topP: Float = 0.9
    @State private var maxTokens: Int = 2048
    @State private var repetitionPenalty: Float = 1.0
    @State private var enableThinking: Bool = false
    @State private var markdownOutput: Bool = true
    @State private var addDateToSystemPrompt: Bool = true
    // SKILL.md instruction skills
    @State private var attachedSkillIDs: Set<String> = []
    @State private var installedSkills: [SBBender.Skill] = []
    // Features
    @State private var knowledgeEnabled: Bool = false
    @State private var knowledgeChunkingStrategy: String = "paragraph"
    @State private var knowledgeHybridWeight: Float = 0.7
    @State private var learningEnabled: Bool = false
    @State private var learningMode: String = "always"
    @State private var enabledNativeToolIDs: Set<String> = []
    @State private var nativeToolAvailability: [(skill: any NativeTool, available: Bool)] = []
    @State private var customToolIDs: Set<String> = []
    @State private var mcpServerIDs: Set<String> = []
    @State private var systemPromptFile: String? = nil
    // Advanced
    @State private var toolCallLimit: Int = 25
    @State private var maxIterations: Int = 10
    @State private var maxHistoryMessages: Int? = nil
    // Navigation
    @State private var currentStep: BuilderStep = .persona
    @State private var showAdvanced = false
    // Sheets
    @State private var showKnowledgeManager = false
    @State private var showToolBuilder = false
    @State private var showMCPConnection = false
    @State private var showWizard = false
    @State private var editingToolConfig: ToolConfig?
    @State private var editingMCPConfig: MCPServerConfig?
    // Instructions preview
    @State private var showInstructionsPreview = false
    // Model search
    @State private var mlxSearchQuery: String = ""

    var isEditing: Bool { config != nil && template == nil }

    var body: some View {
        VStack(spacing: 0) {
            builderHeader
            Divider()
            if isEditing {
                // Edit mode: single scrollable page — no steps
                editContent
            } else {
                // New agent: step wizard
                stepIndicator
                Divider()
                stepContent
            }
            Divider()
            builderFooter
        }
        .frame(width: 680, height: 640)
        .onAppear {
            loadConfig()
            if let template { applyTemplate(template) }
        }
        .task {
            await loadInstalledSkills()
            nativeToolAvailability = await appState.availableSkills()
            // Default: all available tools enabled if config has none set
            if enabledNativeToolIDs.isEmpty {
                enabledNativeToolIDs = Set(nativeToolAvailability.filter(\.available).map(\.skill.id))
            }
        }
        .onChange(of: providerType) { _, newValue in
            Task {
                switch newValue {
                case .mlx:
                    appState.modelRegistry.loadMLXLocal()
                case .ollama:
                    await appState.modelRegistry.loadOllamaModels()
                case .anthropic:
                    let key = KeychainService.anthropicKey
                    if !key.isEmpty { await appState.modelRegistry.loadAnthropicModels(apiKey: key) }
                case .openai:
                    let key = KeychainService.openaiKey
                    if !key.isEmpty { await appState.modelRegistry.loadOpenAIModels(apiKey: key) }
                case .groq:
                    let key = KeychainService.groqKey
                    if !key.isEmpty { await appState.modelRegistry.loadGroqModels(apiKey: key) }
                case .deepinfra:
                    let key = KeychainService.deepinfraKey
                    if !key.isEmpty { await appState.modelRegistry.loadDeepInfraModels(apiKey: key) }
                case .foundation:
                    break
                }
            }
        }
        .sheet(isPresented: $showKnowledgeManager) {
            if let c = config {
                KnowledgeManagerView(agentConfig: c)
                    .environment(appState)
            }
        }
        .sheet(isPresented: $showToolBuilder) {
            ToolBuilderSheet(existingConfig: editingToolConfig, agentID: config?.id)
                .environment(appState)
                .onDisappear { refreshToolIDs() }
        }
        .sheet(isPresented: $showMCPConnection) {
            MCPConnectionSheet(existingConfig: editingMCPConfig)
                .environment(appState)
                .onDisappear { refreshMCPIDs() }
        }
        .sheet(isPresented: $showWizard) {
            AgentWizardSheet { generatedConfig in
                applyGeneratedConfig(generatedConfig)
            }
            .environment(appState)
        }
    }

    // MARK: - Header (Live Preview)

    private var builderHeader: some View {
        HStack(spacing: 16) {
            // Live avatar
            AgentAvatar(emoji: emoji, gradientHex: gradientHex, size: 64)
                .shadow(color: Color(hex: gradientHex.first ?? "#0077B6").opacity(0.4), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(name.isEmpty ? "Untitled Assistant" : name)
                    .font(.title2.bold())
                // Capability summary
                HStack(spacing: 8) {
                    if !enabledNativeToolIDs.isEmpty {
                        Label("\(enabledNativeToolIDs.count) capabilities", systemImage: "wrench.fill")
                    }
                    if !attachedSkillIDs.isEmpty {
                        Label("\(attachedSkillIDs.count) behaviors", systemImage: "doc.text")
                    }
                    if knowledgeEnabled {
                        Label("Knowledge", systemImage: "book.closed.fill")
                    }
                    if learningEnabled {
                        Label("Memory", systemImage: "brain")
                    }
                    if !mcpServerIDs.isEmpty {
                        Label("\(mcpServerIDs.count) plugins", systemImage: "server.rack")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // AI Wizard button
            if !isEditing {
                Button {
                    showWizard = true
                } label: {
                    Label("AI Setup", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Describe what you want and let AI configure the assistant")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(BuilderStep.allCases, id: \.rawValue) { step in
                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        currentStep = step
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: step.icon)
                            .font(.system(size: 18))
                        Text(step.title)
                            .font(.caption.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(currentStep == step ? Color.accentColor.opacity(0.1) : .clear)
                    .foregroundStyle(currentStep == step ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                if step.rawValue < BuilderStep.allCases.count - 1 {
                    Divider().frame(height: 30)
                }
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                switch currentStep {
                case .persona:
                    personaStep
                case .capabilities:
                    capabilitiesStep
                case .behavior:
                    behaviorStep
                }
            }
            .padding(24)
        }
    }

    // MARK: - Edit Mode (single scrollable page)

    private var editContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Name — top priority
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(.subheadline.weight(.medium))
                    TextField("Give your assistant a name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)
                }

                // Instructions — most important thing
                instructionsSection

                Divider()

                // Native tools
                nativeToolsPickerSection

                Divider()

                // SKILL.md instruction skills
                skillsPickerSection

                // Features
                VStack(alignment: .leading, spacing: 10) {
                    FeatureToggleRow(
                        icon: "book.closed.fill", color: .blue,
                        title: "Knowledge Base",
                        subtitle: "Feed documents and files for the assistant to reference",
                        isOn: $knowledgeEnabled
                    )
                    if knowledgeEnabled && config?.id != nil {
                        Button {
                            showKnowledgeManager = true
                        } label: {
                            Label("Manage Documents", systemImage: "doc.on.doc")
                        }
                        .font(.caption)
                        .padding(.leading, 44)
                    }
                    FeatureToggleRow(
                        icon: "brain", color: .purple,
                        title: "Memory",
                        subtitle: "Remember preferences and context across conversations",
                        isOn: $learningEnabled
                    )
                    FeatureToggleRow(
                        icon: "lightbulb.fill", color: .yellow,
                        title: "Deep Thinking",
                        subtitle: "Take extra time to reason through complex problems",
                        isOn: $enableThinking
                    )
                }

                Divider()

                // Model + Personality
                modelPickerSection

                // Creativity slider
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Creativity")
                            .font(.subheadline)
                        Spacer()
                        Text(creativityLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $temperature, in: 0.0...1.5, step: 0.1)
                    HStack {
                        Text("Precise").font(.caption2).foregroundStyle(.tertiary)
                        Spacer()
                        Text("Creative").font(.caption2).foregroundStyle(.tertiary)
                    }
                }

                // Response length
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Response Length")
                            .font(.subheadline)
                        Spacer()
                        Text(responseLengthLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { Float(maxTokens) },
                        set: { maxTokens = Int($0) }
                    ), in: 256...8192, step: 256)
                    HStack {
                        Text("Short").font(.caption2).foregroundStyle(.tertiary)
                        Spacer()
                        Text("Detailed").font(.caption2).foregroundStyle(.tertiary)
                    }
                }

                Divider()

                // Connections
                connectionsSection

                Divider()

                // Appearance (bottom — it's the fluff)
                HStack(alignment: .top, spacing: 32) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Icon")
                            .font(.subheadline.weight(.medium))
                        EmojiPickerView(selected: $emoji)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Color")
                            .font(.subheadline.weight(.medium))
                        GradientPickerView(selectedHex: $gradientHex)
                    }
                }

                // Advanced (only for power users)
                if appState.showAdvancedFeatures {
                    DisclosureGroup("Advanced Settings", isExpanded: $showAdvanced) {
                        advancedSettingsContent
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
    }

    // MARK: - Step 1: Persona

    private var personaStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Name — first thing you see
            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.subheadline.weight(.medium))
                TextField("Give your assistant a name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
            }

            // Instructions — the most important field, right after name
            instructionsSection

            Divider()

            // Templates — helpful but secondary
            VStack(alignment: .leading, spacing: 10) {
                Text("Or start from a template")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 10)], spacing: 10) {
                    ForEach(appState.agentTemplates) { tmpl in
                        TemplateCard(template: tmpl, isSelected: name == tmpl.name && emoji == tmpl.emoji) {
                            applyTemplate(tmpl)
                        }
                    }
                }
            }

            Divider()

            // Appearance — the fluff, at the bottom
            HStack(alignment: .top, spacing: 32) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Icon")
                        .font(.subheadline.weight(.medium))
                    EmojiPickerView(selected: $emoji)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Color")
                        .font(.subheadline.weight(.medium))
                    GradientPickerView(selectedHex: $gradientHex)
                }
            }
        }
    }

    // MARK: - Shared Sections

    private var modelPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI Model")
                .font(.subheadline.weight(.medium))

            // Provider buttons
            HStack(spacing: 8) {
                ForEach(ProviderType.allCases) { pt in
                    Button {
                        providerType = pt
                        modelID = pt.defaultModelID
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: pt.icon)
                                .font(.system(size: 18))
                            Text(pt.displayName)
                                .font(.caption2.weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(providerType == pt ? Color.accentColor.opacity(0.15) : .clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(providerType == pt ? Color.accentColor : .clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Dynamic model picker per provider
            switch providerType {
            case .mlx:
                mlxModelPicker
            case .ollama:
                ollamaModelPicker
            case .anthropic:
                apiModelPicker(models: appState.modelRegistry.anthropicModels, placeholder: "claude-sonnet-4-5-20250929")
            case .openai:
                apiModelPicker(models: appState.modelRegistry.openaiModels, placeholder: "gpt-4.1")
            case .groq:
                apiModelPicker(models: appState.modelRegistry.groqModels, placeholder: "llama-3.3-70b-versatile")
            case .deepinfra:
                apiModelPicker(models: appState.modelRegistry.deepinfraModels, placeholder: "meta-llama/Llama-4-Scout-17B-16E-Instruct")
            case .foundation:
                VStack(alignment: .leading, spacing: 4) {
                    Text("Uses Apple Intelligence (macOS 26+)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label("Apple Intelligence does not support tool calling. Agent tools will not work.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MLX: local models + HuggingFace search
    @ViewBuilder
    private var mlxModelPicker: some View {
        MLXModelPickerView(
            modelID: $modelID,
            searchQuery: $mlxSearchQuery,
            registry: appState.modelRegistry
        )
    }

    // Ollama: installed models from /api/tags
    @ViewBuilder
    private var ollamaModelPicker: some View {
        OllamaModelPickerView(
            modelID: $modelID,
            registry: appState.modelRegistry
        )
    }

    // OpenAI / Anthropic: API-fetched model list + manual entry
    private func apiModelPicker(models: [String], placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !models.isEmpty {
                Picker("Model", selection: $modelID) {
                    ForEach(models, id: \.self) { m in
                        Text(m).tag(m)
                    }
                }
                .labelsHidden()
            } else {
                TextField(placeholder, text: $modelID)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                Text("Add your access key in Settings to load available models")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Instructions")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let path = systemPromptFile, !path.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.caption2)
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.caption2)
                        Button("Clear") { systemPromptFile = nil }
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
                Button {
                    showInstructionsPreview.toggle()
                } label: {
                    Label(
                        showInstructionsPreview ? "Edit" : "Preview",
                        systemImage: showInstructionsPreview ? "pencil" : "eye"
                    )
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                Button("Import File") { loadSystemPromptFile() }
                    .font(.caption)
            }
            Text("Tell the assistant who it is and how it should behave — supports Markdown")
                .font(.caption)
                .foregroundStyle(.tertiary)

            if showInstructionsPreview {
                ScrollView {
                    MarkdownView(content: instructions)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(minHeight: 100, maxHeight: 160)
                .background(RoundedRectangle(cornerRadius: 8).fill(.background))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            } else {
                TextEditor(text: $instructions)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 100, maxHeight: 160)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.background))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            }
        }
    }

    @ViewBuilder
    private var connectionsSection: some View {
        if appState.showAdvancedFeatures {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connections")
                .font(.subheadline.weight(.medium))

            // Custom tools summary
            let agentTools = appState.toolConfigs.filter { customToolIDs.contains($0.id) || $0.agentID == config?.id }
            HStack {
                Image(systemName: "wrench.fill")
                    .foregroundStyle(.green)
                    .frame(width: 28)
                VStack(alignment: .leading) {
                    Text("Custom Tools")
                        .font(.subheadline)
                    Text(agentTools.isEmpty ? "No custom tools" : "\(agentTools.count) tool\(agentTools.count == 1 ? "" : "s") attached")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    editingToolConfig = nil
                    showToolBuilder = true
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.04)))

            if !agentTools.isEmpty {
                ForEach(agentTools) { tool in
                    HStack {
                        Text(tool.name)
                            .font(.caption.weight(.medium))
                        Text(tool.toolDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            editingToolConfig = tool
                            showToolBuilder = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.leading, 44)
                }
            }

            // MCP summary
            let serverConfigs = appState.mcpServerConfigs.filter { mcpServerIDs.contains($0.id) }
            HStack {
                Image(systemName: "server.rack")
                    .foregroundStyle(.orange)
                    .frame(width: 28)
                VStack(alignment: .leading) {
                    Text("MCP Servers")
                        .font(.subheadline)
                    Text(serverConfigs.isEmpty ? "No servers connected" : "\(serverConfigs.count) server\(serverConfigs.count == 1 ? "" : "s") connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                let unattached = appState.mcpServerConfigs.filter { !mcpServerIDs.contains($0.id) }
                if !unattached.isEmpty {
                    Menu {
                        ForEach(unattached) { server in
                            Button(server.name) { mcpServerIDs.insert(server.id) }
                        }
                    } label: {
                        Image(systemName: "link")
                    }
                    .menuStyle(.borderlessButton)
                }
                Button {
                    editingMCPConfig = nil
                    showMCPConnection = true
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.04)))

            ForEach(serverConfigs) { server in
                HStack {
                    Circle()
                        .fill(server.enabled ? .green : .gray)
                        .frame(width: 6, height: 6)
                    Text(server.name)
                        .font(.caption.weight(.medium))
                    Spacer()
                    Button {
                        editingMCPConfig = server
                        showMCPConnection = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 44)
            }
        }
        } // if showAdvancedFeatures
    }

    private var advancedSettingsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Focus")
                    .font(.caption)
                Spacer()
                Text(String(format: "%.2f", topP))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $topP, in: 0.0...1.0, step: 0.05)

            HStack {
                Text("Variety")
                    .font(.caption)
                Spacer()
                Text(String(format: "%.2f", repetitionPenalty))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $repetitionPenalty, in: 1.0...2.0, step: 0.05)

            Stepper("Actions per step: \(toolCallLimit)", value: $toolCallLimit, in: 1...100)
                .font(.caption)
            Stepper("Max steps: \(maxIterations)", value: $maxIterations, in: 1...50)
                .font(.caption)

            Toggle("Markdown output", isOn: $markdownOutput)
                .font(.caption)
            Toggle("Include today's date", isOn: $addDateToSystemPrompt)
                .font(.caption)

            Toggle("Limit conversation history", isOn: Binding(
                get: { maxHistoryMessages != nil },
                set: { on in maxHistoryMessages = on ? 50 : nil }
            ))
            .font(.caption)

            if maxHistoryMessages != nil {
                Stepper(
                    "Keep last \(maxHistoryMessages ?? 50) messages",
                    value: Binding(
                        get: { maxHistoryMessages ?? 50 },
                        set: { maxHistoryMessages = $0 }
                    ),
                    in: 10...500,
                    step: 10
                )
                .font(.caption)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Step 2: Capabilities

    private var capabilitiesStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Native tools grid
            nativeToolsPickerSection

            Divider()

            // SKILL.md instruction skills
            skillsPickerSection

            Divider()

            // Feature toggles
            VStack(alignment: .leading, spacing: 10) {
                Text("Features")
                    .font(.subheadline.weight(.medium))

                FeatureToggleRow(
                    icon: "book.closed.fill", color: .blue,
                    title: "Knowledge Base",
                    subtitle: "Feed documents and files for the assistant to reference",
                    isOn: $knowledgeEnabled
                )

                if knowledgeEnabled && config?.id != nil {
                    Button {
                        showKnowledgeManager = true
                    } label: {
                        Label("Manage Documents", systemImage: "doc.on.doc")
                    }
                    .font(.caption)
                    .padding(.leading, 44)
                }

                FeatureToggleRow(
                    icon: "brain", color: .purple,
                    title: "Memory",
                    subtitle: "Remember preferences and context across conversations",
                    isOn: $learningEnabled
                )
            }

            Divider()

            // Connections (shared section)
            connectionsSection
        }
    }

    // MARK: - Step 3: Behavior

    private var behaviorStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            modelPickerSection

            Divider()

            // Personality (human terms)
            VStack(alignment: .leading, spacing: 14) {
                Text("Personality")
                    .font(.subheadline.weight(.medium))

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Creativity")
                            .font(.subheadline)
                        Spacer()
                        Text(creativityLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $temperature, in: 0.0...1.5, step: 0.1)
                    HStack {
                        Text("Precise").font(.caption2).foregroundStyle(.tertiary)
                        Spacer()
                        Text("Creative").font(.caption2).foregroundStyle(.tertiary)
                    }
                }

                FeatureToggleRow(
                    icon: "lightbulb.fill", color: .yellow,
                    title: "Deep Thinking",
                    subtitle: "Take extra time to reason through complex problems",
                    isOn: $enableThinking
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Response Length")
                            .font(.subheadline)
                        Spacer()
                        Text(responseLengthLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { Float(maxTokens) },
                        set: { maxTokens = Int($0) }
                    ), in: 256...8192, step: 256)
                    HStack {
                        Text("Short").font(.caption2).foregroundStyle(.tertiary)
                        Spacer()
                        Text("Detailed").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }

            Divider()

            // Advanced (collapsed by default, only for power users)
            if appState.showAdvancedFeatures {
                DisclosureGroup("Advanced Settings", isExpanded: $showAdvanced) {
                    advancedSettingsContent
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Native Tools Picker

    private var nativeToolsPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Capabilities")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button("All") {
                    for entry in nativeToolAvailability where entry.available {
                        enabledNativeToolIDs.insert(entry.skill.id)
                    }
                }
                .font(.caption)
                Button("None") { enabledNativeToolIDs.removeAll() }
                    .font(.caption)
            }
            Text("Built-in Apple capabilities your assistant can use")
                .font(.caption)
                .foregroundStyle(.tertiary)

            ForEach(AppState.skillCategories, id: \.name) { category in
                let categorySkills = nativeToolAvailability.filter { entry in
                    category.skillIDs.contains(entry.skill.id)
                }
                if !categorySkills.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(category.name, systemImage: category.icon)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        FlowLayout(spacing: 6) {
                            ForEach(categorySkills, id: \.skill.id) { entry in
                                let isOn = enabledNativeToolIDs.contains(entry.skill.id)
                                ToolChip(name: entry.skill.name, isOn: isOn, isAvailable: entry.available) {
                                    if isOn { enabledNativeToolIDs.remove(entry.skill.id) }
                                    else { enabledNativeToolIDs.insert(entry.skill.id) }
                                }
                                .help(entry.skill.description)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Skills Picker (SKILL.md)

    private var skillsPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Behaviors")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if !installedSkills.isEmpty {
                    Button("All") {
                        for skill in installedSkills {
                            attachedSkillIDs.insert(skill.id)
                        }
                    }
                    .font(.caption)
                    Button("None") { attachedSkillIDs.removeAll() }
                        .font(.caption)
                }
            }
            Text("Instruction behaviors that shape how your assistant thinks and works")
                .font(.caption)
                .foregroundStyle(.tertiary)

            if installedSkills.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("No behaviors installed — visit the Capability Store to add some")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(.background.opacity(0.6)))
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(installedSkills) { skill in
                        let isOn = attachedSkillIDs.contains(skill.id)
                        ToolChip(name: skill.name, isOn: isOn, isAvailable: true) {
                            if isOn { attachedSkillIDs.remove(skill.id) }
                            else { attachedSkillIDs.insert(skill.id) }
                        }
                        .help(skill.description)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(.background.opacity(0.6)))
            }
        }
    }

    // MARK: - Footer

    private var builderFooter: some View {
        HStack {
            if isEditing {
                // Edit mode: just Save and Cancel
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save Changes") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            } else {
                // New agent: step navigation
                if currentStep != .persona {
                    Button {
                        withAnimation(.spring(duration: 0.3)) {
                            currentStep = BuilderStep(rawValue: currentStep.rawValue - 1) ?? .persona
                        }
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                }

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                if currentStep == .behavior {
                    Button("Create Assistant") { save() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                } else {
                    Button {
                        withAnimation(.spring(duration: 0.3)) {
                            currentStep = BuilderStep(rawValue: currentStep.rawValue + 1) ?? .behavior
                        }
                    } label: {
                        Label("Next", systemImage: "chevron.right")
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - Human-Friendly Labels

    private var creativityLabel: String {
        switch temperature {
        case 0.0...0.2: return "Very precise"
        case 0.2...0.5: return "Focused"
        case 0.5...0.8: return "Balanced"
        case 0.8...1.1: return "Creative"
        default: return "Very creative"
        }
    }

    private var responseLengthLabel: String {
        switch maxTokens {
        case 0...512: return "Brief"
        case 512...1024: return "Short"
        case 1024...2048: return "Medium"
        case 2048...4096: return "Long"
        default: return "Very detailed"
        }
    }

    // MARK: - Template Application

    private func applyTemplate(_ template: AgentTemplate) {
        withAnimation(.spring(duration: 0.2)) {
            name = template.name
            emoji = template.emoji
            gradientHex = template.gradientHex
            instructions = template.instructions
            temperature = template.temperature
            enableThinking = template.enableThinking
            knowledgeEnabled = template.knowledgeEnabled
            learningEnabled = template.learningEnabled
            if !template.skillIDs.isEmpty {
                enabledNativeToolIDs = Set(template.skillIDs)
            }
        }
    }

    private func applyGeneratedConfig(_ config: AgentConfig) {
        name = config.name
        emoji = config.emoji
        if config.gradientHex.count >= 2 { gradientHex = config.gradientHex }
        instructions = config.instructions
        attachedSkillIDs = Set(config.attachedSkillIDs)
        if !config.enabledSkillIDs.isEmpty {
            enabledNativeToolIDs = Set(config.enabledSkillIDs)
        }
        temperature = config.temperature
        topP = config.topP
        maxTokens = config.maxTokens
        enableThinking = config.enableThinking
        markdownOutput = config.markdown
        knowledgeEnabled = config.knowledgeEnabled
        learningEnabled = config.learningEnabled
    }

    // MARK: - Installed Skills

    private func loadInstalledSkills() async {
        do {
            installedSkills = try await appState.skillsShClient.listInstalled()
        } catch {
            installedSkills = []
        }
    }

    // MARK: - Config Load / Save

    private func loadConfig() {
        guard let c = config else { return }
        name = c.name
        emoji = c.emoji
        gradientHex = c.gradientHex
        instructions = c.instructions
        providerType = ProviderType(rawValue: c.providerType) ?? .mlx
        modelID = c.modelID
        toolCallLimit = c.toolCallLimit
        maxIterations = c.maxIterations
        temperature = c.temperature
        topP = c.topP
        maxTokens = c.maxTokens
        repetitionPenalty = c.repetitionPenalty
        enableThinking = c.enableThinking
        markdownOutput = c.markdown
        addDateToSystemPrompt = c.addDateToSystemPrompt
        maxHistoryMessages = c.maxHistoryMessages
        knowledgeEnabled = c.knowledgeEnabled
        knowledgeChunkingStrategy = c.knowledgeChunkingStrategy
        knowledgeHybridWeight = c.knowledgeHybridWeight
        learningEnabled = c.learningEnabled
        learningMode = c.learningMode
        enabledNativeToolIDs = Set(c.enabledSkillIDs)
        customToolIDs = Set(c.customToolIDs)
        mcpServerIDs = Set(c.mcpServerIDs)
        attachedSkillIDs = Set(c.attachedSkillIDs)
        systemPromptFile = c.systemPromptFile
    }

    private func save() {
        var agent = config ?? AgentConfig()
        agent.name = name.trimmingCharacters(in: .whitespaces)
        agent.emoji = emoji
        agent.gradientHex = gradientHex
        agent.instructions = instructions
        agent.providerType = providerType.rawValue
        agent.modelID = modelID
        agent.toolCallLimit = toolCallLimit
        agent.maxIterations = maxIterations
        agent.temperature = temperature
        agent.topP = topP
        agent.maxTokens = maxTokens
        agent.repetitionPenalty = repetitionPenalty
        agent.enableThinking = enableThinking
        agent.markdown = markdownOutput
        agent.addDateToSystemPrompt = addDateToSystemPrompt
        agent.maxHistoryMessages = maxHistoryMessages
        agent.knowledgeEnabled = knowledgeEnabled
        agent.knowledgeChunkingStrategy = knowledgeChunkingStrategy
        agent.knowledgeHybridWeight = knowledgeHybridWeight
        agent.learningEnabled = learningEnabled
        agent.learningMode = learningMode
        agent.enabledSkillIDs = Array(enabledNativeToolIDs)
        agent.customToolIDs = Array(customToolIDs)
        agent.mcpServerIDs = Array(mcpServerIDs)
        agent.attachedSkillIDs = Array(attachedSkillIDs)
        agent.systemPromptFile = systemPromptFile
        agent.updatedAt = Date()

        appState.saveAgent(agent)
        appState.resetLiveAgent(for: agent.id)
        dismiss()
    }

    private func loadSystemPromptFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            systemPromptFile = url.path
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                instructions = content
            }
        }
    }

    private func refreshToolIDs() {
        if let agentID = config?.id {
            for tool in appState.toolConfigs where tool.agentID == agentID {
                customToolIDs.insert(tool.id)
            }
        }
    }

    private func refreshMCPIDs() {}
}

// MARK: - Tool Chip (tappable pill)

private struct ToolChip: View {
    let name: String
    let isOn: Bool
    let isAvailable: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(name)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(
                        isOn ? Color.accentColor.opacity(0.2) :
                        !isAvailable ? Color.gray.opacity(0.05) :
                        Color.secondary.opacity(0.08)
                    )
                )
                .foregroundStyle(
                    isOn ? Color.accentColor :
                    !isAvailable ? Color.gray.opacity(0.4) :
                    Color.secondary
                )
                .overlay(
                    Capsule().stroke(isOn ? Color.accentColor.opacity(0.4) : .clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.5)
    }
}

// MARK: - Feature Toggle Row

private struct FeatureToggleRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(isOn ? color : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isOn ? color.opacity(0.06) : Color.gray.opacity(0.04))
        )
    }
}

// MARK: - Template Card

private struct TemplateCard: View {
    let template: AgentTemplate
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Text(template.emoji)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(template.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isSelected ? Color.accentColor :
                        isHovered ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.2),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// FlowLayout is defined in AgentChatView.swift as a shared internal type
