import Foundation
import Translation

/// Translates text between languages using Apple's Translation framework.
/// Latency: <100ms for short texts.
@available(macOS 26, *)
public struct TranslationSkill: NativeTool {
    public let id = "translation"
    public let name = "translateText"
    public let description = "Translate text between languages using Apple Translation"

    public var isAvailable: Bool {
        get async { true }
    }

    public init() {}

    public var toolParameters: JSONSchema {
        JSONSchema(
            properties: [
                "input": .string("The text to translate"),
                "source": .string("Source language code (e.g. 'en', 'fr'). Auto-detected if omitted."),
                "target": .string("Target language code (e.g. 'es', 'de'). Defaults to 'en'."),
            ],
            required: ["input"]
        )
    }

    public func asTool() -> Tool {
        let skill = self
        return Tool(
            name: name,
            description: description,
            parameters: toolParameters
        ) { arguments, _ in
            struct Args: Decodable { let input: String; let source: String?; let target: String? }
            let args = try JSONDecoder().decode(Args.self, from: Data(arguments.utf8))
            var params: [String: String] = [:]
            if let source = args.source { params["source"] = source }
            if let target = args.target { params["target"] = target }
            let result = try await skill.execute(input: NativeToolInput(text: args.input, parameters: params))
            return result.output
        }
    }

    public func execute(input: NativeToolInput) async throws -> NativeToolResult {
        guard let text = input.text, !text.isEmpty else {
            throw SBBenderError.skillExecutionFailed(skill: name, reason: "No text provided")
        }

        let start = CFAbsoluteTimeGetCurrent()

        let sourceLocale: Locale.Language?
        if let sourceCode = input.parameters["source"] {
            sourceLocale = Locale.Language(identifier: sourceCode)
        } else {
            sourceLocale = nil
        }

        let targetCode = input.parameters["target"] ?? "en"
        let targetLocale = Locale.Language(identifier: targetCode)

        let sourceLanguage = sourceLocale ?? Locale.Language(identifier: "en")

        let session = TranslationSession(installedSource: sourceLanguage, target: targetLocale)
        let response = try await session.translate(text)
        let translated = response.targetText

        return NativeToolResult(
            output: translated,
            structuredData: [
                "sourceLanguage": response.sourceLanguage.minimalIdentifier,
                "targetLanguage": targetCode,
            ],
            confidence: 1.0,
            latency: CFAbsoluteTimeGetCurrent() - start
        )
    }
}
