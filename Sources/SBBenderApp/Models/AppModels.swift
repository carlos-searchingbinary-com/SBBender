import Foundation
import SwiftUI
import SBBender
import GRDB

// MARK: - Sidebar Navigation

enum SidebarItem: Hashable {
    case agents
    case agentChat(String)
    case teams
    case teamWorkspace(String)
    case marketplace
    case skillDetail(String)       // skills.sh skill ID
    case nativeSkillDetail(String) // native skill ID
    case skillLab
    case toolManager
    case mcpServers
    case settings
}

// MARK: - Provider Type

enum ProviderType: String, CaseIterable, Identifiable, Codable {
    case mlx = "mlx"
    case foundation = "foundation"
    case ollama = "ollama"
    case anthropic = "anthropic"
    case openai = "openai"
    case groq = "groq"
    case deepinfra = "deepinfra"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mlx: "MLX"
        case .foundation: "Apple Intelligence"
        case .ollama: "Ollama"
        case .anthropic: "Anthropic"
        case .openai: "OpenAI"
        case .groq: "Groq"
        case .deepinfra: "DeepInfra"
        }
    }

    var defaultModelID: String {
        switch self {
        case .mlx: "mlx-community/Qwen3-4B-4bit"
        case .foundation: "apple-intelligence"
        case .ollama: "qwen3:4b"
        case .anthropic: "claude-sonnet-4-5-20250929"
        case .openai: "gpt-4.1"
        case .groq: "llama-3.3-70b-versatile"
        case .deepinfra: "meta-llama/Llama-4-Scout-17B-16E-Instruct"
        }
    }

    var icon: String {
        switch self {
        case .mlx: "cpu"
        case .foundation: "apple.logo"
        case .ollama: "server.rack"
        case .anthropic: "cloud"
        case .openai: "cloud.fill"
        case .groq: "bolt.fill"
        case .deepinfra: "cloud.bolt"
        }
    }

    /// Whether this provider requires an API key.
    var requiresAPIKey: Bool {
        switch self {
        case .mlx, .ollama, .foundation: false
        case .anthropic, .openai, .groq, .deepinfra: true
        }
    }

    /// Whether this provider is a cloud (non-local) provider.
    var isCloud: Bool {
        switch self {
        case .mlx, .ollama, .foundation: false
        case .anthropic, .openai, .groq, .deepinfra: true
        }
    }

    /// Whether this provider is available on the current system.
    var isAvailableOnSystem: Bool {
        switch self {
        case .foundation:
            if #available(macOS 26, *) { return true }
            return false
        default:
            return true
        }
    }
}

// MARK: - Activity Events

struct ActivityEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let kind: Kind
    let agentName: String?

    enum Kind {
        case thinking
        case modelRequest(provider: String, model: String)
        case toolCallStarted(name: String)
        case toolCallCompleted(name: String, chars: Int)
        case toolCallError(name: String, error: String)
        case streaming(tokens: Int)
        case completed(latency: TimeInterval, toolCalls: Int)
        case error(String)
    }

    var icon: String {
        switch kind {
        case .thinking: "brain"
        case .modelRequest: "arrow.up.circle"
        case .toolCallStarted: "wrench.and.screwdriver"
        case .toolCallCompleted: "checkmark.circle.fill"
        case .toolCallError: "xmark.circle.fill"
        case .streaming: "text.cursor"
        case .completed: "flag.checkered"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch kind {
        case .thinking: .purple
        case .modelRequest: .cyan
        case .toolCallStarted: .orange
        case .toolCallCompleted: .green
        case .toolCallError: .red
        case .streaming: .blue
        case .completed: .green
        case .error: .red
        }
    }

    var description: String {
        switch kind {
        case .thinking: return "Thinking..."
        case .modelRequest(let provider, let model):
            let shortModel = model.components(separatedBy: "/").last ?? model
            return "\(provider) \u{2022} \(shortModel)"
        case .toolCallStarted(let name): return "Calling \(name)..."
        case .toolCallCompleted(let name, let chars): return "\(name) returned \(chars) chars"
        case .toolCallError(let name, let error): return "\(name) failed: \(error)"
        case .streaming(let tokens): return "Streaming (\(tokens) tokens)"
        case .completed(let latency, let toolCalls):
            let l = String(format: "%.1f", latency)
            return toolCalls > 0 ? "Done in \(l)s (\(toolCalls) tool calls)" : "Done in \(l)s"
        case .error(let msg): return msg
        }
    }

    init(kind: Kind, agentName: String? = nil) {
        self.timestamp = Date()
        self.kind = kind
        self.agentName = agentName
    }
}

// MARK: - Agent Status

enum AgentStatus {
    case idle, thinking, working, streaming, error, done
}

// MARK: - Chat Message

struct ChatMessage: Identifiable {
    let id: String
    let role: String
    let content: String
    let toolCalls: [ToolCall]?
    let timestamp: Date

