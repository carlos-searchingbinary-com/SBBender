import Foundation

/// The role of a message participant in a conversation.
public enum Role: String, Sendable, Codable, Hashable {
    case system
    case user
    case assistant
    case tool
}
