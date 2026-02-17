import Foundation

/// A skill defined by SKILL.md — instructions that shape agent behavior.
///
/// Skills are evaluated by an agent with a model, not executed directly.
/// They can bundle scripts (bash/python in `scripts/`) and declare which
/// tools the agent may use (`allowed-tools`).
///
/// This is distinct from `NativeTool`, which provides instant, zero-LLM
/// native capabilities (NLP, Vision, Translation).
public struct Skill: Sendable, Identifiable, Codable {
    public let id: String
    public let name: String
    public let description: String
    /// Full markdown instructions from SKILL.md body.
    public let instructions: String
    /// Bundled scripts (bash/python) from the skill's scripts/ directory.
    public let scripts: [SkillScript]
    /// Tool restrictions — if set, the agent can only use these tools.
    public let allowedTools: [String]?
    /// Reference documents for progressive disclosure.
    public let references: [SkillReference]
    /// GitHub source (owner/repo).
    public let source: String
    /// Local directory where installed.
    public let localPath: URL

    public init(
        id: String,
        name: String,
        description: String,
        instructions: String,
        scripts: [SkillScript] = [],
        allowedTools: [String]? = nil,
        references: [SkillReference] = [],
        source: String = "",
        localPath: URL = URL(fileURLWithPath: "/tmp")
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.instructions = instructions
        self.scripts = scripts
        self.allowedTools = allowedTools
        self.references = references
        self.source = source
        self.localPath = localPath
    }
}

/// A script bundled with a skill.
public struct SkillScript: Sendable, Identifiable, Codable {
    public let name: String
    public let language: ScriptLanguage
    public let localPath: URL
    public var id: String { name }

    public init(name: String, language: ScriptLanguage, localPath: URL) {
        self.name = name
        self.language = language
        self.localPath = localPath
    }
}

/// Language of a bundled script.
public enum ScriptLanguage: String, Sendable, Codable {
    case bash, python, javascript, unknown

    public init(filename: String) {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "sh", "bash": self = .bash
        case "py": self = .python
        case "js", "mjs": self = .javascript
        default: self = .unknown
        }
    }
}

/// A reference document bundled with a skill.
public struct SkillReference: Sendable, Identifiable, Codable {
    public let name: String
    public let content: String
    public var id: String { name }

    public init(name: String, content: String) {
        self.name = name
        self.content = content
    }
}
