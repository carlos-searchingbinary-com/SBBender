import Foundation

/// A native Apple capability that provides instant, zero-LLM-needed results.
///
/// NativeTools are distinct from Tools:
/// - A **NativeTool** provides instant native capability (NLP, Vision, Translation).
/// - A **Tool** is an LLM-callable function with JSON Schema that the model decides to invoke.
///
/// NativeTools can optionally be exposed as Tools to the model, but they can also be
/// called directly by the Agent without model involvement.
public protocol NativeTool: Sendable {
    /// Unique identifier for this native tool.
    var id: String { get }

    /// Human-readable name.
    var name: String { get }

    /// Description of what this native tool does.
    var description: String { get }

    /// Whether this native tool is currently available on this device.
    var isAvailable: Bool { get async }

    /// Execute the native tool with the given input.
    func execute(input: NativeToolInput) async throws -> NativeToolResult

    /// Convert this native tool into an LLM-callable Tool.
    /// Override this to expose a richer parameter schema than the default `input` + `parameters`.
    func asTool() -> Tool
}

/// Input to a native tool invocation.
public struct NativeToolInput: Sendable {
    public let text: String?
    public let imageData: Data?
    public let audioData: Data?
    public let parameters: [String: String]

    public init(
        text: String? = nil,
        imageData: Data? = nil,
        audioData: Data? = nil,
        parameters: [String: String] = [:]
    ) {
        self.text = text
        self.imageData = imageData
        self.audioData = audioData
        self.parameters = parameters
    }

    public static func text(_ text: String) -> NativeToolInput {
        NativeToolInput(text: text)
    }
}

/// Result from a native tool invocation.
public struct NativeToolResult: Sendable {
    public let output: String
    public let structuredData: [String: String]
    public let confidence: Float
    public let latency: TimeInterval

    public init(
        output: String,
        structuredData: [String: String] = [:],
        confidence: Float = 1.0,
        latency: TimeInterval = 0
    ) {
        self.output = output
        self.structuredData = structuredData
        self.confidence = confidence
        self.latency = latency
    }
}

// MARK: - NativeTool → Tool Bridge

/// Default JSON args for native tools exposed as tools.
private struct NativeToolArgs: Decodable, Sendable {
    let input: String
    let parameters: [String: String]?
}

extension NativeTool {
    /// The JSON Schema for this native tool when exposed as a Tool.
    ///
    /// Override `toolParameters` in your native tool to expose richer schemas.
    /// The default exposes just `input` (required) and `parameters` (optional dict).
    public var toolParameters: JSONSchema {
        JSONSchema(
            properties: [
                "input": .string("The input text for the native tool"),
            ],
            required: ["input"]
        )
    }

    /// Expose this native tool as a Tool that the model can call.
    ///
    /// The default implementation works for any NativeTool. NativeTools with custom
    /// parameter schemas should override `toolParameters` and/or `asTool()`.
    public func asTool() -> Tool {
        let nativeTool = self
        return Tool(
            name: name,
            description: description,
            parameters: toolParameters
        ) { arguments, _ in
            let args = try JSONDecoder().decode(NativeToolArgs.self, from: Data(arguments.utf8))
            let input = NativeToolInput(
                text: args.input,
                parameters: args.parameters ?? [:]
            )
            let result = try await nativeTool.execute(input: input)

            // Return structured data as JSON if available, otherwise plain output
            if !result.structuredData.isEmpty {
                var response = result.structuredData
                response["output"] = result.output
                if let data = try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]),
                   let json = String(data: data, encoding: .utf8) {
                    return json
                }
            }
            return result.output
        }
    }
}
