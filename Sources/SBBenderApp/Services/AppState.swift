import Foundation
import SwiftUI
import SBBender

#if canImport(Containerization)
import Containerization
#endif

#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
@Observable
final class AppState {
    // MARK: - User Preferences

    var showAdvancedFeatures: Bool {
        get { UserDefaults.standard.bool(forKey: "showAdvancedFeatures") }
        set { UserDefaults.standard.set(newValue, forKey: "showAdvancedFeatures") }
    }

    // MARK: - Persisted Data

    var agents: [AgentConfig] = []
    var teams: [TeamConfig] = []
    var toolConfigs: [ToolConfig] = []
    var mcpServerConfigs: [MCPServerConfig] = []
    private(set) var agentTemplates: [AgentTemplate] = []

    // MARK: - Toast Notifications

    var toasts: [ToastMessage] = []

    func addToast(_ toast: ToastMessage) {
        toasts.append(toast)
    }

    func dismissToast(id: String) {
        toasts.removeAll { $0.id == id }
    }

    // MARK: - Navigation

    var selectedSidebarItem: SidebarItem? = .dashboard

    /// Currently browsed skills.sh entry (for skill detail page).
    var browsingSkillsShEntry: SkillsShEntry?

    // MARK: - Runtime

    let modelRegistry = ModelRegistry()
    let hardwareInfo = HardwareInfo.detect()
    let curatedRegistry = CuratedRegistry()
    private(set) var persistence: PersistenceService?
    /// Direct reference to GRDBStorage for knowledge persistence (avoids actor hop in sync code).
    private var knowledgePersistence: GRDBStorage?
    private var liveAgents: [String: Agent] = [:]
    private var knowledgeIndexers: [String: DocumentIndexer] = [:]
    private var mcpManagers: [String: MCPManager] = [:]
    private var _skillsShClient: SkillsShClient?

    /// MLXProvider instances keyed by modelID so the loaded model survives agent resets.
    /// Never cleared — the model stays in memory for the lifetime of the app.
    private var mlxProviders: [String: MLXProvider] = [:]

    /// Lazily created skills.sh client.
    var skillsShClient: SkillsShClient {
        if let client = _skillsShClient { return client }
        let client = SkillsShClient()
        _skillsShClient = client
        return client
    }

    // MARK: - OpenClaw (macOS 26+)

