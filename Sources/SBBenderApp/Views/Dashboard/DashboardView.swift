import SwiftUI
import SBBender

struct DashboardView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Hero
                heroSection

                // Capabilities grid
                capabilitiesSection

                // Stats footer
                statsFooter
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your AI Can...")
                .font(.largeTitle.bold())

            Text("These are the capabilities available to your assistants — powered by Apple Silicon and local models.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 500, alignment: .leading)
        }
    }

    // MARK: - Capabilities Grid

    private var capabilitiesSection: some View {
        let capabilities = buildCapabilities()
        let grouped = Dictionary(grouping: capabilities) { $0.category }
        let sortedCategories: [CapabilityCategory] = [.language, .calendar, .documents, .web, .automation, .analysis]

        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 16)], spacing: 16) {
            ForEach(sortedCategories, id: \.self) { category in
                if let items = grouped[category] {
                    ForEach(items) { cap in
                        capabilityCard(cap)
                    }
                }
            }
        }
    }

    private func capabilityCard(_ cap: Capability) -> some View {
        Button {
            if let agentID = cap.availableInAgentID {
                appState.selectedSidebarItem = .agentChat(agentID)
            } else {
                // "Needs Setup" → navigate to agent list so user can create one
                appState.selectedSidebarItem = .agents
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: cap.icon)
                        .font(.title2)
                        .foregroundStyle(cap.isActive ? cap.color : .secondary)
                        .frame(width: 32, height: 32)

                    Spacer()

                    Text(cap.isActive ? "Active" : "Add to Assistant")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(cap.isActive ? Color.green.opacity(0.12) : Color.orange.opacity(0.12))
                        )
                        .foregroundStyle(cap.isActive ? .green : .orange)
                }

                Text(cap.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text(cap.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if !cap.examplePrompt.isEmpty {
                    Text("Try: \"\(cap.examplePrompt)\"")
                        .font(.system(size: 10))
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                        .italic()
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stats Footer

    private var statsFooter: some View {
        HStack(spacing: 24) {
            statBadge(value: "\(appState.agents.count)", label: "Assistants")
            statBadge(value: "\(activeSkillCount)", label: "Active Capabilities")
            statBadge(value: "\(appState.teams.count)", label: "Teams")
        }
        .padding(.top, 8)
    }

    private func statBadge(value: String, label: String) -> some View {
        HStack(spacing: 6) {
            Text(value)
                .font(.title3.bold().monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Data

    private var activeSkillCount: Int {
        Set(appState.agents.flatMap(\.enabledSkillIDs)).count
    }

    private func buildCapabilities() -> [Capability] {
        let enabledSkills = Set(appState.agents.flatMap(\.enabledSkillIDs))
        let agentsBySkill: [String: String] = {
            var map: [String: String] = [:]
            for agent in appState.agents {
                for sid in agent.enabledSkillIDs where map[sid] == nil {
                    map[sid] = agent.id
                }
            }
            return map
        }()

        func isActive(_ skillID: String) -> Bool { enabledSkills.contains(skillID) }
        func agentFor(_ skillID: String) -> String? { agentsBySkill[skillID] }

        return [
            // Language
            Capability(name: "Language Detection", description: "Identify 60+ languages instantly", icon: "globe", color: .blue, category: .language, isActive: isActive("language-detection"), examplePrompt: "What language is this?", availableInAgentID: agentFor("language-detection")),
            Capability(name: "Sentiment Analysis", description: "Analyze emotional tone of text", icon: "face.smiling", color: .green, category: .language, isActive: isActive("sentiment"), examplePrompt: "How does this review feel?", availableInAgentID: agentFor("sentiment")),
            Capability(name: "Entity Extraction", description: "Find names, places, dates in text", icon: "person.text.rectangle", color: .purple, category: .language, isActive: isActive("entity-extraction"), examplePrompt: "Extract people and places from this article", availableInAgentID: agentFor("entity-extraction")),
            Capability(name: "Translation", description: "Translate between languages on-device", icon: "character.bubble", color: .teal, category: .language, isActive: isActive("translation"), examplePrompt: "Translate this to Spanish", availableInAgentID: agentFor("translation")),

            // Calendar & Tasks
            Capability(name: "Calendar", description: "View and manage calendar events", icon: "calendar", color: .red, category: .calendar, isActive: isActive("calendar"), examplePrompt: "What's on my schedule today?", availableInAgentID: agentFor("calendar")),
            Capability(name: "Reminders", description: "Create and search reminders", icon: "checklist", color: .orange, category: .calendar, isActive: isActive("reminders"), examplePrompt: "Remind me to call Mom at 5pm", availableInAgentID: agentFor("reminders")),

            // Documents
            Capability(name: "Knowledge Base", description: "Search ingested documents with AI", icon: "doc.text.magnifyingglass", color: .indigo, category: .documents, isActive: appState.agents.contains(where: { $0.knowledgeEnabled }), examplePrompt: "What does the report say about Q4?", availableInAgentID: appState.agents.first(where: { $0.knowledgeEnabled })?.id),

            // Web
            Capability(name: "Web Browsing", description: "Navigate and extract web content", icon: "safari", color: .blue, category: .web, isActive: isActive("webkit_browser") || isActive("browser"), examplePrompt: "Summarize the homepage of apple.com", availableInAgentID: agentFor("webkit_browser") ?? agentFor("browser")),
            Capability(name: "Web Fetch", description: "Download and parse web pages", icon: "arrow.down.doc", color: .cyan, category: .web, isActive: isActive("web-fetch"), examplePrompt: "Fetch the latest Swift blog post", availableInAgentID: agentFor("web-fetch")),

            // Automation
            Capability(name: "Email", description: "Read, search, and send via Mail.app", icon: "envelope", color: .blue, category: .automation, isActive: isActive("email"), examplePrompt: "Show my unread emails", availableInAgentID: agentFor("email")),
            Capability(name: "Shell Commands", description: "Run safe terminal commands", icon: "terminal", color: .gray, category: .automation, isActive: isActive("shell"), examplePrompt: "List files in my Downloads folder", availableInAgentID: agentFor("shell")),
            Capability(name: "Shortcuts", description: "Run Apple Shortcuts automations", icon: "command.square", color: .pink, category: .automation, isActive: isActive("shortcuts"), examplePrompt: "Run my Morning Routine shortcut", availableInAgentID: agentFor("shortcuts")),

            // Analysis
            Capability(name: "Image Analysis", description: "Describe and analyze images locally", icon: "eye", color: .purple, category: .analysis, isActive: isActive("describeImage") || isActive("vision"), examplePrompt: "Describe this screenshot", availableInAgentID: agentFor("describeImage") ?? agentFor("vision")),
            Capability(name: "Data Analysis", description: "Query and analyze CSV/Excel data", icon: "chart.bar", color: .orange, category: .analysis, isActive: isActive("data-analysis"), examplePrompt: "Chart the sales by month", availableInAgentID: agentFor("data-analysis")),
            Capability(name: "Charts", description: "Generate charts from data", icon: "chart.pie", color: .mint, category: .analysis, isActive: isActive("charting"), examplePrompt: "Create a pie chart of expenses", availableInAgentID: agentFor("charting")),
        ]
    }
}

// MARK: - Models

private enum CapabilityCategory: String, Hashable {
    case language, calendar, documents, web, automation, analysis
}

private struct Capability: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let icon: String
    let color: Color
    let category: CapabilityCategory
    let isActive: Bool
    let examplePrompt: String
    let availableInAgentID: String?
}
