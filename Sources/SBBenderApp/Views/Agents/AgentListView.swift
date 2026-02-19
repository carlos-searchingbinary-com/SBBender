import SwiftUI
import SBBender

struct AgentListView: View {
    @Environment(AppState.self) private var appState
    @State private var showingBuilder = false
    @State private var editingAgent: AgentConfig?
    @State private var selectedTemplate: AgentTemplate?
    @State private var agentToDelete: AgentConfig?
    @State private var lastMessages: [String: String] = [:]
    @State private var bundles: [BundleEntry] = []
    @State private var applyingBundleID: String?

    private let columns = [
        GridItem(.adaptive(minimum: 260, maximum: 340), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Template quick-start
                if appState.agents.isEmpty {
                    emptyStateView
                } else {
                    // Quick Setup bundles
                    if !bundles.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Quick Setup")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 20)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(compatibleBundles) { bundle in
                                        BundleChip(
                                            bundle: bundle,
                                            isApplying: applyingBundleID == bundle.id
                                        ) {
                                            applyBundle(bundle)
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                        .padding(.top, 4)
                    }

                    // Compact template strip
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Create from template")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 20)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(appState.agentTemplates) { template in
                                    MiniTemplateChip(template: template) {
                                        selectedTemplate = template
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.top, 4)
                }

                // Agent grid
                LazyVGrid(columns: columns, spacing: 16) {
                    // New Agent
                    Button { showingBuilder = true } label: {
                        VStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                                    .foregroundStyle(.secondary.opacity(0.5))
                                    .frame(width: 48, height: 48)
                                Image(systemName: "plus")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            Text("New AI Assistant")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)

                    // Agent cards — clicking the whole card opens chat
                    ForEach(appState.agents) { agent in
                        AgentCard(
                            config: agent,
                            skills: appState.nativeSkills,
                            lastMessage: lastMessages[agent.id]
                        ) {
                            appState.selectedSidebarItem = .agentChat(agent.id)
                        } onEdit: {
                            editingAgent = agent
                        } onDelete: {
                            agentToDelete = agent
                        }
                        .onTapGesture {
                            appState.selectedSidebarItem = .agentChat(agent.id)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 20)
        }
        .navigationTitle("My Assistants")
        .sheet(isPresented: $showingBuilder) {
            AgentBuilderSheet(config: nil)
                .environment(appState)
        }
        .sheet(item: $editingAgent) { agent in
            AgentBuilderSheet(config: agent)
                .environment(appState)
        }
        .sheet(item: $selectedTemplate) { template in
            AgentBuilderSheet(config: nil, template: template)
                .environment(appState)
        }
        .alert(
            "Delete Assistant?",
            isPresented: Binding(
                get: { agentToDelete != nil },
                set: { if !$0 { agentToDelete = nil } }
            ),
            presenting: agentToDelete
        ) { agent in
            Button("Delete", role: .destructive) {
                appState.deleteAgent(agent)
                agentToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                agentToDelete = nil
            }
        } message: { agent in
            Text("Are you sure you want to delete \"\(agent.name)\"? This cannot be undone.")
        }
        .task {
            await loadBundles()
            await loadLastMessages()
        }
    }

    /// Bundles compatible with the user's hardware tier.
    private var compatibleBundles: [BundleEntry] {
        let tier = appState.hardwareInfo.modelTier
        return bundles.filter { $0.minTier <= tier }
    }

    private func loadBundles() async {
        do {
            bundles = try await appState.curatedRegistry.bundles()
        } catch {
            // Silently fail — bundles are optional
        }
    }

    private func applyBundle(_ bundle: BundleEntry) {
        applyingBundleID = bundle.id
        Task {
            await appState.applyBundle(bundle)
            applyingBundleID = nil
        }
    }

    private func loadLastMessages() async {
        guard let storage = await appState.persistence?.storage else { return }
        for agent in appState.agents {
            do {
                if let session = try await storage.getSession(id: agent.id) {
                    // Find last assistant message
                    if let lastAssistant = session.messages.last(where: { $0.role == .assistant }) {
                        let text = lastAssistant.content.compactMap { content -> String? in
                            if case .text(let s) = content { return s }
                            return nil
                        }.joined()
                        if !text.isEmpty {
                            let preview = text.prefix(80)
                            lastMessages[agent.id] = String(preview) + (text.count > 80 ? "..." : "")
                        }
                    }
                }
            } catch {
                // Skip this agent
            }
        }
    }

    // MARK: - Empty State (first-time UX)

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Create your first AI assistant")
                    .font(.title3.weight(.semibold))
                Text("Pick a template to get started, or build one from scratch")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 12)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 12)], spacing: 12) {
                ForEach(appState.agentTemplates) { template in
                    LargeTemplateCard(template: template) {
                        selectedTemplate = template
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Agent Card (rich)

private struct AgentCard: View {
    let config: AgentConfig
    let skills: [any NativeTool]
    var lastMessage: String?
    let onChat: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    /// Resolve skill names from IDs using metadata for human-readable names
    private var enabledSkillNames: [String] {
        config.enabledSkillIDs.map { SkillMetadata.displayName(for: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top: avatar + name + chat button
            HStack(spacing: 12) {
                AgentAvatar(emoji: config.emoji, gradientHex: config.gradientHex, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(config.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(providerLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Last message preview
            if let lastMessage {
                Text(lastMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }

            // Capabilities summary
            VStack(alignment: .leading, spacing: 8) {
                // Tools as wrapped pills
                if !enabledSkillNames.isEmpty {
                    WrappingHStack(items: enabledSkillNames, maxRows: 2) { name in
                        Text(name)
                            .font(.caption2)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.accentColor.opacity(0.1)))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("All tools enabled")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                // Feature badges
                HStack(spacing: 8) {
                    if !config.attachedSkillIDs.isEmpty {
                        FeaturePill(icon: "doc.text", text: "\(config.attachedSkillIDs.count) Behaviors", color: .indigo)
                    }
                    if config.knowledgeEnabled {
                        FeaturePill(icon: "book.closed.fill", text: "Knowledge", color: .blue)
                    }
                    if config.learningEnabled {
                        FeaturePill(icon: "brain", text: "Memory", color: .purple)
                    }
                    if !config.mcpServerIDs.isEmpty {
                        FeaturePill(icon: "server.rack", text: "\(config.mcpServerIDs.count) Plugins", color: .orange)
                    }
                    if !config.customToolIDs.isEmpty {
                        FeaturePill(icon: "wrench.fill", text: "\(config.customToolIDs.count) Tools", color: .green)
                    }
                    if config.enableThinking {
                        FeaturePill(icon: "lightbulb.fill", text: "Deep Reasoning", color: .yellow)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)

            Divider()

            // Bottom bar: personality + actions
            HStack(spacing: 12) {
                // Personality indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(creativityColor)
                        .frame(width: 6, height: 6)
                    Text(creativityLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if !config.instructions.isEmpty && config.instructions != "You are a helpful assistant." {
                    Text("Custom instructions")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                // Edit button (chat is the whole card now)
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if isHovered {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isHovered ? Color.accentColor.opacity(0.4) : .clear, lineWidth: 2)
        )
        .onHover { val in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = val }
        }
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .contextMenu {
            Button("Open Chat", systemImage: "message", action: onChat)
            Button("Edit", systemImage: "pencil", action: onEdit)
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    private var providerLabel: String {
        let pt = ProviderType(rawValue: config.providerType)?.displayName ?? config.providerType
        let model = config.modelID.components(separatedBy: "/").last ?? config.modelID
        return "\(pt) \u{2022} \(model)"
    }

    private var creativityLabel: String {
        switch config.temperature {
        case 0.0...0.3: return "Precise"
        case 0.3...0.6: return "Focused"
        case 0.6...0.9: return "Balanced"
        default: return "Creative"
        }
    }

    private var creativityColor: Color {
        switch config.temperature {
        case 0.0...0.3: return .blue
        case 0.3...0.6: return .green
        case 0.6...0.9: return .orange
        default: return .red
        }
    }
}

// MARK: - Feature Pill

private struct FeaturePill: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(text)
                .font(.caption2)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.1)))
    }
}

// MARK: - Wrapping HStack (for skill pills)

private struct WrappingHStack<Item: Hashable, Content: View>: View {
    let items: [Item]
    let maxRows: Int
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        // Simple horizontal flow with overflow
        let visible = Array(items.prefix(maxRows * 4))
        let remaining = items.count - visible.count

        FlowLayout(spacing: 4) {
            ForEach(visible, id: \.self) { item in
                content(item)
            }
            if remaining > 0 {
                Text("+\(remaining)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
            }
        }
    }
}

// FlowLayout is defined in AgentChatView.swift as a shared internal type

// MARK: - Mini Template Chip (compact strip)

private struct MiniTemplateChip: View {
    let template: AgentTemplate
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Text(template.emoji)
                    .font(.subheadline)
                Text(template.name)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(isHovered ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Large Template Card (empty state)

private struct LargeTemplateCard: View {
    let template: AgentTemplate
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(template.emoji)
                        .font(.largeTitle)
                    Spacer()
                }
                Text(template.name)
                    .font(.headline)
                Text(template.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Spacer()

                // Skill preview
                HStack(spacing: 4) {
                    ForEach(template.skillIDs.prefix(3), id: \.self) { skillID in
                        Text(SkillMetadata.displayName(for: skillID))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.1)))
                            .foregroundStyle(.secondary)
                    }
                    if template.skillIDs.count > 3 {
                        Text("+\(template.skillIDs.count - 3)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 160)
            .padding(16)
            .background(
                LinearGradient(
                    colors: template.gradientHex.map { Color(hex: $0).opacity(0.08) },
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isHovered ? Color.accentColor.opacity(0.4) : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Bundle Chip

private struct BundleChip: View {
    let bundle: BundleEntry
    let isApplying: Bool
    let onApply: () -> Void

    @State private var isHovered = false

    private var bundleEmoji: String {
        switch bundle.id {
        case "starter": return "🚀"
        case "research-setup": return "🔬"
        case "developer-setup": return "👨‍💻"
        case "macos-automation": return "⚙️"
        case "data-analysis": return "📊"
        case "meeting-copilot": return "🎙️"
        case "power-user": return "💎"
        default: return "📦"
        }
    }

    var body: some View {
        Button(action: onApply) {
            HStack(spacing: 6) {
                if isApplying {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(bundleEmoji)
                        .font(.subheadline)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(bundle.name)
                        .font(.caption.weight(.medium))
                    Text(bundle.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isHovered ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isApplying)
        .onHover { isHovered = $0 }
    }
}
