import Foundation
import SwiftUI
import SBBender

@MainActor
@Observable
final class AppState {
    // MARK: - Persisted Data

    var agents: [AgentConfig] = []
    var teams: [TeamConfig] = []
    var toolConfigs: [ToolConfig] = []
    var mcpServerConfigs: [MCPServerConfig] = []

    // MARK: - Navigation

    var selectedSidebarItem: SidebarItem? = .agents

    /// Currently browsed skills.sh entry (for skill detail page).
    var browsingSkillsShEntry: SkillsShEntry?

    // MARK: - Runtime

    let modelRegistry = ModelRegistry()
    let hardwareInfo = HardwareInfo.detect()
    let curatedRegistry = CuratedRegistry()
    private(set) var persistence: PersistenceService?
    private var liveAgents: [String: Agent] = [:]
    private var knowledgeIndexers: [String: DocumentIndexer] = [:]
    private var mcpManagers: [String: MCPManager] = [:]
    private var _skillsShClient: SkillsShClient?

    /// Lazily created skills.sh client.
    var skillsShClient: SkillsShClient {
        if let client = _skillsShClient { return client }
        let client = SkillsShClient()
        _skillsShClient = client
        return client
    }

    // MARK: - OpenClaw (macOS 26+)

    private var _clawHubManager: (any Sendable)?

    @available(macOS 26, *)
    var clawHubManager: ClawHubManager? {
        _clawHubManager as? ClawHubManager
    }

    // MARK: - Native Skills (all 18)

