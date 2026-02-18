import Foundation
import NaturalLanguage

/// Detects the dominant language of input text using NaturalLanguage framework.
/// Latency: <1ms.
public struct LanguageDetectionSkill: NativeTool {
    public let id = "language-detection"
    public let name = "detectLanguage"
    public let description = "Detect the dominant language of the given text"

    public var isAvailable: Bool {
        get async { true }
    }

    public init() {}

    public func execute(input: NativeToolInput) async throws -> NativeToolResult {
        guard let text = input.text, !text.isEmpty else {
            throw SBBenderError.skillExecutionFailed(skill: name, reason: "No text provided")
        }

        let start = CFAbsoluteTimeGetCurrent()
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)

        guard let language = recognizer.dominantLanguage else {
            return NativeToolResult(output: "und", confidence: 0, latency: CFAbsoluteTimeGetCurrent() - start)
        }

        let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
        let confidence = hypotheses[language] ?? 0

        return NativeToolResult(
            output: language.rawValue,
            structuredData: ["language": language.rawValue],
            confidence: Float(confidence),
            latency: CFAbsoluteTimeGetCurrent() - start
        )
    }
}

/// Analyzes sentiment of input text. Returns a score from -1.0 (negative) to 1.0 (positive).
/// Latency: <1ms.
public struct SentimentSkill: NativeTool {
    public let id = "sentiment"
    public let name = "analyzeSentiment"
    public let description = "Analyze the sentiment of the given text (-1.0 negative to 1.0 positive)"

    public var isAvailable: Bool {
        get async { true }
    }

    public init() {}

    public func execute(input: NativeToolInput) async throws -> NativeToolResult {
        guard let text = input.text, !text.isEmpty else {
            throw SBBenderError.skillExecutionFailed(skill: name, reason: "No text provided")
        }

        let start = CFAbsoluteTimeGetCurrent()
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text

        let (tag, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
        let score = Double(tag?.rawValue ?? "0") ?? 0

        let label: String
        if score > 0.1 { label = "positive" }
        else if score < -0.1 { label = "negative" }
        else { label = "neutral" }

        return NativeToolResult(
            output: label,
            structuredData: ["score": String(score), "label": label],
            confidence: 1.0,
            latency: CFAbsoluteTimeGetCurrent() - start
        )
    }
}

/// Extracts named entities (people, organizations, places) from text.
/// Latency: <1ms per paragraph.
public struct EntityExtractionSkill: NativeTool {
    public let id = "entity-extraction"
    public let name = "extractEntities"
    public let description = "Extract named entities (people, organizations, places) from text"

    public var isAvailable: Bool {
        get async { true }
    }

    public init() {}

    public func execute(input: NativeToolInput) async throws -> NativeToolResult {
        guard let text = input.text, !text.isEmpty else {
            throw SBBenderError.skillExecutionFailed(skill: name, reason: "No text provided")
        }

        let start = CFAbsoluteTimeGetCurrent()
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text

        var people: [String] = []
        var organizations: [String] = []
        var places: [String] = []

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitPunctuation, .omitWhitespace, .joinNames]
        ) { tag, range in
            let entity = String(text[range])
            switch tag {
            case .personalName:
                if !people.contains(entity) { people.append(entity) }
            case .organizationName:
                if !organizations.contains(entity) { organizations.append(entity) }
            case .placeName:
                if !places.contains(entity) { places.append(entity) }
            default:
                break
            }
            return true
        }

        var structured: [String: String] = [:]
        if !people.isEmpty { structured["people"] = people.joined(separator: ", ") }
        if !organizations.isEmpty { structured["organizations"] = organizations.joined(separator: ", ") }
        if !places.isEmpty { structured["places"] = places.joined(separator: ", ") }

        let allEntities = people + organizations + places
        let output = allEntities.isEmpty ? "No entities found" : allEntities.joined(separator: ", ")

        return NativeToolResult(
            output: output,
            structuredData: structured,
            confidence: 1.0,
            latency: CFAbsoluteTimeGetCurrent() - start
        )
    }
}

