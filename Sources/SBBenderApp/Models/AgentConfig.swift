import Foundation
import GRDB

struct AgentConfig: Codable, Identifiable, Sendable, Equatable {
    let id: String
    var name: String
    var emoji: String
    var gradientHex: [String]
    var instructions: String
    var providerType: String
    var modelID: String
    var enabledSkillIDs: [String]
    var toolCallLimit: Int
    var maxIterations: Int
    // Phase 2: Knowledge
    var knowledgeEnabled: Bool
    var knowledgeChunkingStrategy: String   // "fixedSize", "sentence", "paragraph"
    var knowledgeHybridWeight: Float
    // Phase 2: Learning
    var learningEnabled: Bool
    var learningMode: String               // "always", "agentic"
    // Phase 2: Custom Tools & MCP
    var customToolIDs: [String]
    var mcpServerIDs: [String]
    // Phase 2: SKILL.md instruction skills
    var attachedSkillIDs: [String]
    // Phase 2: System prompt file
    var systemPromptFile: String?
    // Phase 3: Generation config
    var temperature: Float
    var topP: Float
    var maxTokens: Int
    var repetitionPenalty: Float
    var enableThinking: Bool
    var markdown: Bool
    var addDateToSystemPrompt: Bool
    var maxHistoryMessages: Int?
    // Timestamps
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String = "New Agent",
        emoji: String = "🤖",
        gradientHex: [String] = ["#0077B6", "#00B4D8"],
        instructions: String = "You are a helpful assistant.",
        providerType: String = "mlx",
        modelID: String = "mlx-community/Qwen3-4B-4bit",
        enabledSkillIDs: [String] = [],
        toolCallLimit: Int = 25,
        maxIterations: Int = 10,
        knowledgeEnabled: Bool = false,
        knowledgeChunkingStrategy: String = "paragraph",
        knowledgeHybridWeight: Float = 0.7,
        learningEnabled: Bool = false,
        learningMode: String = "always",
        customToolIDs: [String] = [],
        mcpServerIDs: [String] = [],
        attachedSkillIDs: [String] = [],
        systemPromptFile: String? = nil,
        temperature: Float = 0.7,
        topP: Float = 0.9,
        maxTokens: Int = 2048,
        repetitionPenalty: Float = 1.0,
        enableThinking: Bool = false,
        markdown: Bool = true,
        addDateToSystemPrompt: Bool = true,
        maxHistoryMessages: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.gradientHex = gradientHex
        self.instructions = instructions
        self.providerType = providerType
        self.modelID = modelID
        self.enabledSkillIDs = enabledSkillIDs
        self.toolCallLimit = toolCallLimit
        self.maxIterations = maxIterations
        self.knowledgeEnabled = knowledgeEnabled
        self.knowledgeChunkingStrategy = knowledgeChunkingStrategy
        self.knowledgeHybridWeight = knowledgeHybridWeight
        self.learningEnabled = learningEnabled
        self.learningMode = learningMode
        self.customToolIDs = customToolIDs
        self.mcpServerIDs = mcpServerIDs
        self.attachedSkillIDs = attachedSkillIDs
        self.systemPromptFile = systemPromptFile
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.repetitionPenalty = repetitionPenalty
        self.enableThinking = enableThinking
        self.markdown = markdown
        self.addDateToSystemPrompt = addDateToSystemPrompt
        self.maxHistoryMessages = maxHistoryMessages
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - GRDB Record

extension AgentConfig: FetchableRecord, PersistableRecord {
    static let databaseTableName = "agent_configs"

    enum Columns: String, ColumnExpression {
        case id, name, emoji, gradientHex, instructions
        case providerType, modelID, enabledSkillIDs
        case toolCallLimit, maxIterations
        case knowledgeEnabled, knowledgeChunkingStrategy, knowledgeHybridWeight
        case learningEnabled, learningMode
        case customToolIDs, mcpServerIDs, attachedSkillIDs, systemPromptFile
        case temperature, topP, maxTokens, repetitionPenalty
        case enableThinking, markdown, addDateToSystemPrompt, maxHistoryMessages
        case createdAt, updatedAt
    }
}
