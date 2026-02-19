import SwiftUI
import SBBender
import UniformTypeIdentifiers

struct AgentChatView: View {
    let agentID: String
    @Environment(AppState.self) private var appState
    @State private var viewModel = AgentChatViewModel()
    @State private var showRightPanel = true
    @State private var agent: Agent?
    @State private var isFileDropTargeted = false
    @State private var showEditSheet = false
    @State private var showClearConfirmation = false
    @State private var knowledgeChunkCount: Int = 0
    @State private var knowledgeDocCount: Int = 0

    private var config: AgentConfig? {
        appState.agentConfig(for: agentID)
    }

    private var hasMessages: Bool {
        !viewModel.messages.isEmpty
    }

    var body: some View {
        HSplitView {
            chatPanel
                .frame(minWidth: 480)

            if showRightPanel {
                rightPanel
                    .frame(minWidth: 260, maxWidth: 360)
            }
        }
        .navigationTitle(config?.name ?? "Chat")
        .toolbar { toolbarContent }
        .sheet(isPresented: $showEditSheet) {
            if let config {
                AgentBuilderSheet(config: config)
                    .environment(appState)
            }
        }
        .task { await setupAgent() }
        .sheet(item: $viewModel.pendingConfirmation) { confirmation in
            ToolConfirmationSheet(confirmation: confirmation) {
                Task {
                    await confirmation.approve()
                    viewModel.pendingConfirmation = nil
                }
            } onDeny: {
                Task {
                    await confirmation.deny()
                    viewModel.pendingConfirmation = nil
                }
            }
        }
        .alert("Start new conversation?", isPresented: $showClearConfirmation) {
            Button("New Chat", role: .destructive) {
                Task { await newChat() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The current conversation will be saved and you can switch back to it later.")
        }
    }

    // MARK: - Chat Panel

    private var chatPanel: some View {
        VStack(spacing: 0) {
            // Compact header bar (always visible)
            if let config {
                compactHeader(config)
                Divider()
            }

            if hasMessages {
                messagesView
            } else if let config {
                welcomeView(config)
            }

            Divider()

            // Metrics bar
            if let metrics = viewModel.metrics {
                MetricsBar(metrics: metrics, statusMessage: viewModel.statusMessage)
            }

            // Input bar
            inputBar
        }
    }

    // MARK: - Compact Header

    private func compactHeader(_ config: AgentConfig) -> some View {
        HStack(spacing: 10) {
            // Back button
            Button {
                appState.selectedSidebarItem = .agents
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Back to My Assistants")

            AgentAvatar(emoji: config.emoji, gradientHex: config.gradientHex, size: 30)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(config.name)
                        .font(.subheadline.weight(.semibold))
                    StatusIndicator(status: viewModel.status, size: 7)
                    if viewModel.isGenerating {
                        Text(statusLabel)
                            .font(.caption2)
                            .foregroundStyle(statusLabelColor)
                    }
                }
                Text(modelLabel(config))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Inline feature badges
            HStack(spacing: 4) {
                if !resolvedSkillNames(config).isEmpty {
                    compactBadge(
                        "\(resolvedSkillNames(config).count)",
                        icon: "sparkle",
                        color: .blue
                    )
                }
                if appState.showAdvancedFeatures && !config.mcpServerIDs.isEmpty {
                    compactBadge(
                        "\(config.mcpServerIDs.count)",
                        icon: "puzzlepiece.extension",
                        color: .green
                    )
                }
                if config.knowledgeEnabled {
                    compactBadge("Docs", icon: "book.closed.fill", color: .indigo)
                }
                if config.learningEnabled {
                    compactBadge("Memory", icon: "brain", color: .purple)
                }
                if config.enableThinking {
                    compactBadge("Reason", icon: "lightbulb.fill", color: .orange)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }

    private func compactBadge(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(text)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Capsule().fill(color.opacity(0.1)))
    }

    // MARK: - Welcome View (empty state)

    private func welcomeView(_ config: AgentConfig) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 40)

                // Hero: avatar + name + description
                VStack(spacing: 14) {
                    AgentAvatar(emoji: config.emoji, gradientHex: config.gradientHex, size: 72)

                    Text(config.name)
                        .font(.title2.weight(.semibold))

                    Text(modelLabel(config))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.quaternary))

                    // Instructions preview
                    if !config.instructions.isEmpty,
                       config.instructions != "You are a helpful assistant." {
                        Text(config.instructions)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(4)
                            .frame(maxWidth: 500)
                    }
                }
                .padding(.bottom, 24)

                // Capabilities grid
                capabilitiesGrid(config)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 24)