    private(set) var containerRuntimeStatus: ContainerRuntimeStatus = .notSupported
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
            WebKitBrowserSkill(),
            ShortcutsSkill(),
            // Data
            DataAnalysisSkill(),
            ChartingSkill(),
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
        ("Data", "tablecells", ["data-analysis", "charting"]),
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
            self.knowledgePersistence = await p.storage
            self.agents = try await p.loadAgents()
            self.teams = try await p.loadTeams()
            self.toolConfigs = try await p.loadToolConfigs()
            self.mcpServerConfigs = try await p.loadMCPServerConfigs()
        } catch {
            os_log_error("AppState bootstrap failed: \(error)")
            addToast(ToastMessage(severity: .error, title: "Couldn't load your data", message: "Try restarting the app. Your data should still be safe."))
        }

        // Seed baseline skills on first launch
        do {
            try await skillsShClient.seedBaselineSkills()
        } catch {
            os_log_error("Failed to seed baseline skills: \(error)")
        }

        // Load available models from all providers
        await modelRegistry.loadAll()

        // Load agent templates from curated registry
        do {
            let entries = try await curatedRegistry.agentTemplates()
            agentTemplates = entries.map { AgentTemplate(from: $0) }
        } catch {
            os_log_error("Failed to load agent templates: \(error)")
            addToast(ToastMessage(severity: .warning, title: "Starter templates unavailable", message: "You can still create assistants manually."))
        }

        // Auto-setup container runtime for OpenClaw skills
        if #available(macOS 26, *) {
            await setupContainerRuntime()
        }
    }

    @available(macOS 26, *)
    private func setupContainerRuntime() async {
        guard let kernelURL = findVmlinuxKernel() else {
            containerRuntimeStatus = .kernelMissing
            return
        }

        do {
            #if canImport(Containerization)
            let kernel = Kernel(path: kernelURL, platform: .linuxArm)
            let manager = try await ContainerManager(
                kernel: kernel,
                initfsReference: "ghcr.io/apple/containerization/vminit:0.13.0"
            )
            let clawHub = try await getOrCreateClawHubManager()
            await clawHub.configureContainerManager(manager)
            containerRuntimeStatus = .ready
            #else
            containerRuntimeStatus = .notSupported
            #endif
        } catch {
            containerRuntimeStatus = .initFailed(error.localizedDescription)
            os_log_error("Container runtime setup failed: \(error)")
            addToast(ToastMessage(severity: .warning, title: "Advanced plugin system unavailable", message: "Your assistants will work fine without it."))
        }
    }

    // MARK: - Agent CRUD

    func saveAgent(_ config: AgentConfig) {
        if let idx = agents.firstIndex(where: { $0.id == config.id }) {
            agents[idx] = config
        } else {
            agents.insert(config, at: 0)
        }
        // Reset cached agent so it picks up new skills/tools/config on next use
        resetLiveAgent(for: config.id)
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
        // Remove from any agent that references it and reset their cached instances
        for i in agents.indices {
            if agents[i].customToolIDs.contains(config.id) {
                agents[i].customToolIDs.removeAll { $0 == config.id }
                resetLiveAgent(for: agents[i].id)
            }
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
        // Remove from any agent that references it and reset their cached instances
        for i in agents.indices {
            if agents[i].mcpServerIDs.contains(config.id) {
                agents[i].mcpServerIDs.removeAll { $0 == config.id }
                resetLiveAgent(for: agents[i].id)
            }
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
        // Inject GRDB-backed persistence so knowledge survives restarts
        if let storage = knowledgePersistence {
            Task { await indexer.setPersistence(storage) }
        }
        // Inject contextual enricher — uses Apple NLP entities + FoundationModel on macOS 26+
        let enricher = buildContextualEnricher(for: config)
        Task { await indexer.setContextualEnricher(enricher) }
        // Inject HyDE generator — generates hypothetical answers to boost recall at query time
        let hydeGen = buildHyDEGenerator(for: config)
        Task { await indexer.setHyDEGenerator(hydeGen) }
        knowledgeIndexers[config.id] = indexer
        return indexer
    }

    /// Build a ``ContextualEnricher`` appropriate for the current OS.
    ///
    /// On macOS 26+ the enricher uses `LanguageModelSession` (Apple Intelligence)
    /// to generate a 1-3 sentence situating description for each chunk.
    /// On earlier OS versions the enricher still provides Apple NLP entity
    /// extraction; it just skips the LLM-generated context description.
    private func buildContextualEnricher(for config: AgentConfig) -> ContextualEnricher {
#if canImport(FoundationModels)
        if #available(macOS 26, *) {
            return ContextualEnricher(contextGenerator: { docPreview, chunkContent in
                let prompt = """
                <document>\(docPreview)</document>
                Here is the chunk we want to situate within the whole document:
                <chunk>\(chunkContent)</chunk>
                Give a short succinct context (1-3 sentences) to situate this chunk within the overall document for improving search retrieval. Answer only with the context and nothing else.
                """
                let session = LanguageModelSession()
                let response = try? await session.respond(to: prompt)
                return response?.content.trimmingCharacters(in: .whitespacesAndNewlines)
            })
        }
#endif
        // Without FoundationModels: still provide Apple NLP entity extraction.
        return ContextualEnricher()
    }

    /// Build a HyDE generator appropriate for the current OS.
    ///
    /// On macOS 26+ uses `LanguageModelSession` (Apple Intelligence) to write a
    /// short hypothetical document passage that answers the query.  This passage is
    /// embedded at query time and searched alongside the real query for a significant
    /// recall boost (typically +20–30% on factual corpora).
    ///
    /// On earlier OS versions HyDE is skipped — returns `nil` so the indexer falls
    /// back to standard dual-signal (vector + BM25) retrieval.
    private func buildHyDEGenerator(for config: AgentConfig) -> DocumentIndexer.HyDEGenerator? {
#if canImport(FoundationModels)
        if #available(macOS 26, *) {
            return { query in
                let prompt = """
                Write a short passage (2-4 sentences) from a document that would directly answer this question: \(query)
                Write only the passage text as it might appear in the document. Be specific and factual. No preamble, no quotes.
                """
                let session = LanguageModelSession()
                let response = try? await session.respond(to: prompt)
                return response?.content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
#endif
        return nil
    }

    func resetKnowledgeIndexer(for agentID: String) {
        knowledgeIndexers.removeValue(forKey: agentID)
    }

    /// Re-ingest knowledge from persisted file paths when the indexer is empty.
    /// Tries to load from GRDB persistence first (instant), falls back to file re-ingestion.
    /// Returns true if rehydration was performed.
    @discardableResult
    func rehydrateKnowledge(for config: AgentConfig) async -> Bool {
        guard config.knowledgeEnabled else { return false }

        let indexer = getOrCreateKnowledgeIndexer(for: config)
        // Ensure persistence is injected before we try to load from it
        if let storage = knowledgePersistence {
            await indexer.setPersistence(storage)
        }
        let currentChunks = await indexer.chunkCount
        guard currentChunks == 0 else { return false }

        // Fast path: load pre-built index from GRDB persistence
        do {
            let loaded = try await indexer.loadFromPersistence(agentID: config.id)
            if loaded { return true }
        } catch {
            os_log_error("Persistence load failed for agent \(config.id), falling back to file re-ingestion: \(error)")
        }

        // Slow path: re-ingest from original files
        guard let files = try? await persistence?.loadKnowledgeFiles(agentID: config.id),
              !files.isEmpty else { return false }

        let loader = DocumentLoader()

        for file in files {
            guard FileManager.default.fileExists(atPath: file.filePath) else { continue }

            do {
                let ext = file.fileType.lowercased()
                var docs: [(content: String, title: String, metadata: [String: String])] = []

                switch ext {
                case "folder":
                    docs = try loader.loadDirectory(at: file.filePath)
                case "pdf":
                    #if canImport(PDFKit)
                    docs = try loader.loadPDF(at: file.filePath)
                    #endif
                case "pptx":
                    docs = try loader.loadPPTX(at: file.filePath)
                default:
                    let result = try loader.loadText(at: file.filePath)
                    docs = [(content: result.content, title: result.title, metadata: [:])]
                }

                // Enrich metadata with document date and family for versioning support.
                let fileURL = URL(fileURLWithPath: file.filePath)
                let firstPageText = docs.first.map { String($0.content.prefix(1_000)) } ?? ""
                let docDate = DocumentLoader.extractDocumentDate(
                    from: file.fileName,
                    firstPageText: firstPageText,
                    fileURL: fileURL
                )
                let docFamily = DocumentLoader.extractDocumentFamily(from: file.fileName)

                for doc in docs {
                    var enrichedMeta = doc.metadata
                    if let date = docDate {
                        enrichedMeta["documentDate"] = ISO8601DateFormatter().string(from: date)
                    }
                    enrichedMeta["documentFamily"] = docFamily
                    try await indexer.ingest(content: doc.content, title: doc.title, metadata: enrichedMeta)
                }
            } catch {
                os_log_error("Rehydration failed for \(file.fileName): \(error)")
                addToast(ToastMessage(severity: .warning, title: "Couldn't read \(file.fileName)", message: "Try a different file format (PDF, TXT, or Markdown)."))
            }
        }

        do {
            try await indexer.buildIndex()
            // Persist the rebuilt index for next launch
            await indexer.persistIndex(agentID: config.id)
        } catch {
            os_log_error("Rehydration index build failed: \(error)")
        }

        return true
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

        let agent = AgentFactory.createAgent(
            from: config,
            nativeTools: nativeTools,
            skills: skills,
            customTools: customTools,
            storage: storage,
            knowledge: knowledge,
            learning: learning,
            mlxProviderCache: &mlxProviders
        )

        // Connect MCP servers after agent creation
        if !config.mcpServerIDs.isEmpty {
            do {
                if let manager = try await getOrCreateMCPManager(for: config) {
                    let tools = await manager.allTools()
                    for tool in tools {
                        await agent.addTool(tool)
                    }
                }
            } catch {
                os_log_error("MCP connection failed for agent \(config.name): \(error)")
                addToast(ToastMessage(severity: .error, title: "A plugin connection failed", message: "Your assistant will work without it. Check Settings to reconnect."))
            }
        }

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
        var pool = nativeSkills

        // 1. If enabledSkillIDs is set, restrict to those native tools
        if !config.enabledSkillIDs.isEmpty {
            let allowed = Set(config.enabledSkillIDs)
            pool = pool.filter { allowed.contains($0.id) }
        }

        // 2. If attached SKILL.md skills declare allowedTools, further restrict
        let restrictions = skills.compactMap(\.allowedTools)
        if !restrictions.isEmpty {
            let allowedIDs = Set(restrictions.flatMap { $0 })
            pool = pool.filter { allowedIDs.contains($0.id) }
        }

        return pool
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

    // MARK: - Bundle Apply

    /// Apply a curated bundle: creates MCP server configs and an agent in one step.
    func applyBundle(_ bundle: BundleEntry) async {
        // 1. Resolve MCP servers from the curated registry
        var mcpIDs: [String] = []
        if !bundle.mcpServers.isEmpty {
            do {
                let allServers = try await curatedRegistry.mcpServers()
                for serverID in bundle.mcpServers {
                    guard let entry = allServers.first(where: { $0.id == serverID }) else { continue }
                    // Check if we already have this server configured
                    if let existing = mcpServerConfigs.first(where: { $0.name == entry.name }) {
                        mcpIDs.append(existing.id)
                    } else {
                        let config = MCPServerConfig(
                            name: entry.name,
                            command: entry.command,
                            arguments: entry.arguments,
                            environment: entry.environment ?? [:]
                        )
                        saveMCPServerConfig(config)
                        mcpIDs.append(config.id)
                    }
                }
            } catch {
                os_log_error("Failed to load MCP servers for bundle: \(error)")
            }
        }

        // 2. Determine provider from model ID
        let providerType: String
        if bundle.model.hasPrefix("mlx-community/") {
            providerType = "mlx"
        } else if bundle.model.contains(":") {
            providerType = "ollama"
        } else {
            providerType = "mlx"
        }

        // 3. Create the agent
        let agentConfig = AgentConfig(
            name: bundle.name,
            instructions: "You are a helpful assistant configured with the \(bundle.name) bundle.",
            providerType: providerType,
            modelID: bundle.model,
            enabledSkillIDs: bundle.nativeTools,
            mcpServerIDs: mcpIDs,
            enableThinking: true
        )
        saveAgent(agentConfig)
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

    // MARK: - Title Generation

    /// Generate a short conversational title using the agent's already-loaded model.
    /// For MLX agents this is free — the model is already in GPU memory.
    /// For cloud providers a lightweight call is made. Falls back to first 50 chars on failure.
    func generateTitle(for config: AgentConfig, userMessage: String, assistantReply: String) async -> String {
        let fallback = String(userMessage.prefix(50))
        let providerType = ProviderType(rawValue: config.providerType) ?? .mlx

        let provider: any ModelProvider
        if providerType == .mlx {
            // Never trigger a fresh model load just for a title — only use if already cached.
            guard let existing = mlxProviders[config.modelID] else { return fallback }
            provider = existing
        } else {
            provider = AgentFactory.createProvider(type: providerType, modelID: config.modelID)
        }

        let titleConfig = AgentConfiguration(
            name: "TitleGen",
            instructions: "You generate ultra-short chat titles. Reply with ONLY 3–5 words — no punctuation, no quotes, no explanation.",
            generationConfig: GenerationConfig(maxTokens: 15, temperature: 0.3)
        )
        // No storage — this agent is ephemeral
        let titleAgent = Agent(configuration: titleConfig, model: provider)

        let userPreview = String(userMessage.prefix(300))
        let replyPreview = assistantReply.isEmpty ? "" : " Assistant: \(String(assistantReply.prefix(200)))"
        let prompt = "Conversation — User: \(userPreview)\(replyPreview)\n\nTitle:"

        let result = try? await titleAgent.run(prompt)
        let generated = result?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return generated.isEmpty ? fallback : generated
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
