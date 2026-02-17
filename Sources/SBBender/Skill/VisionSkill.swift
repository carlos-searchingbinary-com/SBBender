import Foundation
import os
@preconcurrency import MLXVLM
@preconcurrency import MLXLMCommon
import MLX
import MLXRandom

/// Image description and analysis using MLX Vision Language Models.
///
/// Uses MLXVLM (FastVLM or similar) for on-device image understanding.
/// Runs entirely on Apple Silicon GPU via Metal.
///
/// Latency: ~1s for small images, varies by model and resolution.
public final class VisionSkill: @unchecked Sendable, NativeTool {
    public let id = "vision"
    public let name = "describeImage"
    public let description = "Describe or analyze an image using a vision language model"

    private let modelID: String
    private let maxTokens: Int
    private let state = OSAllocatedUnfairLock(initialState: VisionState())

    struct VisionState: Sendable {
        var container: ModelContainer?
        var loadTask: Task<ModelContainer, Error>?
    }

    public init(
        modelID: String = "mlx-community/FastVLM-0.5B-bf16",
        maxTokens: Int = 512
    ) {
        self.modelID = modelID
        self.maxTokens = maxTokens
    }

    public var isAvailable: Bool {
        get async {
            #if arch(arm64)
            return true
            #else
            return false
            #endif
        }
    }

    public var toolParameters: JSONSchema {
        JSONSchema(
            properties: [
                "input": .string("Path to the image file to analyze"),
                "prompt": .string("What to analyze or describe about the image. Defaults to 'Describe this image.'"),
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
            struct Args: Decodable { let input: String; let prompt: String? }
            let args = try JSONDecoder().decode(Args.self, from: Data(arguments.utf8))
            let result = try await skill.execute(input: NativeToolInput(
                text: args.input,
                parameters: args.prompt.map { ["prompt": $0] } ?? [:]
            ))
            return result.output
        }
    }

    public func execute(input: NativeToolInput) async throws -> NativeToolResult {
        guard let imagePath = input.text, !imagePath.isEmpty else {
            throw SBBenderError.skillExecutionFailed(skill: name, reason: "No image file path provided")
        }

        let imageURL = URL(fileURLWithPath: imagePath)
        guard FileManager.default.fileExists(atPath: imagePath) else {
            throw SBBenderError.skillExecutionFailed(skill: name, reason: "Image file not found: \(imagePath)")
        }

        let prompt = input.parameters["prompt"] ?? "Describe this image."
        let start = CFAbsoluteTimeGetCurrent()

        let container = try await loadModel()

        MLXRandom.seed(UInt64(Date.timeIntervalSinceReferenceDate * 1000))

        let userInput = UserInput(chat: [.user(prompt, images: [.url(imageURL)])])

        let maxTok = maxTokens
        let result = try await container.perform { ctx in
            let preparedInput = try await ctx.processor.prepare(input: userInput)
            let parameters = GenerateParameters(maxTokens: maxTok, temperature: 0.7)
            return try MLXLMCommon.generate(
                input: preparedInput,
                parameters: parameters,
                context: ctx
            ) { tokens in
                tokens.count >= maxTok ? .stop : .more
            }
        }

        var output = result.output
        // Strip <think> tags
        if let thinkEnd = output.range(of: "</think>") {
            output = String(output[thinkEnd.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if output.hasPrefix("<think>") {
            output = ""
        }

        return NativeToolResult(
            output: output.trimmingCharacters(in: .whitespacesAndNewlines),
            structuredData: [
                "model": modelID,
                "imagePath": imagePath,
            ],
            confidence: 1.0,
            latency: CFAbsoluteTimeGetCurrent() - start
        )
    }

    private func loadModel() async throws -> ModelContainer {
        enum LoadState {
            case loaded(ModelContainer)
            case loading(Task<ModelContainer, Error>)
            case needsLoad
        }

        let loadState: LoadState = state.withLock { s in
            if let container = s.container { return .loaded(container) }
            if let task = s.loadTask { return .loading(task) }
            return .needsLoad
        }

        switch loadState {
        case .loaded(let c): return c
        case .loading(let t): return try await t.value
        case .needsLoad: break
        }

        let mid = modelID
        let task = Task<ModelContainer, Error> {
            Log.skill.info("Loading VLM model: \(mid)")
            MLX.Memory.cacheLimit = 32 * 1024 * 1024
            let config = ModelConfiguration(id: mid)
            let container = try await VLMModelFactory.shared.loadContainer(configuration: config)
            Log.skill.info("VLM model loaded: \(mid)")
            return container
        }

        state.withLock { $0.loadTask = task }
        let result = try await task.value
        state.withLock { s in
            s.container = result
            s.loadTask = nil
        }
        return result
    }
}