                // Knowledge status card
                if config.knowledgeEnabled {
                    knowledgeStatusCard
                        .padding(.horizontal, 40)
                        .padding(.bottom, 24)
                }

                // Quick-start suggestions
                quickStartSuggestions(config)
                    .padding(.horizontal, 40)

                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var knowledgeStatusCard: some View {
        HStack(spacing: 12) {
            if viewModel.isRehydrating {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading knowledge...")
                            .font(.subheadline.weight(.medium))
                    }
                    if case .embedding(let current, let total) = viewModel.rehydrationProgress {
                        ProgressView(value: Double(current), total: Double(max(total, 1)))
                        Text("Analyzing \(current) of \(total) sections...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if case .buildingIndex = viewModel.rehydrationProgress {
                        Text("Making documents searchable...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if knowledgeChunkCount > 0 {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(knowledgeDocCount) document\(knowledgeDocCount == 1 ? "" : "s"), \(knowledgeChunkCount) sections ready")
                        .font(.subheadline.weight(.medium))
                    Text("Knowledge base is loaded and searchable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "doc.badge.plus")
                    .foregroundStyle(.indigo)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No documents loaded")
                        .font(.subheadline.weight(.medium))
                    Text("Add documents in this assistant's settings to get started")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.indigo.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.indigo.opacity(0.15), lineWidth: 1)
        )
    }

    private func capabilitiesGrid(_ config: AgentConfig) -> some View {
        let skillNames = resolvedSkillNames(config)
        let mcpNames = resolvedMCPNames(config)
        let hasAnyCapability = !skillNames.isEmpty || !mcpNames.isEmpty
            || config.knowledgeEnabled || config.learningEnabled
            || !config.customToolIDs.isEmpty || config.enableThinking

        return Group {
            if hasAnyCapability {
                VStack(alignment: .leading, spacing: 12) {
                    // Capabilities
                    if !skillNames.isEmpty {
                        capabilitySection(
                            title: "Capabilities",
                            icon: "sparkle",
                            color: .blue
                        ) {
                            FlowLayout(spacing: 5) {
                                ForEach(skillNames, id: \.self) { name in
                                    Text(name)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(Color.blue.opacity(0.08))
                                        )
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                    }

                    // Plugins (MCP — only visible in advanced mode)
                    if appState.showAdvancedFeatures && !mcpNames.isEmpty {
                        capabilitySection(
                            title: "Plugins",
                            icon: "puzzlepiece.extension",
                            color: .green
                        ) {
                            FlowLayout(spacing: 5) {
                                ForEach(mcpNames, id: \.self) { name in
                                    HStack(spacing: 3) {
                                        Circle()
                                            .fill(.green)
                                            .frame(width: 5, height: 5)
                                        Text(name)
                                            .font(.caption)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.green.opacity(0.08))
                                    )
                                }
                            }
                        }
                    }

                    // Features row
                    let features = collectFeatures(config)
                    if !features.isEmpty {
                        capabilitySection(
                            title: "Features",
                            icon: "sparkles",
                            color: .secondary
                        ) {
                            HStack(spacing: 6) {
                                ForEach(features, id: \.label) { feature in
                                    HStack(spacing: 4) {
                                        Image(systemName: feature.icon)
                                            .font(.system(size: 10))
                                        Text(feature.label)
                                            .font(.caption)
                                    }
                                    .foregroundStyle(feature.color)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(feature.color.opacity(0.08))
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
            }
        }
    }

    private func capabilitySection<Content: View>(
        title: String,
        icon: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            content()
        }
    }

    private func quickStartSuggestions(_ config: AgentConfig) -> some View {
        let suggestions = generateSuggestions(config)
        return Group {
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Try asking")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)

                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            viewModel.inputText = suggestion
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.right.circle")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Text(suggestion)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.ultraThinMaterial)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Messages View

    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.messages) { msg in
                        ChatBubble(message: msg)
                            .id(msg.id)
                    }

                    if viewModel.isGenerating,
                       !viewModel.messages.contains(where: { $0.role == "assistant-streaming" }) {
                        ThinkingBubble(
                            status: viewModel.status,
                            elapsed: viewModel.elapsedSeconds,
                            latestActivity: viewModel.activityEvents.last?.description
                        )
                        .id("thinking-bubble")
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        // File drop overlay for knowledge ingestion
        .overlay {
            if isFileDropTargeted, config?.knowledgeEnabled == true {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.blue.opacity(0.1))
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "doc.badge.plus")
                                .font(.largeTitle)
                            Text("Drop to add to knowledge base")
                                .font(.headline)
                        }
                        .foregroundStyle(.blue)
                    )
                    .padding()
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isFileDropTargeted) { providers in
            guard config?.knowledgeEnabled == true else { return false }
            handleFileDrop(providers)
            return true
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextEditor(text: $viewModel.inputText)
                .font(.body)
                .frame(minHeight: 36, maxHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.shift) {
                        return .ignored // let TextEditor insert newline
                    }
                    Task { await send() }
                    return .handled
                }

            if viewModel.isGenerating {
                Button { viewModel.cancel() } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            } else {
                Button { Task { await send() } } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
    }

    // MARK: - Right Panel (Agent Info + Activity)

    @State private var rightPanelTab: RightPanelTab = .info

    private enum RightPanelTab: String, CaseIterable {
        case info = "Info"
        case activity = "Activity"
    }

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tab picker
            Picker("Panel", selection: $rightPanelTab) {
                ForEach(RightPanelTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(10)

            Divider()

            switch rightPanelTab {
            case .info:
                agentInfoPanel
            case .activity:
                activityPanel
            }
        }
        .background(.ultraThinMaterial)
        .onChange(of: viewModel.activityEvents.count) { old, new in
            // Auto-switch to activity when events start coming in
            if old == 0 && new > 0 {
                rightPanelTab = .activity
            }
        }
    }

    // MARK: - Agent Info Panel

    private var agentInfoPanel: some View {
        ScrollView {
            if let config {
                VStack(alignment: .leading, spacing: 16) {
                    // AI Engine
                    infoSection(title: "AI Engine", icon: "cpu") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ProviderType(rawValue: config.providerType)?.displayName ?? config.providerType)
                                .font(.subheadline.weight(.medium))
                            Text(config.modelID.components(separatedBy: "/").last ?? config.modelID)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Instructions
                    if !config.instructions.isEmpty,
                       config.instructions != "You are a helpful assistant." {
                        infoSection(title: "Instructions", icon: "text.alignleft") {
                            Text(config.instructions)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(8)
                        }
                    }

                    // Capabilities
                    let skillNames = resolvedSkillNames(config)
                    if !skillNames.isEmpty {
                        infoSection(title: "Capabilities (\(skillNames.count))", icon: "sparkle") {
                            FlowLayout(spacing: 4) {
                                ForEach(skillNames, id: \.self) { name in
                                    Text(name)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(
                                            RoundedRectangle(cornerRadius: 5)
                                                .fill(Color.blue.opacity(0.08))
                                        )
                                }
                            }
                        }
                    }

                    // Plugins (MCP — gated)
                    let mcpNames = resolvedMCPNames(config)
                    if appState.showAdvancedFeatures && !mcpNames.isEmpty {
                        infoSection(title: "Plugins (\(mcpNames.count))", icon: "puzzlepiece.extension") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(mcpNames, id: \.self) { name in
                                    HStack(spacing: 5) {
                                        Circle()
                                            .fill(.green)
                                            .frame(width: 5, height: 5)
                                        Text(name)
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                    }

                    // Custom Tools (gated)
                    let toolNames = resolvedToolNames(config)
                    if appState.showAdvancedFeatures && !toolNames.isEmpty {
                        infoSection(title: "Custom Actions (\(toolNames.count))", icon: "wrench") {
                            FlowLayout(spacing: 4) {
                                ForEach(toolNames, id: \.self) { name in
                                    Text(name)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(
                                            RoundedRectangle(cornerRadius: 5)
                                                .fill(Color.orange.opacity(0.08))
                                        )
                                }
                            }
                        }
                    }

                    // Features
                    let features = collectFeatures(config)
                    if !features.isEmpty {
                        infoSection(title: "Features", icon: "sparkles") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(features, id: \.label) { f in
                                    HStack(spacing: 5) {
                                        Image(systemName: f.icon)
                                            .font(.caption2)
                                            .foregroundStyle(f.color)
                                            .frame(width: 14)
                                        Text(f.label)
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                    }

                    // Settings
                    infoSection(title: "Settings", icon: "slider.horizontal.3") {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                            GridRow {
                                Text("Creativity")
                                    .font(.caption2).foregroundStyle(.secondary)
                                Text(friendlyCreativity(config.temperature))
                                    .font(.caption.weight(.medium))
                            }
                            GridRow {
                                Text("Response length")
                                    .font(.caption2).foregroundStyle(.secondary)
                                Text(friendlyResponseLength(config.maxTokens))
                                    .font(.caption.weight(.medium))
                            }
                            if appState.showAdvancedFeatures {
                                GridRow {
                                    Text("Top-p")
                                        .font(.caption2).foregroundStyle(.secondary)
                                    Text(String(format: "%.1f", config.topP))
                                        .font(.caption.weight(.medium))
                                }
                            }
                        }
                    }

                    // Edit button
                    Button {
                        showEditSheet = true
                    } label: {
                        Label("Edit Assistant", systemImage: "pencil")
                            .font(.caption.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(12)
            }
        }
    }

    private func infoSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            content()
        }
    }

    // MARK: - Activity Panel

    private var activityPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.activityEvents.isEmpty {
                ContentUnavailableView(
                    "No Activity",
                    systemImage: "waveform",
                    description: Text("Events will appear here when the assistant runs.")
                )
            } else {
                ActivityFeedView(events: viewModel.activityEvents)
            }

            // Tool outputs
            if !viewModel.toolOutputEntries.isEmpty {
                Divider()
                toolOutputSection
            }
        }
    }

    @ViewBuilder
    private var toolOutputSection: some View {
        if appState.showAdvancedFeatures {
            VStack(alignment: .leading, spacing: 0) {
                Text("Action Results")
                    .font(.subheadline.bold())
                    .padding(12)
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(viewModel.toolOutputEntries, id: \.callID) { entry in
                            DisclosureGroup {
                                Text(entry.fullOutput)
                                    .font(.system(.caption2, design: .monospaced))
                                    .textSelection(.enabled)
                                    .padding(6)
                            } label: {
                                HStack {
                                    Image(systemName: "wrench.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                    Text(entry.toolName)
                                        .font(.caption.bold())
                                    Spacer()
                                }
                            }
                            .padding(.horizontal, 12)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            if viewModel.sessions.count > 1 {
                Menu {
                    ForEach(viewModel.sessions) { session in
                        Button {
                            Task {
                                let storage = await appState.persistence?.storage
                                if let agent { await agent.setSessionID(session.id) }
                                await viewModel.switchSession(to: session.id, storage: storage)
                            }
                        } label: {
                            HStack {
                                Text(session.title)
                                if session.id == viewModel.currentSessionID {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    Divider()
                    ForEach(viewModel.sessions) { session in
                        if session.id != viewModel.currentSessionID {
                            Button(role: .destructive) {
                                Task {
                                    let storage = await appState.persistence?.storage
                                    await viewModel.deleteSession(session.id, storage: storage, agentID: agentID)
                                }
                            } label: {
                                Label("Delete \"\(session.title)\"", systemImage: "trash")
                            }
                        }
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .help("Chat History")
            }
        }
        ToolbarItem(placement: .automatic) {
            Button {
                showEditSheet = true
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Edit Assistant")
        }
        ToolbarItem(placement: .automatic) {
            Button {
                showClearConfirmation = true
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .help("New Chat")
        }
        ToolbarItem(placement: .automatic) {
            Button {
                withAnimation { showRightPanel.toggle() }
            } label: {
                Image(systemName: "sidebar.trailing")
            }
            .help("Toggle Info Panel")
        }
    }

    // MARK: - Actions

    private func setupAgent() async {
        guard let config else { return }
        self.agent = await appState.getOrCreateLiveAgent(for: config)
        let storage = await appState.persistence?.storage
        await viewModel.loadConversation(storage: storage, agentID: config.id)

        // Auto-rehydrate knowledge if indexer is empty but files are persisted
        if config.knowledgeEnabled {
            let indexer = appState.getOrCreateKnowledgeIndexer(for: config)
            let chunks = await indexer.chunkCount
            if chunks == 0 {
                viewModel.isRehydrating = true
                await indexer.setOnProgress { [viewModel] progress in
                    Task { @MainActor in
                        viewModel.rehydrationProgress = progress.phase
                    }
                }
                await appState.rehydrateKnowledge(for: config)
                viewModel.isRehydrating = false
                viewModel.rehydrationProgress = nil
            }
            // Update knowledge stats for the welcome view
            knowledgeChunkCount = await indexer.chunkCount
            knowledgeDocCount = await indexer.sourceCount
        }
    }

    private func newChat() async {
        let storage = await appState.persistence?.storage
        await viewModel.newChat(agent: agent, storage: storage, agentID: agentID)
    }

    private func send() async {
        guard let agent else { return }
        let providerName = config.flatMap { ProviderType(rawValue: $0.providerType)?.displayName }
        let isFirstMessage = viewModel.messages.count(where: { $0.role == "user" }) <= 1
        await viewModel.sendMessage(
            agent: agent,
            agentName: config?.name ?? "Assistant",
            providerType: providerName,
            modelID: config?.modelID
        )
        // Auto-title session from first user message
        if isFirstMessage, let agentID = config?.id {
            let storage = await appState.persistence?.storage
            await viewModel.updateSessionTitle(storage: storage, agentID: agentID)
        }
    }

    private func handleFileDrop(_ providers: [NSItemProvider]) {
        guard let config, config.knowledgeEnabled else { return }

        Task {
            var urls: [URL] = []
            for provider in providers {
                if let url = await loadFileURL(from: provider) {
                    urls.append(url)
                }
            }

            guard !urls.isEmpty else { return }
            let indexer = appState.getOrCreateKnowledgeIndexer(for: config)
            let loader = DocumentLoader()

            for url in urls {
                do {
                    let result = try loader.loadText(at: url.path)
                    try await indexer.ingest(content: result.content, title: result.title)
                    try await indexer.buildIndex()

                    let entry = KnowledgeFileEntry(
                        agentID: config.id,
                        fileName: url.lastPathComponent,
                        filePath: url.path,
                        fileType: url.pathExtension
                    )
                    try? await appState.persistence?.saveKnowledgeFile(entry)

                    viewModel.activityEvents.append(ActivityEvent(
                        kind: .toolCallCompleted(name: "knowledge_ingest", chars: result.content.count),
                        agentName: config.name
                    ))
                } catch {
                    viewModel.activityEvents.append(ActivityEvent(
                        kind: .toolCallError(name: "knowledge_ingest", error: error.localizedDescription),
                        agentName: config.name
                    ))
                }
            }
        }
    }

    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: url)
            }
        }
    }

    // MARK: - Helpers

    private var statusLabel: String {
        switch viewModel.status {
        case .thinking:
            let s = viewModel.elapsedSeconds
            return s > 0 ? "Thinking... \(s)s" : "Thinking..."
        case .working:
            return "Working..."
        case .streaming:
            return "Generating"
        case .error:
            return "Error"
        default:
            return ""
        }
    }

    private var statusLabelColor: Color {
        switch viewModel.status {
        case .thinking: .purple
        case .working: .orange
        case .streaming: .green
        case .error: .red
        default: .secondary
        }
    }

    private func modelLabel(_ config: AgentConfig) -> String {
        let provider = ProviderType(rawValue: config.providerType)?.displayName ?? config.providerType
        let model = friendlyModelName(config.modelID)
        return "\(provider) \u{2022} \(model)"
    }

    private func friendlyModelName(_ modelID: String) -> String {
        let short = modelID.components(separatedBy: "/").last ?? modelID
        // Map known model patterns to friendly names
        let lower = short.lowercased()
        if lower.contains("qwen3-4b") || lower.contains("qwen3-1.7b") { return "Small & Fast" }
        if lower.contains("qwen3-8b") { return "Balanced" }
        if lower.contains("qwen3-14b") || lower.contains("qwen3-30b") { return "Powerful" }
        if lower.contains("qwen3-32b") || lower.contains("qwen3-70b") { return "Very Powerful" }
        // Strip quantization suffixes for other models
        return short
            .replacingOccurrences(of: "-4bit", with: "")
            .replacingOccurrences(of: "-8bit", with: "")
            .replacingOccurrences(of: "-4-bit", with: "")
            .replacingOccurrences(of: "-8-bit", with: "")
    }

    private func friendlyCreativity(_ t: Float) -> String {
        switch t {
        case 0.0...0.2: return "Very precise"
        case 0.2...0.5: return "Focused"
        case 0.5...0.8: return "Balanced"
        case 0.8...1.1: return "Creative"
        default: return "Very creative"
        }
    }

    private func friendlyResponseLength(_ tokens: Int) -> String {
        switch tokens {
        case ...512: return "Brief"
        case 513...1024: return "Short"
        case 1025...2048: return "Medium"
        case 2049...4096: return "Long"
        default: return "Very long"
        }
    }

    private func resolvedSkillNames(_ config: AgentConfig) -> [String] {
        config.enabledSkillIDs.map { SkillMetadata.displayName(for: $0) }
    }

    private func resolvedMCPNames(_ config: AgentConfig) -> [String] {
        config.mcpServerIDs.compactMap { id in
            appState.mcpServerConfigs.first(where: { $0.id == id })?.name
        }
    }

    private func resolvedToolNames(_ config: AgentConfig) -> [String] {
        config.customToolIDs.compactMap { id in
            appState.toolConfigs.first(where: { $0.id == id })?.name
        }
    }

    private struct FeatureInfo: Hashable {
        let label: String
        let icon: String
        let color: Color

        func hash(into hasher: inout Hasher) {
            hasher.combine(label)
        }
        static func == (lhs: FeatureInfo, rhs: FeatureInfo) -> Bool {
            lhs.label == rhs.label
        }
    }

    private func collectFeatures(_ config: AgentConfig) -> [FeatureInfo] {
        var features: [FeatureInfo] = []
        if config.knowledgeEnabled {
            features.append(FeatureInfo(label: "Knowledge Base", icon: "book.closed.fill", color: .indigo))
        }
        if config.learningEnabled {
            features.append(FeatureInfo(label: "Memory", icon: "brain", color: .purple))
        }
        if config.enableThinking {
            features.append(FeatureInfo(label: "Deep Reasoning", icon: "lightbulb.fill", color: .orange))
        }
        if config.markdown {
            features.append(FeatureInfo(label: "Markdown", icon: "text.badge.checkmark", color: .teal))
        }
        if !config.attachedSkillIDs.isEmpty {
            features.append(FeatureInfo(label: "\(config.attachedSkillIDs.count) Instructions", icon: "doc.text", color: .mint))
        }
        return features
    }

    private func generateSuggestions(_ config: AgentConfig) -> [String] {
        let ids = Set(config.enabledSkillIDs)
        var suggestions: [String] = []

        if ids.contains("shell") {
            suggestions.append("List all files in my Desktop folder")
        }
        if ids.contains("web-fetch") {
            suggestions.append("Fetch the latest news from Hacker News")
        }
        if ids.contains("calendar") {
            suggestions.append("What meetings do I have today?")
        }
        if ids.contains("reminders") {
            suggestions.append("Show my pending reminders")
        }
        if ids.contains("applescript") {
            suggestions.append("Open Safari and go to apple.com")
        }
        if ids.contains("sentiment") {
            suggestions.append("Analyze the sentiment of this text: I love this product!")
        }
        if ids.contains("entity-extraction") {
            suggestions.append("Extract key entities from a news article")
        }
        if ids.contains("transcription") {
            suggestions.append("Transcribe the last recorded meeting")
        }
        if ids.contains("email") {
            suggestions.append("Check my unread emails")
        }
        if ids.contains("language-detection") {
            suggestions.append("Detect the language of: Bonjour le monde")
        }
        if config.knowledgeEnabled {
            suggestions.append("Drop a file here to start analyzing it")
        }

        // Fallback for agents with no specific skills
        if suggestions.isEmpty {
            suggestions.append("Tell me about yourself and what you can do")
            suggestions.append("Help me with a task")
        }

        return Array(suggestions.prefix(3))
    }
}

// MARK: - ThinkingBubble

struct ThinkingBubble: View {
    let status: AgentStatus
    let elapsed: Int
    var latestActivity: String? = nil

    private var label: String {
        switch status {
        case .thinking: "Thinking"
        case .working: "Working"
        default: "Thinking"
        }
    }

    private var labelColor: Color {
        switch status {
        case .working: .orange
        default: .purple
        }
    }

    private var stageHint: String? {
        if elapsed < 3 { return "Starting up..." }
        if elapsed < 15 && status == .thinking { return "Warming up..." }
        if elapsed >= 15 && status == .thinking { return "Writing reply..." }
        return nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(labelColor)
                .frame(width: 28)
                .symbolEffect(.pulse)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(label)
                        .font(.caption.bold())
                        .foregroundStyle(labelColor)

                    BouncingDots(color: labelColor)

                    if elapsed > 0 {
                        Text("\(elapsed)s")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }

                // Show latest activity or stage hint
                if let activity = latestActivity {
                    Text(activity)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .transition(.opacity)
                } else if let hint = stageHint {
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }
        }
        .padding(12)
        .background(labelColor.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .animation(.easeInOut(duration: 0.3), value: latestActivity)
        .animation(.easeInOut(duration: 0.3), value: stageHint)
    }
}

struct BouncingDots: View {
    let color: Color
    @State private var animate = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(color)
                    .frame(width: 4, height: 4)
                    .offset(y: animate ? -3 : 0)
                    .animation(
                        .easeInOut(duration: 0.4)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.15),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}

// MARK: - FlowLayout (shared)

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangeSubviews(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }
        return (positions, CGSize(width: maxX, height: y + rowHeight))
    }
}
