import Foundation
import Observation
@preconcurrency import MLXLLM
@preconcurrency import MLXLMCommon

/// Dynamically fetches available models from each provider's real API.
/// - MLX: scans local HuggingFace cache + searches HuggingFace Hub
/// - Ollama: queries /api/tags for installed + /api/pull for new
/// - OpenAI: queries /v1/models
/// - Anthropic: queries /v1/models
@Observable
@MainActor
final class ModelRegistry {
    var mlxLocalModels: [String] = []
    var mlxSearchResults: [HFModelInfo] = []
    var mlxSearching = false

    /// Download state per model ID
    var mlxDownloadState: [String: MLXDownloadState] = [:]

    var ollamaModels: [OllamaModelInfo] = []
    var ollamaAvailable = false

    var openaiModels: [String] = []
    var anthropicModels: [String] = []
    var groqModels: [String] = []
    var deepinfraModels: [String] = []

    var errorMessage: String?

    enum MLXDownloadState: Equatable {
        case idle
        case downloading(progress: Double, speedBytesPerSec: Double?)
        case completed
        case error(String)
    }

    // MARK: - MLX (Local HuggingFace Cache)

    /// Scan ~/.cache/huggingface/hub/ for downloaded MLX-compatible models.
    /// Shows all local models that have actual model snapshots downloaded.
    func loadMLXLocal() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let cachePath = "\(home)/.cache/huggingface/hub"
        let fm = FileManager.default

        guard let entries = try? fm.contentsOfDirectory(atPath: cachePath) else {
            // Fallback: try with URL API
            let cacheURL = URL(fileURLWithPath: cachePath)
            guard let urlEntries = try? fm.contentsOfDirectory(
                at: cacheURL, includingPropertiesForKeys: nil
            ) else {
                mlxLocalModels = []
                return
            }
            mlxLocalModels = urlEntries.compactMap { url -> String? in
                let name = url.lastPathComponent
                guard name.hasPrefix("models--") else { return nil }
                return String(name.dropFirst("models--".count)).replacingOccurrences(of: "--", with: "/")
            }
            .filter { isLikelyLLM($0, cachePath: cachePath) }
            .sorted { mlxSortKey($0) < mlxSortKey($1) }
            return
        }