    init(
        id: String = UUID().uuidString,
        role: String,
        content: String,
        toolCalls: [SBBender.ToolCall]? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.timestamp = Date()
    }
}

// MARK: - Gradient Presets

struct GradientPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let hex: [String]

    static let all: [GradientPreset] = [
        GradientPreset(id: "ocean", name: "Ocean", hex: ["#0077B6", "#00B4D8"]),
        GradientPreset(id: "sunset", name: "Sunset", hex: ["#FF6B6B", "#FFA500"]),
        GradientPreset(id: "forest", name: "Forest", hex: ["#2D6A4F", "#74C69D"]),
        GradientPreset(id: "purple", name: "Purple", hex: ["#7209B7", "#B5179E"]),
        GradientPreset(id: "midnight", name: "Midnight", hex: ["#1B1B3A", "#4A4E69"]),
        GradientPreset(id: "fire", name: "Fire", hex: ["#D00000", "#FFBA08"]),
        GradientPreset(id: "arctic", name: "Arctic", hex: ["#48CAE4", "#CAF0F8"]),
        GradientPreset(id: "gold", name: "Gold", hex: ["#B8860B", "#FFD700"]),
        GradientPreset(id: "rose", name: "Rose", hex: ["#FF006E", "#FB5607"]),
        GradientPreset(id: "mint", name: "Mint", hex: ["#06D6A0", "#118AB2"]),
        GradientPreset(id: "slate", name: "Slate", hex: ["#2B2D42", "#8D99AE"]),
        GradientPreset(id: "coral", name: "Coral", hex: ["#F72585", "#7209B7"]),
    ]
}

// MARK: - Emoji Categories

struct EmojiCategory: Identifiable {
    let id: String
    let name: String
    let emojis: [String]

    static let all: [EmojiCategory] = [
        EmojiCategory(id: "robots", name: "Robots", emojis: ["🤖", "🦾", "🔮", "⚡", "🛸", "🧿"]),
        EmojiCategory(id: "people", name: "People", emojis: ["🧙", "🥷", "🦸", "👨‍🔬", "👩‍💻", "🧑‍🎨"]),
        EmojiCategory(id: "animals", name: "Animals", emojis: ["🦊", "🐙", "🦉", "🐝", "🦈", "🐉"]),
        EmojiCategory(id: "objects", name: "Objects", emojis: ["🧠", "💎", "🔬", "🎯", "🚀", "⚙️"]),
        EmojiCategory(id: "nature", name: "Nature", emojis: ["🌟", "🔥", "🌊", "⛈️", "🌈", "🌸"]),
    ]
}

// MARK: - Knowledge File Entry

struct KnowledgeFileEntry: Codable, Identifiable, Sendable, Equatable {
    let id: String
    var agentID: String
    var fileName: String
    var filePath: String
    var fileType: String       // "txt", "pdf", "md", "pptx", "folder"
    var chunkCount: Int
    var ingestedAt: Date

    init(
        id: String = UUID().uuidString,
        agentID: String,
        fileName: String,
        filePath: String,
        fileType: String,
        chunkCount: Int = 0
    ) {
        self.id = id
        self.agentID = agentID
        self.fileName = fileName
        self.filePath = filePath
        self.fileType = fileType
        self.chunkCount = chunkCount
        self.ingestedAt = Date()
    }
}

// MARK: - Knowledge File GRDB Record

extension KnowledgeFileEntry: FetchableRecord, PersistableRecord {
    static let databaseTableName = "knowledge_files"

    enum Columns: String, ColumnExpression {
        case id, agentID, fileName, filePath, fileType, chunkCount, ingestedAt
    }
}

// MARK: - Agent Template

struct AgentTemplate: Identifiable {
    let id: String
    let name: String
    let emoji: String
    let gradientHex: [String]
    let description: String
    let skillIDs: [String]
    let instructions: String
    let temperature: Float
    let enableThinking: Bool
    let knowledgeEnabled: Bool
    let learningEnabled: Bool

    init(
        id: String,
        name: String,
        emoji: String,
        gradientHex: [String],
        description: String,
        skillIDs: [String],
        instructions: String,
        temperature: Float,
        enableThinking: Bool,
        knowledgeEnabled: Bool,
        learningEnabled: Bool
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.gradientHex = gradientHex
        self.description = description
        self.skillIDs = skillIDs
        self.instructions = instructions
        self.temperature = temperature
        self.enableThinking = enableThinking
        self.knowledgeEnabled = knowledgeEnabled
        self.learningEnabled = learningEnabled
    }

    init(from entry: AgentTemplateEntry) {
        self.id = entry.id
        self.name = entry.name
        self.emoji = entry.emoji
        self.gradientHex = entry.gradientHex
        self.description = entry.description
        self.skillIDs = entry.skillIDs
        self.instructions = entry.instructions
        self.temperature = entry.temperature
        self.enableThinking = entry.enableThinking
        self.knowledgeEnabled = entry.knowledgeEnabled
        self.learningEnabled = entry.learningEnabled
    }