/// Tokenizes text into sentences, words, or paragraphs.
public struct TokenizationSkill: NativeTool {
    public let id = "tokenization"
    public let name = "tokenize"
    public let description = "Tokenize text into sentences, words, or paragraphs"

    public var isAvailable: Bool {
        get async { true }
    }

    public init() {}

    public var toolParameters: JSONSchema {
        JSONSchema(
            properties: [
                "input": .string("The text to tokenize"),
                "unit": .string("Token unit: 'word', 'sentence', or 'paragraph'. Defaults to 'sentence'."),
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
            struct Args: Decodable { let input: String; let unit: String? }
            let args = try JSONDecoder().decode(Args.self, from: Data(arguments.utf8))
            var params: [String: String] = [:]
            if let unit = args.unit { params["unit"] = unit }
            let result = try await skill.execute(input: NativeToolInput(text: args.input, parameters: params))
            return result.output
        }
    }

    public func execute(input: NativeToolInput) async throws -> NativeToolResult {
        guard let text = input.text, !text.isEmpty else {
            throw SBBenderError.skillExecutionFailed(skill: name, reason: "No text provided")
        }

        let start = CFAbsoluteTimeGetCurrent()
        let unitStr = input.parameters["unit"] ?? "sentence"

        let unit: NLTokenUnit
        switch unitStr {
        case "word": unit = .word
        case "paragraph": unit = .paragraph
        default: unit = .sentence
        }

        let tokenizer = NLTokenizer(unit: unit)
        tokenizer.string = text

        var tokens: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            tokens.append(String(text[range]))
            return true
        }

        return NativeToolResult(
            output: tokens.joined(separator: "\n"),
            structuredData: ["count": String(tokens.count), "unit": unitStr],
            confidence: 1.0,
            latency: CFAbsoluteTimeGetCurrent() - start
        )
    }
}

/// Computes text embedding distance between two strings using NLEmbedding.
public struct EmbeddingDistanceSkill: NativeTool {
    public let id = "embedding-distance"
    public let name = "embeddingDistance"
    public let description = "Compute semantic similarity between two texts using NLEmbedding"

    public var isAvailable: Bool {
        get async { NLEmbedding.wordEmbedding(for: .english) != nil }
    }

    public init() {}

    public var toolParameters: JSONSchema {
        JSONSchema(
            properties: [
                "input": .string("The first text to compare"),
                "compareTo": .string("The second text to compare against"),
            ],
            required: ["input", "compareTo"]
        )
    }

    public func asTool() -> Tool {
        let skill = self
        return Tool(
            name: name,
            description: description,
            parameters: toolParameters
        ) { arguments, _ in
            struct Args: Decodable { let input: String; let compareTo: String }
            let args = try JSONDecoder().decode(Args.self, from: Data(arguments.utf8))
            let result = try await skill.execute(input: NativeToolInput(
                text: args.input,
                parameters: ["compareTo": args.compareTo]
            ))
            return result.output
        }
    }

    public func execute(input: NativeToolInput) async throws -> NativeToolResult {
        guard let text = input.text else {
            throw SBBenderError.skillExecutionFailed(skill: name, reason: "No text provided")
        }
        guard let compareTo = input.parameters["compareTo"], !compareTo.isEmpty else {
            throw SBBenderError.skillExecutionFailed(skill: name, reason: "Missing or empty 'compareTo' parameter")
        }

        let start = CFAbsoluteTimeGetCurrent()

        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else {
            throw SBBenderError.skillNotAvailable("Sentence embedding not available for English")
        }

        let distance = embedding.distance(between: text, and: compareTo)
        let similarity = max(0, 1.0 - distance)

        return NativeToolResult(
            output: String(format: "%.4f", similarity),
            structuredData: [
                "similarity": String(format: "%.4f", similarity),
                "distance": String(format: "%.4f", distance),
            ],
            confidence: 1.0,
            latency: CFAbsoluteTimeGetCurrent() - start
        )
    }
}
