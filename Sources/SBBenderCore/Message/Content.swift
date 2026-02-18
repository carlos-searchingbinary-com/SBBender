import Foundation

/// A single piece of content within a message — text or media.
public enum Content: Sendable, Codable, Hashable {
    case text(String)
    case image(ImageContent)
    case audio(AudioContent)
    case video(VideoContent)
    case file(FileContent)

    /// Returns the text value if this is a `.text` case, otherwise nil.
    public var textValue: String? {
        if case .text(let s) = self { return s }
        return nil
    }

    public var isText: Bool {
        if case .text = self { return true }
        return false
    }
}