    func toAgentConfig() -> AgentConfig {
        AgentConfig(
            name: name,
            emoji: emoji,
            gradientHex: gradientHex,
            instructions: instructions,
            enabledSkillIDs: skillIDs,
            knowledgeEnabled: knowledgeEnabled,
            learningEnabled: learningEnabled,
            temperature: temperature,
            enableThinking: enableThinking
        )
    }
}

// MARK: - Team Templates

/// A pre-configured multi-agent team that can be created in one tap.
struct TeamTemplate: Identifiable {
    let id: String
    let name: String
    let emoji: String
    let gradientHex: [String]
    let description: String
    let mode: String // "sequential", "parallel", "autonomous"

    /// The agents that make up this team, in order.
    let agents: [AgentTemplate]

    /// Convert to a TeamConfig + its member AgentConfigs.
    func toTeamConfig() -> (team: TeamConfig, agents: [AgentConfig]) {
        let agentConfigs = agents.map { $0.toAgentConfig() }
        let team = TeamConfig(
            name: name,
            emoji: emoji,
            gradientHex: gradientHex,
            mode: mode,
            memberIDs: agentConfigs.map(\.id)
        )
        return (team, agentConfigs)
    }

    static let builtIn: [TeamTemplate] = [
        TeamTemplate(
            id: "prepare-my-day",
            name: "Prepare My Day",
            emoji: "☀️",
            gradientHex: ["#FF6B35", "#F7C948"],
            description: "Scans your inbox, checks your calendar, and creates a morning briefing with action items",
            mode: "sequential",
            agents: [
                AgentTemplate(
                    id: "inbox-scanner",
                    name: "Inbox Scanner",
                    emoji: "📬",
                    gradientHex: ["#0077B6", "#00B4D8"],
                    description: "Reads unread emails, extracts key people and urgency",
                    skillIDs: ["email", "entity-extraction", "sentiment"],
                    instructions: """
                    You are an inbox scanner. Your job is to read the user's unread emails and produce a structured digest.

                    Steps:
                    1. Use the readEmail tool with action 'getUnread' to fetch unread messages.
                    2. For each important email, use extractEntities on the sender/subject to identify key people and organizations.
                    3. Use analyzeSentiment on the subject lines to flag urgent or negative tone.

                    Output a structured digest with:
                    - Total unread count
                    - For each email: sender, subject, urgency (high/medium/low based on sentiment), key entities
                    - Group by urgency: high-priority first

                    Be concise. This output feeds into the next agent.
                    """,
                    temperature: 0.3,
                    enableThinking: false,
                    knowledgeEnabled: false,
                    learningEnabled: false
                ),
                AgentTemplate(
                    id: "calendar-briefer",
                    name: "Calendar Briefer",
                    emoji: "📅",
                    gradientHex: ["#2D6A4F", "#74C69D"],
                    description: "Pulls today's schedule and cross-references with email senders",
                    skillIDs: ["calendar", "reminders"],
                    instructions: """
                    You are a calendar briefer. You receive an email digest from the previous agent.

                    Steps:
                    1. Use searchCalendar with input 'today' to get all events for today.
                    2. Use manageReminders with input 'all' to check existing reminders.
                    3. Cross-reference: if any email senders appear in today's meetings, note that connection.

                    Output a timeline for the day:
                    - Time | Event | Related emails (if any) | Existing reminders
                    - Note any gaps in the schedule
                    - Flag meetings where you received related emails (e.g. "Meeting with Sarah at 2pm — she emailed about the budget")

                    Include the email digest from above in your output so the next agent has full context.
                    """,
                    temperature: 0.3,
                    enableThinking: false,
                    knowledgeEnabled: false,
                    learningEnabled: false
                ),
                AgentTemplate(
                    id: "day-strategist",
                    name: "Day Strategist",
                    emoji: "🧠",
                    gradientHex: ["#7209B7", "#B5179E"],
                    description: "Synthesizes emails + calendar into a prioritized action plan with reminders",
                    skillIDs: ["reminders", "sentiment"],
                    instructions: """
                    You are a day strategist. You receive a combined email digest and calendar timeline.

                    Your job is to create a morning briefing:

                    1. **Priority Actions**: Which emails need a response before which meeting? Order by urgency and deadline.
                    2. **Meeting Prep**: For each meeting, what should the user prepare? Reference related emails.
                    3. **Action Items**: Create reminders for key tasks using manageReminders with action 'create'.
                    4. **Quick Wins**: Any emails that can be handled in under 2 minutes.
                    5. **Day Summary**: A 2-3 sentence overview of the day ahead.

                    Format as a clean, scannable morning briefing. Use sections with headers.
                    Create real reminders for the top 3-5 action items.
                    """,
                    temperature: 0.5,
                    enableThinking: false,
                    knowledgeEnabled: false,
                    learningEnabled: false
                ),
            ]
        ),
    ]
}

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
