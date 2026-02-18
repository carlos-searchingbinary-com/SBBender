import Foundation

// MARK: - Media Source

/// A unified source for media content — URL, file path, or raw bytes.
public enum MediaSource: Sendable, Codable, Hashable {
    case url(URL)
    case filePath(String)
    case data(Data)

    public func resolveData() throws -> Data {
        switch self {
        case .url(let url):
            return try Data(contentsOf: url)
        case .filePath(let path):
            return try Data(contentsOf: URL(fileURLWithPath: path))
        case .data(let data):
            return data
        }
    }
}

// MARK: - Image Content

public struct ImageContent: Sendable, Codable, Hashable, Identifiable {
    public let id: String
    public let source: MediaSource
    public var mimeType: String?
    public var width: Int?
    public var height: Int?
    /// Detail level hint for vision models ("low", "high", "auto").
    public var detail: String?

    public init(
        id: String = UUID().uuidString,
        source: MediaSource,
        mimeType: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        detail: String? = nil
    ) {
        self.id = id
        self.source = source
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.detail = detail
    }

    public static func url(_ url: URL, detail: String? = nil) -> ImageContent {
        ImageContent(source: .url(url), detail: detail)
    }

    public static func file(_ path: String, detail: String? = nil) -> ImageContent {
        ImageContent(source: .filePath(path), detail: detail)
    }

    public static func data(_ data: Data, mimeType: String = "image/png") -> ImageContent {
        ImageContent(source: .data(data), mimeType: mimeType)
    }
}

// MARK: - Audio Content

public struct AudioContent: Sendable, Codable, Hashable, Identifiable {
    public let id: String
    public let source: MediaSource
    public var mimeType: String?
    public var duration: TimeInterval?
    public var sampleRate: Int?

    public init(
        id: String = UUID().uuidString,
        source: MediaSource,
        mimeType: String? = nil,
        duration: TimeInterval? = nil,
        sampleRate: Int? = nil
    ) {
        self.id = id
        self.source = source
        self.mimeType = mimeType
        self.duration = duration
        self.sampleRate = sampleRate
    }

    public static func file(_ path: String) -> AudioContent {
        AudioContent(source: .filePath(path))
    }

    public static func data(_ data: Data, mimeType: String = "audio/wav") -> AudioContent {
        AudioContent(source: .data(data), mimeType: mimeType)
    }
}

// MARK: - Video Content

public struct VideoContent: Sendable, Codable, Hashable, Identifiable {
    public let id: String
    public let source: MediaSource
    public var mimeType: String?
    public var duration: TimeInterval?
    public var width: Int?
    public var height: Int?

    public init(
        id: String = UUID().uuidString,
        source: MediaSource,
        mimeType: String? = nil,
        duration: TimeInterval? = nil,
        width: Int? = nil,
        height: Int? = nil
    ) {
        self.id = id
        self.source = source
        self.mimeType = mimeType
        self.duration = duration
        self.width = width
        self.height = height
    }
}

// MARK: - File Content

public struct FileContent: Sendable, Codable, Hashable, Identifiable {
    public let id: String
    public let source: MediaSource
    public var mimeType: String?
    public var fileName: String?
    public var size: Int?

    public init(
        id: String = UUID().uuidString,
        source: MediaSource,
        mimeType: String? = nil,
        fileName: String? = nil,
        size: Int? = nil
    ) {
        self.id = id
        self.source = source
        self.mimeType = mimeType
        self.fileName = fileName
        self.size = size
    }
}
