import Foundation
import GRDB
import SBBender

actor PersistenceService {
    let dbWriter: any DatabaseWriter
    private(set) var storage: GRDBStorage?

    init(path: String? = nil) throws {
        let dbPath: String
        if let path {
            dbPath = path
        } else {
            guard let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                throw PersistenceError.directoryNotFound
            }
            let dir = appSupport.appendingPathComponent("com.sbbender.app", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            dbPath = dir.appendingPathComponent("app.sqlite").path
        }

        var config = Configuration()
        config.foreignKeysEnabled = true
        dbWriter = try DatabasePool(path: dbPath, configuration: config)
        // Init GRDBStorage before migrate() to satisfy actor isolation
        storage = try GRDBStorage(path: dbPath.replacingOccurrences(of: "app.sqlite", with: "sbbender.sqlite"))
        try migrate()
    }

    init(inMemory: Bool) throws {
        dbWriter = try DatabaseQueue()
        storage = try GRDBStorage(inMemory: true)
        try migrate()
    }

    // MARK: - Migration

    private nonisolated func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_app_tables") { db in
            try db.create(table: "agent_configs", ifNotExists: true) { t in
                t.primaryKey("id", .text).notNull()
                t.column("name", .text).notNull()
                t.column("emoji", .text).notNull()
                t.column("gradientHex", .text).notNull()  // JSON array
                t.column("instructions", .text).notNull()
                t.column("providerType", .text).notNull()
                t.column("modelID", .text).notNull()
                t.column("enabledSkillIDs", .text).notNull()  // JSON array
                t.column("toolCallLimit", .integer).notNull()
                t.column("maxIterations", .integer).notNull()
                t.column("createdAt", .double).notNull()
                t.column("updatedAt", .double).notNull()
            }

            try db.create(table: "team_configs", ifNotExists: true) { t in
                t.primaryKey("id", .text).notNull()
                t.column("name", .text).notNull()
                t.column("emoji", .text).notNull()
                t.column("gradientHex", .text).notNull()
                t.column("mode", .text).notNull()
                t.column("memberIDs", .text).notNull()  // JSON array
                t.column("leaderID", .text)
                t.column("createdAt", .double).notNull()
                t.column("updatedAt", .double).notNull()
            }
        }

        migrator.registerMigration("v2_phase2_tables") { db in
            // New columns on agent_configs
            try db.alter(table: "agent_configs") { t in
                t.add(column: "knowledgeEnabled", .boolean).notNull().defaults(to: false)
                t.add(column: "knowledgeChunkingStrategy", .text).notNull().defaults(to: "paragraph")
                t.add(column: "knowledgeHybridWeight", .double).notNull().defaults(to: 0.7)
                t.add(column: "learningEnabled", .boolean).notNull().defaults(to: false)
                t.add(column: "learningMode", .text).notNull().defaults(to: "always")
                t.add(column: "customToolIDs", .text).notNull().defaults(to: "[]")
                t.add(column: "mcpServerIDs", .text).notNull().defaults(to: "[]")
                t.add(column: "systemPromptFile", .text)
            }

            // Custom tool configs
            try db.create(table: "tool_configs", ifNotExists: true) { t in
                t.primaryKey("id", .text).notNull()
                t.column("name", .text).notNull()
                t.column("toolDescription", .text).notNull()
                t.column("parameters", .text).notNull()     // JSON array
                t.column("executionType", .text).notNull()
                t.column("executionBody", .text).notNull()
                t.column("requiresConfirmation", .boolean).notNull()
                t.column("agentID", .text)
                t.column("createdAt", .double).notNull()
                t.column("updatedAt", .double).notNull()
            }

            // MCP server configs
            try db.create(table: "mcp_server_configs", ifNotExists: true) { t in
                t.primaryKey("id", .text).notNull()
                t.column("name", .text).notNull()
                t.column("command", .text).notNull()
                t.column("arguments", .text).notNull()      // JSON array
                t.column("environment", .text).notNull()     // JSON dict
                t.column("enabled", .boolean).notNull()
                t.column("createdAt", .double).notNull()
                t.column("updatedAt", .double).notNull()
            }

            // Knowledge file entries
            try db.create(table: "knowledge_files", ifNotExists: true) { t in
                t.primaryKey("id", .text).notNull()
                t.column("agentID", .text).notNull()
                t.column("fileName", .text).notNull()
                t.column("filePath", .text).notNull()
                t.column("fileType", .text).notNull()
                t.column("chunkCount", .integer).notNull()
                t.column("ingestedAt", .double).notNull()
            }
        }

        migrator.registerMigration("v3_generation_config") { db in
            try db.alter(table: "agent_configs") { t in
                t.add(column: "temperature", .double).notNull().defaults(to: 0.7)
                t.add(column: "topP", .double).notNull().defaults(to: 0.9)
                t.add(column: "maxTokens", .integer).notNull().defaults(to: 2048)
                t.add(column: "repetitionPenalty", .double).notNull().defaults(to: 1.0)
                t.add(column: "enableThinking", .boolean).notNull().defaults(to: false)
                t.add(column: "markdown", .boolean).notNull().defaults(to: true)
                t.add(column: "addDateToSystemPrompt", .boolean).notNull().defaults(to: true)
                t.add(column: "maxHistoryMessages", .integer)
            }
        }

        migrator.registerMigration("v4_attached_skills") { db in
            try db.alter(table: "agent_configs") { t in
                t.add(column: "attachedSkillIDs", .text).notNull().defaults(to: "[]")
            }
        }

        try migrator.migrate(dbWriter)
    }

    // MARK: - Agent Configs

    func loadAgents() throws -> [AgentConfig] {
        try dbWriter.read { db in
            try AgentConfig.order(Column("updatedAt").desc).fetchAll(db)
        }
    }

    func saveAgent(_ config: AgentConfig) throws {
        var config = config
        config.updatedAt = Date()
        try dbWriter.write { db in
            try config.save(db)
        }
    }

    func deleteAgent(id: String) throws {
        try dbWriter.write { db in
            _ = try AgentConfig.deleteOne(db, key: id)
        }
        // Also delete associated sessions
        if let storage {
            Task { try? await storage.deleteSession(id: id) }
        }
    }

    // MARK: - Team Configs

    func loadTeams() throws -> [TeamConfig] {
        try dbWriter.read { db in
            try TeamConfig.order(Column("updatedAt").desc).fetchAll(db)
        }
    }

    func saveTeam(_ config: TeamConfig) throws {
        var config = config
        config.updatedAt = Date()
        try dbWriter.write { db in
            try config.save(db)
        }
    }

    func deleteTeam(id: String) throws {
        try dbWriter.write { db in
            _ = try TeamConfig.deleteOne(db, key: id)
        }
    }

    // MARK: - Tool Configs

    func loadToolConfigs() throws -> [ToolConfig] {
        try dbWriter.read { db in
            try ToolConfig.order(Column("updatedAt").desc).fetchAll(db)
        }
    }

    func saveToolConfig(_ config: ToolConfig) throws {
        var config = config
        config.updatedAt = Date()
        try dbWriter.write { db in
            try config.save(db)
        }
    }

    func deleteToolConfig(id: String) throws {
        try dbWriter.write { db in
            _ = try ToolConfig.deleteOne(db, key: id)
        }
    }

    // MARK: - MCP Server Configs

    func loadMCPServerConfigs() throws -> [MCPServerConfig] {
        try dbWriter.read { db in
            try MCPServerConfig.order(Column("updatedAt").desc).fetchAll(db)
        }
    }

    func saveMCPServerConfig(_ config: MCPServerConfig) throws {
        var config = config
        config.updatedAt = Date()
        try dbWriter.write { db in
            try config.save(db)
        }
    }

    func deleteMCPServerConfig(id: String) throws {
        try dbWriter.write { db in
            _ = try MCPServerConfig.deleteOne(db, key: id)
        }
    }

    // MARK: - Knowledge Files

    func loadKnowledgeFiles(agentID: String) throws -> [KnowledgeFileEntry] {
        try dbWriter.read { db in
            try KnowledgeFileEntry
                .filter(Column("agentID") == agentID)
                .order(Column("ingestedAt").desc)
                .fetchAll(db)
        }
    }

    func saveKnowledgeFile(_ entry: KnowledgeFileEntry) throws {
        try dbWriter.write { db in
            try entry.save(db)
        }
    }

    func deleteKnowledgeFile(id: String) throws {
        try dbWriter.write { db in
            _ = try KnowledgeFileEntry.deleteOne(db, key: id)
        }
    }

    func deleteKnowledgeFiles(agentID: String) throws {
        try dbWriter.write { db in
            _ = try KnowledgeFileEntry.filter(Column("agentID") == agentID).deleteAll(db)
        }
    }

    // MARK: - Stats

    func agentCount() throws -> Int {
        try dbWriter.read { db in
            try AgentConfig.fetchCount(db)
        }
    }

    func teamCount() throws -> Int {
        try dbWriter.read { db in
            try TeamConfig.fetchCount(db)
        }
    }

    func clearAll() throws {
        try dbWriter.write { db in
            try AgentConfig.deleteAll(db)
            try TeamConfig.deleteAll(db)
            try ToolConfig.deleteAll(db)
            try MCPServerConfig.deleteAll(db)
            try KnowledgeFileEntry.deleteAll(db)
        }
    }
}

enum PersistenceError: LocalizedError {
    case directoryNotFound

    var errorDescription: String? {
        switch self {
        case .directoryNotFound: "Application Support directory not accessible"
        }
    }
}
