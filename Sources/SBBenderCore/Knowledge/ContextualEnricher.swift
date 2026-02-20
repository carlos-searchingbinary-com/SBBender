import Foundation
import NaturalLanguage

// MARK: - EnrichedChunk

/// A document chunk enriched with a contextual description and extracted entities.
///
/// The ``enrichedContent`` field — context description prepended to the raw chunk text —
/// is what gets embedded and indexed in BM25, giving the retrieval system the full
/// narrative context rather than an isolated fragment.
public struct EnrichedChunk: Sendable {
    /// The original, un-modified chunk.
    public let original: DocumentChunk
    /// A 1-3 sentence description situating this chunk within its source document.
    public let contextDescription: String
    /// Deduplicated named entities (persons, places, organizations) extracted from the chunk.
    public let entities: [String]
    /// The text that should be embedded: ``contextDescription`` + two newlines + ``original.content``.
    public let enrichedContent: String
}

// MARK: - ContextualEnricher

/// Enriches document chunks with contextual descriptions and Apple NLP entity extraction.
///
/// Implements Anthropic's *Contextual Retrieval* technique: before indexing, each chunk
/// receives a short prose description that explains where it lives inside its parent
/// document.  This dramatically improves retrieval for queries that use different
/// vocabulary than the raw chunk text.
///
/// **Context generation strategy (in priority order):**
/// 1. Use the caller-supplied ``ContextGenerator`` closure (typically an LLM call).
/// 2. Fall back to a rule-based description using the chunk's source title, position,
///    and NLTagger-extracted named entities.
///
/// - Note: This actor lives in `SBBenderCore` because `NaturalLanguage` is already a
///   dependency of that target (see `NLEmbeddingProvider`, `LanguageSkills`).
///   The optional ``ContextGenerator`` closure is ``@Sendable`` so callers can bridge
///   to MLX or FoundationModels without introducing a dependency on those targets.
public actor ContextualEnricher {

    // MARK: Types

    /// Closure that receives a truncated document preview and the raw chunk content,
    /// and returns a 1-3 sentence context description — or `nil` to fall back to the
    /// rule-based description.
    public typealias ContextGenerator = @Sendable (String, String) async -> String?

    // MARK: Properties

    private let contextGenerator: ContextGenerator?

    // MARK: Init

    public init(contextGenerator: ContextGenerator? = nil) {
        self.contextGenerator = contextGenerator
    }

    // MARK: Public API

    /// Enrich a single chunk with a context description and named-entity metadata.
    ///
    /// - Parameters:
    ///   - chunk: The chunk to enrich.
    ///   - documentContent: The full text of the source document (used as context window
    ///     for the LLM generator; only the first 6 000 characters are forwarded).
    ///   - allChunks: All chunks from the same ingestion batch (currently unused but
    ///     available for future structural heuristics such as section detection).
    /// - Returns: An ``EnrichedChunk`` ready for embedding and BM25 indexing.
    public func enrich(
        chunk: DocumentChunk,
        documentContent: String,
        allChunks: [DocumentChunk]
    ) async -> EnrichedChunk {
        let entities = extractEntities(from: chunk.content)

        let contextDescription: String
        if let generator = contextGenerator {
            let docPreview = String(documentContent.prefix(6_000))
            contextDescription = await generator(docPreview, chunk.content)
                ?? buildFallbackContext(chunk: chunk, entities: entities)
        } else {
            contextDescription = buildFallbackContext(chunk: chunk, entities: entities)
        }

        let enrichedContent = contextDescription + "\n\n" + chunk.content

        return EnrichedChunk(
            original: chunk,
            contextDescription: contextDescription,
            entities: entities,
            enrichedContent: enrichedContent
        )
    }

    // MARK: Private Helpers

    /// Rule-based fallback context: source title + chunk position + top entities.
    private func buildFallbackContext(chunk: DocumentChunk, entities: [String]) -> String {
        var parts: [String] = ["From: \(chunk.sourceTitle), section \(chunk.chunkIndex + 1)"]
        if !entities.isEmpty {
            parts.append("Key entities: \(entities.prefix(5).joined(separator: ", "))")
        }
        return parts.joined(separator: ". ") + "."
    }

    /// Extract named entities (persons, places, organizations) from `text` using NLTagger.
    ///
    /// Returns a deduplicated list of entity strings, preserving first-occurrence order.
    private func extractEntities(from text: String) -> [String] {
        var entities: [String] = []
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitWhitespace, .joinNames]
        ) { tag, range in
            if let tag, tag != .other {
                let entity = String(text[range])
                if entity.count > 2 { entities.append(entity) }
            }
            return true
        }
        // Deduplicate while preserving insertion order (case-insensitive).
        var seen = Set<String>()
        return entities.filter { seen.insert($0.lowercased()).inserted }
    }
}