    let nativeSkills: [any NativeTool] = {
        var skills: [any NativeTool] = [
            // Language
            LanguageDetectionSkill(),
            SentimentSkill(),
            EntityExtractionSkill(),
            TokenizationSkill(),
            EmbeddingDistanceSkill(),
            // System
            ShellSkill(allowedCommands: ["ls", "cat", "echo", "date", "pwd", "which", "find", "wc", "grep", "head", "tail", "sort", "uniq", "curl", "jq"]),
            AppleScriptSkill(),
            WebFetchSkill(),
            BrowserSkill(),
            ShortcutsSkill(),
            // Communication
            EmailSkill(),
        ]
        #if canImport(EventKit)
        // Calendar
        skills.append(CalendarSkill())
        skills.append(RemindersSkill())
        #endif
        #if canImport(ScreenCaptureKit)
        if #available(macOS 14, *) {
            skills.append(ScreenCaptureSkill())
        }
        #endif
        #if canImport(Speech)
        skills.append(TranscriptionSkill())
        #endif
        #if arch(arm64)
        skills.append(VisionSkill())
        #endif
        if #available(macOS 26, *) {
            skills.append(TranslationSkill())
        }
        return skills
    }()

    /// Skill categories for grouped display in the UI.
    static let skillCategories: [(name: String, icon: String, skillIDs: [String])] = [
        ("Language", "textformat", ["language-detection", "sentiment", "entity-extraction", "tokenization", "embedding-distance"]),
        ("System", "terminal", ["shell", "applescript", "web-fetch", "browser", "shortcuts"]),
        ("Communication", "envelope", ["email"]),
        ("Media", "waveform", ["transcription", "screencapture", "vision", "translation"]),
        ("Calendar", "calendar", ["calendar", "reminders"]),
    ]

    /// Returns all native skills with availability status, cached after first check.
    private var _skillAvailabilityCache: [(skill: any NativeTool, available: Bool)]?

    func availableSkills() async -> [(skill: any NativeTool, available: Bool)] {
        if let cached = _skillAvailabilityCache { return cached }
        var result: [(skill: any NativeTool, available: Bool)] = []
        for skill in nativeSkills {
            let available = await skill.isAvailable
            result.append((skill: skill, available: available))
        }
        _skillAvailabilityCache = result
        return result
    }

    // MARK: - Lifecycle

    func bootstrap() async {
        do {
            let p = try PersistenceService()
            self.persistence = p
            self.agents = try await p.loadAgents()
            self.teams = try await p.loadTeams()
            self.toolConfigs = try await p.loadToolConfigs()
            self.mcpServerConfigs = try await p.loadMCPServerConfigs()
        } catch {
            os_log_error("AppState bootstrap failed: \(error)")
        }

        // Seed baseline skills on first launch
        do {
            try await skillsShClient.seedBaselineSkills()
        } catch {
            os_log_error("Failed to seed baseline skills: \(error)")
        }

        // Load available models from all providers
        await modelRegistry.loadAll()
    }

    // MARK: - Agent CRUD

    func saveAgent(_ config: AgentConfig) {
        if let idx = agents.firstIndex(where: { $0.id == config.id }) {
            agents[idx] = config
        } else {
            agents.insert(config, at: 0)
        }
        Task { try? await persistence?.saveAgent(config) }
    }

    func deleteAgent(_ config: AgentConfig) {
        agents.removeAll { $0.id == config.id }
        liveAgents.removeValue(forKey: config.id)
        knowledgeIndexers.removeValue(forKey: config.id)
        // Disconnect MCP manager for this agent
        if let mgr = mcpManagers.removeValue(forKey: config.id) {
            Task { await mgr.disconnectAll() }
        }
        for i in teams.indices {
            teams[i].memberIDs.removeAll { $0 == config.id }
            if teams[i].leaderID == config.id { teams[i].leaderID = nil }
        }
        Task { try? await persistence?.deleteAgent(id: config.id) }
    }

    // MARK: - Team CRUD

    func saveTeam(_ config: TeamConfig) {
        if let idx = teams.firstIndex(where: { $0.id == config.id }) {
            teams[idx] = config
        } else {
            teams.insert(config, at: 0)
        }
        Task { try? await persistence?.saveTeam(config) }
    }

    func deleteTeam(_ config: TeamConfig) {
        teams.removeAll { $0.id == config.id }
        Task { try? await persistence?.deleteTeam(id: config.id) }
    }

    // MARK: - Tool Config CRUD

    func saveToolConfig(_ config: ToolConfig) {
        if let idx = toolConfigs.firstIndex(where: { $0.id == config.id }) {
            toolConfigs[idx] = config
        } else {
            toolConfigs.insert(config, at: 0)
        }
        Task { try? await persistence?.saveToolConfig(config) }
    }

    func deleteToolConfig(_ config: ToolConfig) {
        toolConfigs.removeAll { $0.id == config.id }
        // Remove from any agent that references it
        for i in agents.indices {
            agents[i].customToolIDs.removeAll { $0 == config.id }
        }
        Task { try? await persistence?.deleteToolConfig(id: config.id) }
    }

    func toolConfigs(for agentID: String) -> [ToolConfig] {
        let config = agentConfig(for: agentID)
        let ids = Set(config?.customToolIDs ?? [])
        return toolConfigs.filter { ids.contains($0.id) || $0.agentID == agentID }
    }

    // MARK: - MCP Server Config CRUD

    func saveMCPServerConfig(_ config: MCPServerConfig) {
        if let idx = mcpServerConfigs.firstIndex(where: { $0.id == config.id }) {
            mcpServerConfigs[idx] = config
        } else {
            mcpServerConfigs.insert(config, at: 0)
        }
        Task { try? await persistence?.saveMCPServerConfig(config) }
    }

    func deleteMCPServerConfig(_ config: MCPServerConfig) {
        mcpServerConfigs.removeAll { $0.id == config.id }
        // Remove from any agent that references it
        for i in agents.indices {
            agents[i].mcpServerIDs.removeAll { $0 == config.id }
        }
        Task { try? await persistence?.deleteMCPServerConfig(id: config.id) }
    }

    func mcpConfigs(for agentID: String) -> [MCPServerConfig] {
        let config = agentConfig(for: agentID)
        let ids = Set(config?.mcpServerIDs ?? [])
        return mcpServerConfigs.filter { ids.contains($0.id) }
    }

    // MARK: - Knowledge Indexer Lifecycle

    func getOrCreateKnowledgeIndexer(for config: AgentConfig) -> DocumentIndexer {
        if let existing = knowledgeIndexers[config.id] {
            return existing
        }
        let strategy = AgentFactory.chunkingStrategy(from: config)
        let indexerConfig = DocumentIndexer.Config(
            chunkingStrategy: strategy,
            hybridWeight: config.knowledgeHybridWeight
        )
        let indexer = DocumentIndexer(config: indexerConfig)
        knowledgeIndexers[config.id] = indexer
        return indexer
    }

    func resetKnowledgeIndexer(for agentID: String) {
        knowledgeIndexers.removeValue(forKey: agentID)
    }

    // MARK: - MCP Manager Lifecycle

    func getOrCreateMCPManager(for config: AgentConfig) async throws -> MCPManager? {
        guard !config.mcpServerIDs.isEmpty else { return nil }

        if let existing = mcpManagers[config.id] {
            return existing
        }

        let manager = MCPManager()
        let serverConfigs = mcpConfigs(for: config.id)

        for server in serverConfigs where server.enabled {
            try await manager.connect(
                name: server.name,
                command: server.command,
                args: server.arguments,
                environment: server.environment.isEmpty ? nil : server.environment
            )
        }

        mcpManagers[config.id] = manager
        return manager
    }

    // MARK: - Agent Runtime

    func getOrCreateLiveAgent(for config: AgentConfig) async -> Agent {
        if let existing = liveAgents[config.id] {
            return existing
        }

        let skills = await skillsForConfig(config)
        let nativeTools = nativeToolsForConfig(config, skills: skills)
        let storage = await persistence?.storage

        // Build custom tools
        let customTools = toolConfigs(for: config.id).map { $0.toLiveTool() }

        // Knowledge
        var knowledge: (any KnowledgeSource)?
        if config.knowledgeEnabled {
            knowledge = getOrCreateKnowledgeIndexer(for: config)
        }

        // Learning
        var learning: LearningEngine?
        if config.learningEnabled, let storage {
            let mode: LearningMode = config.learningMode == "agentic" ? .agentic : .always
            learning = LearningEngine(
                storage: storage,
                userID: config.id,
                userProfile: LearningStoreConfig(enabled: true, mode: mode),
                userMemory: LearningStoreConfig(enabled: true, mode: mode)
            )
        }

        // MCP
        var mcpManager: MCPManager?
        do {
            mcpManager = try await getOrCreateMCPManager(for: config)
        } catch {
            os_log_error("MCP connection failed for agent \(config.name): \(error)")
        }

        let agent = AgentFactory.createAgent(
            from: config,
            nativeTools: nativeTools,
            skills: skills,
            customTools: customTools,
            storage: storage,
            knowledge: knowledge,
            learning: learning,
            mcpManager: mcpManager
        )
        liveAgents[config.id] = agent
        return agent
    }

    func resetLiveAgent(for id: String) {
        liveAgents.removeValue(forKey: id)
        // Also reset MCP manager so it reconnects with fresh config
        if let mgr = mcpManagers.removeValue(forKey: id) {
            Task { await mgr.disconnectAll() }
        }
    }

    // MARK: - Tools & Skills

    func nativeToolsForConfig(_ config: AgentConfig, skills: [Skill] = []) -> [any NativeTool] {
        // Derive allowed tools from attached SKILL.md skills
        // If any skill has allowedTools, restrict to the union of those
        // If no skills or none restrict, enable all native tools
        let restrictions = skills.compactMap(\.allowedTools)
        if restrictions.isEmpty {
            return nativeSkills
        }
        let allowedIDs = Set(restrictions.flatMap { $0 })
        return nativeSkills.filter { allowedIDs.contains($0.id) }
    }

    func skillsForConfig(_ config: AgentConfig) async -> [Skill] {
        guard !config.attachedSkillIDs.isEmpty else { return [] }
        do {
            let installed = try await skillsShClient.listInstalled()
            let ids = Set(config.attachedSkillIDs)
            return installed.filter { ids.contains($0.id) }
        } catch {
            os_log_error("Failed to load installed skills: \(error)")
            return []
        }
    }

    func agentConfig(for id: String) -> AgentConfig? {
        agents.first { $0.id == id }
    }

    func teamConfig(for id: String) -> TeamConfig? {
        teams.first { $0.id == id }
    }

    // MARK: - OpenClaw Manager

    @available(macOS 26, *)
    func getOrCreateClawHubManager() async throws -> ClawHubManager {
        if let existing = _clawHubManager as? ClawHubManager {
            return existing
        }

        let imageManager = ContainerImageManager()
        let pool = ContainerPool(imageManager: imageManager)
        let manager = ClawHubManager(
            pool: pool,
            permissionDelegate: AppPermissionDelegate()
        )
        _clawHubManager = manager
        return manager
    }

    // MARK: - Logging

    private func os_log_error(_ msg: String) {
        #if DEBUG
        print("[AppState] \(msg)")
        #endif
    }
}

// MARK: - App Permission Delegate

/// Interactive permission delegate that auto-approves for now.
/// In a future version, this will show sheets for user approval.
@available(macOS 26, *)
struct AppPermissionDelegate: SkillPermissionDelegate {
    func approveEnvironmentVariables(
        skill: String,
        requested: [String]
    ) async -> [String: String] {
        // Auto-approve from environment
        var approved: [String: String] = [:]
        for key in requested {
            if let value = ProcessInfo.processInfo.environment[key] {
                approved[key] = value
            }
        }
        return approved
    }

    func approveNetworkAccess(skill: String) async -> Bool {
        true // Allow network access by default
    }
}
