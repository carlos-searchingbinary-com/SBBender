import Foundation

/// JSON Schema representation for tool parameters.
public struct JSONSchema: Sendable, Codable {
    public let type: String
    public var properties: [String: PropertySchema]
    public var required: [String]

    public init(
        type: String = "object",
        properties: [String: PropertySchema] = [:],
        required: [String] = []
    ) {
        self.type = type
        self.properties = properties
        self.required = required
    }

    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = ["type": type]
        var props: [String: Any] = [:]
        for (key, prop) in properties {
            props[key] = prop.toDictionary()
        }
        if !props.isEmpty {
            dict["properties"] = props
        }
        if !required.isEmpty {
            dict["required"] = required
        }
        return dict
    }
}

/// A box to allow recursive value types.
public final class Box<T: Sendable>: @unchecked Sendable {
    public let value: T
    public init(_ value: T) { self.value = value }
}

/// Schema for a single property in a JSON Schema.
public struct PropertySchema: Sendable, Codable {
    public let type: String
    public var description: String?
    public var enumValues: [String]?
    private var _items: Box<PropertySchema>?
    public var defaultValue: String?

    public var items: PropertySchema? {
        get { _items?.value }
    }

    public init(
        type: String,
        description: String? = nil,
        enumValues: [String]? = nil,
        items: PropertySchema? = nil,
        defaultValue: String? = nil
    ) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
        self._items = items.map { Box($0) }
        self.defaultValue = defaultValue
    }

    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = ["type": type]
        if let desc = description { dict["description"] = desc }
        if let enums = enumValues { dict["enum"] = enums }
        if let items { dict["items"] = items.toDictionary() }
        return dict
    }

    // Custom Codable for the boxed items
    private enum CodingKeys: String, CodingKey {
        case type, description, enumValues, items, defaultValue
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        enumValues = try c.decodeIfPresent([String].self, forKey: .enumValues)
        defaultValue = try c.decodeIfPresent(String.self, forKey: .defaultValue)
        if let items = try c.decodeIfPresent(PropertySchema.self, forKey: .items) {
            _items = Box(items)
        } else {
            _items = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(enumValues, forKey: .enumValues)
        try c.encodeIfPresent(defaultValue, forKey: .defaultValue)
        try c.encodeIfPresent(_items?.value, forKey: .items)
    }

    public static func string(_ description: String? = nil) -> PropertySchema {
        PropertySchema(type: "string", description: description)
    }

    public static func integer(_ description: String? = nil) -> PropertySchema {
        PropertySchema(type: "integer", description: description)
    }

    public static func number(_ description: String? = nil) -> PropertySchema {
        PropertySchema(type: "number", description: description)
    }

    public static func boolean(_ description: String? = nil) -> PropertySchema {
        PropertySchema(type: "boolean", description: description)
    }

    public static func array(items: PropertySchema, description: String? = nil) -> PropertySchema {
        PropertySchema(type: "array", description: description, items: items)
    }
}

/// A tool that can be called by the model.
///
/// Tools are LLM-callable functions with JSON Schema parameters. The model
/// decides when and how to call them based on the schema and description.
public struct Tool: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let parameters: JSONSchema
    public let requiresConfirmation: Bool
    public let stopAfterCall: Bool
    public let maxContentLength: Int?
    private let _execute: @Sendable (String, ToolContext) async throws -> String

    public init(
        name: String,
        description: String,
        parameters: JSONSchema = JSONSchema(),
        requiresConfirmation: Bool = false,
        stopAfterCall: Bool = false,
        maxContentLength: Int? = nil,
        execute: @escaping @Sendable (String, ToolContext) async throws -> String
    ) {
        self.id = name
        self.name = name
        self.description = description
        self.parameters = parameters
        self.requiresConfirmation = requiresConfirmation
        self.stopAfterCall = stopAfterCall
        self.maxContentLength = maxContentLength
        self._execute = execute
    }

    /// Execute the tool with JSON arguments and the current context.
    public func execute(arguments: String, context: ToolContext) async throws -> String {
        try await _execute(arguments, context)
    }

    /// Convert to a `ToolDefinition` for the model API.
    public func toDefinition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: description,
            parameters: parameters.toDictionary()
        )
    }
}

/// Context injected into tool execution at runtime.
public struct ToolContext: Sendable {
    public let agentID: String
    public let sessionID: String
    public let runID: String
    public var sessionState: [String: String]
    public var images: [ImageContent]
    public var audio: [AudioContent]

    public init(
        agentID: String = "",
        sessionID: String = "",
        runID: String = "",
        sessionState: [String: String] = [:],
        images: [ImageContent] = [],
        audio: [AudioContent] = []
    ) {
        self.agentID = agentID
        self.sessionID = sessionID
        self.runID = runID
        self.sessionState = sessionState
        self.images = images
        self.audio = audio
    }
}

// MARK: - ToolKit Protocol

/// A group of related tools. Implement this to bundle tools together.
public protocol ToolKit: Sendable {
    var name: String { get }
    var description: String { get }
    var tools: [Tool] { get }
}

// MARK: - Tool Registry

/// Registry that collects and resolves tools from multiple sources.
public struct ToolRegistry: Sendable {
    private var toolsByName: [String: Tool]

    public init() {
        self.toolsByName = [:]
    }

    public init(tools: [Tool]) {
        self.toolsByName = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
    }

    public init(toolKits: [any ToolKit]) {
        var dict: [String: Tool] = [:]
        for kit in toolKits {
            for tool in kit.tools {
                dict[tool.name] = tool
            }
        }
        self.toolsByName = dict
    }

    public mutating func register(_ tool: Tool) {
        toolsByName[tool.name] = tool
    }

    public mutating func register(contentsOf kit: any ToolKit) {
        for tool in kit.tools {
            toolsByName[tool.name] = tool
        }
    }

    public func get(_ name: String) -> Tool? {
        toolsByName[name]
    }

    public var allTools: [Tool] {
        Array(toolsByName.values)
    }

    public var definitions: [ToolDefinition] {
        allTools.map { $0.toDefinition() }
    }

    public var isEmpty: Bool {
        toolsByName.isEmpty
    }
}
