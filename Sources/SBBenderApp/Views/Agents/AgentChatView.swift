import SwiftUI
import SBBender
import UniformTypeIdentifiers

struct AgentChatView: View {
    let agentID: String
    @Environment(AppState.self) private var appState
    @State private var viewModel = AgentChatViewModel()
    @State private var showActivitySidebar = true
    @State private var agent: Agent?
    @State private var isFileDropTargeted = false

    private var config: AgentConfig? {
        appState.agentConfig(for: agentID)
    }

    var body: some View {
        HSplitView {
            chatPanel
                .frame(minWidth: 500)

            if showActivitySidebar {
                activityPanel
                    .frame(minWidth: 260, maxWidth: 360)
            }
        }
        .navigationTitle(config?.name ?? "Agent Chat")
        .toolbar { toolbarContent }
        .task { await setupAgent() }
    }

    // MARK: - Chat Panel

    private var chatPanel: some View {
        VStack(spacing: 0) {
            // Agent header
            if let config {
                agentHeader(config)
                Divider()
            }

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { msg in
                            ChatBubble(message: msg)
                                .id(msg.id)
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

            Divider()

            // Metrics bar
            if let metrics = viewModel.metrics {
                MetricsBar(metrics: metrics, statusMessage: viewModel.statusMessage)
            }

            // Input bar
            inputBar
        }
    }

    private func agentHeader(_ config: AgentConfig) -> some View {
        HStack(spacing: 12) {
            AgentAvatar(emoji: config.emoji, gradientHex: config.gradientHex, size: 36)
            VStack(alignment: .leading) {
                HStack(spacing: 6) {
                    Text(config.name)
                        .font(.headline)
                    StatusIndicator(status: viewModel.status, size: 8)
                }
                HStack(spacing: 8) {
                    Text(ProviderType(rawValue: config.providerType)?.displayName ?? config.providerType)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Feature badges
                    if config.knowledgeEnabled {
                        featureBadge("RAG", icon: "doc.text.magnifyingglass", color: .blue)
                    }
                    if config.learningEnabled {
                        featureBadge("Memory", icon: "brain", color: .purple)
                    }
                    if !config.mcpServerIDs.isEmpty {
                        featureBadge("MCP", icon: "server.rack", color: .green)
                    }
                    if !config.customToolIDs.isEmpty {
                        featureBadge("\(config.customToolIDs.count) Tools", icon: "wrench", color: .orange)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func featureBadge(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption2)
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(Capsule().fill(color.opacity(0.1)))
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextEditor(text: $viewModel.inputText)
                .font(.body)
                .frame(minHeight: 36, maxHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onSubmit { Task { await send() } }

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
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(12)
    }

    // MARK: - Activity Panel

    private var activityPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Activity")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.activityEvents.count)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }
            .padding(12)

            Divider()

            if viewModel.activityEvents.isEmpty {
                ContentUnavailableView(
                    "No Activity",
                    systemImage: "waveform",
                    description: Text("Events will appear here when the agent runs.")
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
        .background(.ultraThinMaterial)
    }

    private var toolOutputSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Tool Outputs")
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
                                Text("\(entry.characterCount) chars")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Button {
                Task { await newChat() }
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .help("New Chat")
        }
        ToolbarItem(placement: .automatic) {
            Button {
                withAnimation { showActivitySidebar.toggle() }
            } label: {
                Image(systemName: "sidebar.trailing")
            }
            .help("Toggle Activity Sidebar")
        }
        ToolbarItem(placement: .automatic) {
            Button {
                Task {
                    let storage = await appState.persistence?.storage
                    await viewModel.clearChat(agent: agent, storage: storage, agentID: agentID)
                }
            } label: {
                Image(systemName: "trash")
            }
            .help("Clear Chat")
        }
    }

    // MARK: - Actions

    private func setupAgent() async {
        guard let config else { return }
        self.agent = await appState.getOrCreateLiveAgent(for: config)
        let storage = await appState.persistence?.storage
        await viewModel.loadConversation(storage: storage, agentID: config.id)
    }

    private func newChat() async {
        let storage = await appState.persistence?.storage
        await viewModel.clearChat(agent: agent, storage: storage, agentID: agentID)
    }

    private func send() async {
        guard let agent else { return }
        await viewModel.sendMessage(agent: agent, agentName: config?.name ?? "Agent")
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
}
