import Foundation

/// Configuration for an Agent.
public struct AgentConfiguration: Sendable {
    public var name: String
    public var instructions: String
    public var systemPrompt: String?
    public var generationConfig: GenerationConfig
    public var toolCallLimit: Int
    public var maxIterations: Int
    public var addDateToSystemPrompt: Bool
    public var markdown: Bool
    public var maxHistoryMessages: Int?
    public var maxHistoryToolResults: Int?

    public init(
        name: String = "Agent",
        instructions: String = "",
        systemPrompt: String? = nil,
        generationConfig: GenerationConfig = GenerationConfig(),
        toolCallLimit: Int = 25,
        maxIterations: Int = 10,
        addDateToSystemPrompt: Bool = true,
        markdown: Bool = true,
        maxHistoryMessages: Int? = nil,
        maxHistoryToolResults: Int? = nil
    ) {
        self.name = name
        self.instructions = instructions
        self.systemPrompt = systemPrompt
        self.generationConfig = generationConfig
        self.toolCallLimit = toolCallLimit
        self.maxIterations = maxIterations
        self.addDateToSystemPrompt = addDateToSystemPrompt
        self.markdown = markdown
        self.maxHistoryMessages = maxHistoryMessages
        self.maxHistoryToolResults = maxHistoryToolResults
    }

    /// Build the full system prompt from configuration.
    public func buildSystemPrompt(
        nativeTools: [any NativeTool] = [],
        skills: [Skill] = [],
        knowledgeContext: String? = nil,
        learningContext: String? = nil
    ) -> String {
        var parts: [String] = []

        if let custom = systemPrompt {
            parts.append(custom)
        } else {
            parts.append("You are \(name), an AI assistant.")
        }

        if !instructions.isEmpty {
            parts.append(instructions)
        }

        if addDateToSystemPrompt {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            parts.append("Current date: \(formatter.string(from: Date()))")
        }

        if markdown {
            parts.append("Use markdown formatting in your responses where appropriate.")
        }

        // Inject skill instructions (SKILL.md body)
        for skill in skills {
            var skillSection = "## Skill: \(skill.name)\n\(skill.instructions)"
            if !skill.scripts.isEmpty {
                let scriptList = skill.scripts.map { "- \($0.name) (\($0.language.rawValue)): \($0.localPath.path)" }
                skillSection += "\n\nAvailable scripts:\n" + scriptList.joined(separator: "\n")
            }
            parts.append(skillSection)
        }

        if !nativeTools.isEmpty {
            let toolList = nativeTools.map { "- \($0.name): \($0.description)" }.joined(separator: "\n")
            parts.append("You have the following native tools available:\n\(toolList)")
        }

        if let knowledge = knowledgeContext, !knowledge.isEmpty {
            parts.append("## Relevant Knowledge\n\(knowledge)")
        }

        if let learning = learningContext, !learning.isEmpty {
            parts.append("## Memory\n\(learning)")
        }

        return parts.joined(separator: "\n\n")
    }
}
