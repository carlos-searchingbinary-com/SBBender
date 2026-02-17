import Foundation

/// A message in a conversation, supporting multimodal content and tool calls.
public struct Message: Sendable, Codable, Hashable, Identifiable {
    public let id: String
    public let role: Role
    public var content: [Content]
    public var toolCalls: [ToolCall]?
    public var toolCallID: String?
    public var name: String?
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        role: Role,
        content: [Content],
        toolCalls: [ToolCall]? = nil,
        toolCallID: String? = nil,
        name: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.name = name
        self.createdAt = createdAt
    }

    // MARK: - Convenience Initializers

    /// Create a simple text message.
    public static func system(_ text: String) -> Message {
        Message(role: .system, content: [.text(text)])
    }

    public static func user(_ text: String) -> Message {
        Message(role: .user, content: [.text(text)])
    }

    public static func assistant(_ text: String) -> Message {
        Message(role: .assistant, content: [.text(text)])
    }

    public static func tool(id: String, result: String, name: String? = nil) -> Message {
        Message(role: .tool, content: [.text(result)], toolCallID: id, name: name)
    }

    /// Create a multimodal user message with text and images.
    public static func user(_ text: String, images: [ImageContent]) -> Message {
        var parts: [Content] = [.text(text)]
        parts.append(contentsOf: images.map { .image($0) })
        return Message(role: .user, content: parts)
    }

    // MARK: - Computed Properties

    /// Concatenated text from all text content parts.
    public var text: String {
        content.compactMap(\.textValue).joined()
    }

    /// All image attachments in this message.
    public var images: [ImageContent] {
        content.compactMap { if case .image(let img) = $0 { return img } else { return nil } }
    }

    /// All audio attachments in this message.
    public var audio: [AudioContent] {
        content.compactMap { if case .audio(let a) = $0 { return a } else { return nil } }
    }
}

// MARK: - Tool Call

/// A tool call requested by the model.
public struct ToolCall: Sendable, Codable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let arguments: String // JSON-encoded arguments

    public init(id: String = UUID().uuidString, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }

    /// Decode arguments into a specific type.
    public func decodeArguments<T: Decodable>(_ type: T.Type) throws -> T {
        guard let data = arguments.data(using: .utf8) else {
            throw SBBenderError.invalidArguments("Failed to encode arguments string to UTF-8 data")
        }
        return try JSONDecoder().decode(type, from: data)
    }
}
