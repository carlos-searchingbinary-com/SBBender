import Foundation
import SBBender

struct AgentFactory {
    static func createAgent(
        from config: AgentConfig,
        nativeTools: [any NativeTool],
        skills: [Skill] = [],
        customTools: [Tool] = [],
        storage: GRDBStorage? = nil,
        knowledge: (any KnowledgeSource)? = nil,
        learning: LearningEngine? = nil,
        mcpManager: MCPManager? = nil
    ) -> Agent {
        // Resolve instructions: load from file if set, otherwise use config text
        var instructions = config.instructions
        if let filePath = config.systemPromptFile, !filePath.isEmpty {
            if let fileContents = try? String(contentsOfFile: filePath, encoding: .utf8) {
                instructions = fileContents
            }
        }

        let provider = createProvider(
            type: ProviderType(rawValue: config.providerType) ?? .mlx,
            modelID: config.modelID
        )

        let generationConfig = GenerationConfig(
            maxTokens: config.maxTokens,
            temperature: config.temperature,
            topP: config.topP,
            repetitionPenalty: config.repetitionPenalty,
            enableThinking: config.enableThinking
        )

        let agentConfig = AgentConfiguration(
            name: config.name,
            instructions: instructions,
            generationConfig: generationConfig,
            toolCallLimit: config.toolCallLimit,
            maxIterations: config.maxIterations,
            addDateToSystemPrompt: config.addDateToSystemPrompt,
            markdown: config.markdown,
            maxHistoryMessages: config.maxHistoryMessages,
            maxHistoryToolResults: 20
        )

        return Agent(
            id: config.id,
            configuration: agentConfig,
            model: provider,
            tools: customTools,
            nativeTools: nativeTools,
            skills: skills,
            storage: storage,
            knowledge: knowledge,
            learning: learning,
            mcpManager: mcpManager,
            sessionID: config.id
        )
    }

    static func createProvider(type: ProviderType, modelID: String) -> any ModelProvider {
        switch type {
        case .mlx:
            return MLXProvider(modelID: modelID)
        case .foundation:
            if #available(macOS 26, *) {
                return FoundationProvider()
            }
            // Fallback to MLX if macOS 26 not available
            return MLXProvider(modelID: "mlx-community/Qwen3-4B-4bit")
        case .ollama:
            return OllamaProvider(modelID: modelID.isEmpty ? "qwen3:4b" : modelID)
        case .anthropic:
            return AnthropicProvider(
                modelID: modelID.isEmpty ? "claude-sonnet-4-5-20250929" : modelID,
                apiKey: KeychainService.anthropicKey
            )
        case .openai:
            return OpenAIProvider(
                modelID: modelID.isEmpty ? "gpt-4.1" : modelID,
                apiKey: KeychainService.openaiKey
            )
        case .groq:
            return OpenAIProvider(
                modelID: modelID.isEmpty ? "llama-3.3-70b-versatile" : modelID,
                apiKey: KeychainService.groqKey,
                baseURL: URL(string: "https://api.groq.com/openai/v1")!
            )
        case .deepinfra:
            return OpenAIProvider(
                modelID: modelID.isEmpty ? "meta-llama/Llama-4-Scout-17B-16E-Instruct" : modelID,
                apiKey: KeychainService.deepinfraKey,
                baseURL: URL(string: "https://api.deepinfra.com/v1/openai")!
            )
        }
    }

    /// Convert a chunking strategy string to the library enum.
    static func chunkingStrategy(from config: AgentConfig) -> ChunkingStrategy {
        switch config.knowledgeChunkingStrategy {
        case "fixedSize": return .fixedSize(size: 256, overlap: 32)
        case "sentence": return .sentence(maxTokens: 512)
        default: return .paragraph
        }
    }
}