        // Directories named "models--org--name" → "org/name"
        mlxLocalModels = entries.compactMap { name -> String? in
            guard name.hasPrefix("models--") else { return nil }
            return String(name.dropFirst("models--".count)).replacingOccurrences(of: "--", with: "/")
        }
        .filter { isLikelyLLM($0, cachePath: cachePath) }
        .sorted { mlxSortKey($0) < mlxSortKey($1) }
    }

    /// Check if a cached model looks like an LLM (has config.json in its snapshot).
    /// Excludes embedding models, CLIP, OCR, etc.
    private func isLikelyLLM(_ modelID: String, cachePath: String) -> Bool {
        let lower = modelID.lowercased()

        // Always include mlx-community models
        if lower.hasPrefix("mlx-community/") { return true }

        // Exclude known non-LLM model families
        let excludePrefixes = [
            "sentence-transformers/", "openai/clip", "laion/", "timm/",
            "paddlepaddle/", "unitary/", "wespeaker/", "cardiffnlp/",
            "ds4sd/", "idea-research/", "facebook/sam"
        ]
        for prefix in excludePrefixes {
            if lower.hasPrefix(prefix) { return false }
        }

        // Check if the model has a snapshot with config.json (indicates a real model download)
        let dirName = "models--" + modelID.replacingOccurrences(of: "/", with: "--")
        let snapshotsPath = "\(cachePath)/\(dirName)/snapshots"
        guard let snapshots = try? FileManager.default.contentsOfDirectory(atPath: snapshotsPath),
              let firstSnapshot = snapshots.first(where: { !$0.hasPrefix(".") }) else {
            return false
        }
        let configPath = "\(snapshotsPath)/\(firstSnapshot)/config.json"
        return FileManager.default.fileExists(atPath: configPath)
    }

    /// Sort key: mlx-community models first, then alphabetical
    private func mlxSortKey(_ id: String) -> String {
        id.lowercased().hasPrefix("mlx-community/") ? "0_\(id)" : "1_\(id)"
    }

    /// Search HuggingFace Hub for MLX models
    func searchMLXHub(query: String) async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            mlxSearchResults = []
            return
        }

        mlxSearching = true
        defer { mlxSearching = false }

        // HuggingFace API: search models with mlx library tag
        var components = URLComponents(string: "https://huggingface.co/api/models")!
        components.queryItems = [
            URLQueryItem(name: "search", value: q),
            URLQueryItem(name: "library", value: "mlx"),
            URLQueryItem(name: "sort", value: "downloads"),
            URLQueryItem(name: "direction", value: "-1"),
            URLQueryItem(name: "limit", value: "20"),
        ]

        guard let url = components.url else { return }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            let (data, _) = try await URLSession.shared.data(for: request)
            let models = try JSONDecoder().decode([HFModelInfo].self, from: data)
            mlxSearchResults = models
        } catch {
            errorMessage = "HuggingFace search failed: \(error.localizedDescription)"
            mlxSearchResults = []
        }
    }

    // MARK: - MLX Download

    /// Download an MLX model from HuggingFace Hub.
    /// Uses LLMModelFactory which handles caching to ~/.cache/huggingface/hub/
    func downloadMLXModel(id: String) async {
        if case .downloading = mlxDownloadState[id] { return }
        mlxDownloadState[id] = .downloading(progress: 0, speedBytesPerSec: nil)

        do {
            let config = ModelConfiguration(id: id)
            // loadContainer downloads if not cached, then loads into memory.
            // Progress handler reports download fraction and speed.
            _ = try await LLMModelFactory.shared.loadContainer(
                configuration: config
            ) { [weak self] progress in
                Task { @MainActor [weak self] in
                    let fraction = progress.fractionCompleted
                    let speed = progress.userInfo[.throughputKey] as? Double
                    self?.mlxDownloadState[id] = .downloading(
                        progress: fraction,
                        speedBytesPerSec: speed
                    )
                }
            }
            mlxDownloadState[id] = .completed
            // Refresh local models list to pick up the new download
            loadMLXLocal()
        } catch {
            mlxDownloadState[id] = .error(error.localizedDescription)
        }
    }

    /// Check if a model ID is already downloaded locally
    func isMLXModelDownloaded(_ id: String) -> Bool {
        mlxLocalModels.contains(id)
    }

    // MARK: - Ollama

    /// Query Ollama /api/tags for installed models
    func loadOllamaModels(baseURL: URL = URL(string: "http://localhost:11434")!) async {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                ollamaAvailable = false
                ollamaModels = []
                return
            }
            ollamaAvailable = true
            let result = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
            ollamaModels = result.models.sorted { $0.name < $1.name }
        } catch {
            ollamaAvailable = false
            ollamaModels = []
        }
    }

    // MARK: - OpenAI

    /// Query OpenAI /v1/models
    func loadOpenAIModels(apiKey: String, baseURL: URL = URL(string: "https://api.openai.com/v1")!) async {
        guard !apiKey.isEmpty else {
            openaiModels = []
            return
        }

        let url = baseURL.appendingPathComponent("models")
        var request = URLRequest(url: url)
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                openaiModels = []
                return
            }
            let result = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
            // Filter to chat models, sort by ID
            openaiModels = result.data
                .map(\.id)
                .filter { id in
                    id.hasPrefix("gpt-") || id.hasPrefix("o1") || id.hasPrefix("o3") || id.hasPrefix("o4")
                }
                .sorted()
        } catch {
            openaiModels = []
        }
    }

    // MARK: - Anthropic

    /// Query Anthropic /v1/models
    func loadAnthropicModels(apiKey: String) async {
        guard !apiKey.isEmpty else {
            anthropicModels = []
            return
        }

        let url = URL(string: "https://api.anthropic.com/v1/models")!
        var request = URLRequest(url: url)
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                anthropicModels = []
                return
            }
            let result = try JSONDecoder().decode(AnthropicModelsResponse.self, from: data)
            anthropicModels = result.data.map(\.id).sorted()
        } catch {
            anthropicModels = []
        }
    }

    // MARK: - Groq

    /// Query Groq /v1/models (OpenAI-compatible)
    func loadGroqModels(apiKey: String) async {
        guard !apiKey.isEmpty else {
            groqModels = []
            return
        }

        let url = URL(string: "https://api.groq.com/openai/v1/models")!
        var request = URLRequest(url: url)
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                groqModels = []
                return
            }
            let result = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
            groqModels = result.data.map(\.id).sorted()
        } catch {
            groqModels = []
        }
    }

    // MARK: - DeepInfra

    /// Query DeepInfra /v1/openai/models (OpenAI-compatible)
    func loadDeepInfraModels(apiKey: String) async {
        guard !apiKey.isEmpty else {
            deepinfraModels = []
            return
        }

        let url = URL(string: "https://api.deepinfra.com/v1/openai/models")!
        var request = URLRequest(url: url)
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                deepinfraModels = []
                return
            }
            let result = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
            deepinfraModels = result.data.map(\.id).sorted()
        } catch {
            deepinfraModels = []
        }
    }

    /// Load all provider models at once
    func loadAll() async {
        loadMLXLocal()
        async let ollama: () = loadOllamaModels()
        async let openai: () = loadOpenAIModels(apiKey: KeychainService.openaiKey)
        async let anthropic: () = loadAnthropicModels(apiKey: KeychainService.anthropicKey)
        async let groq: () = loadGroqModels(apiKey: KeychainService.groqKey)
        async let deepinfra: () = loadDeepInfraModels(apiKey: KeychainService.deepinfraKey)
        _ = await (ollama, openai, anthropic, groq, deepinfra)
    }
}

// MARK: - Response Types

struct HFModelInfo: Decodable, Identifiable {
    let modelId: String // "mlx-community/Qwen3-4B-4bit" (this is the HF field name)
    let downloads: Int?
    let likes: Int?

    var id: String { modelId }

    var displayName: String {
        // "mlx-community/Qwen3-4B-4bit" → "Qwen3-4B-4bit"
        modelId.components(separatedBy: "/").last ?? modelId
    }
}

struct OllamaTagsResponse: Decodable {
    let models: [OllamaModelInfo]
}

struct OllamaModelInfo: Decodable, Identifiable {
    let name: String
    let size: Int?
    let details: OllamaModelDetails?

    var id: String { name }

    var sizeLabel: String {
        guard let bytes = size else { return "" }
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.0f MB", mb)
    }

    struct OllamaModelDetails: Decodable {
        let parameterSize: String?
        let quantizationLevel: String?

        enum CodingKeys: String, CodingKey {
            case parameterSize = "parameter_size"
            case quantizationLevel = "quantization_level"
        }
    }
}

struct OpenAIModelsResponse: Decodable {
    let data: [OpenAIModel]

    struct OpenAIModel: Decodable {
        let id: String
    }
}

struct AnthropicModelsResponse: Decodable {
    let data: [AnthropicModel]

    struct AnthropicModel: Decodable {
        let id: String
    }
}
