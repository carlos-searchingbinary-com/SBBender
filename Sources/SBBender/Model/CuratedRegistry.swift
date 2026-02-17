import Foundation

// MARK: - Registry Entry Types

/// A curated model entry from the registry catalog.
public struct ModelEntry: Sendable, Codable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let provider: String          // "mlx", "ollama"
    public let parameterSize: String     // "4B", "8B", "32B"
    public let quantization: String      // "4bit", "Q4_K_M"
    public let category: String          // "general", "coding", "reasoning", "vision", "multilingual"
    public let minTier: ModelTier
    public let recommendedTier: ModelTier
    public let ramRequired: Int          // GB
    public let description: String
    public let tags: [String]
    public let featured: Bool
}

/// A curated MCP server entry from the registry catalog.
public struct MCPServerEntry: Sendable, Codable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let description: String
    public let command: String
    public let arguments: [String]
    public let environment: [String: String]?
    public let category: String
    public let minModelTier: ModelTier
    public let requiredBins: [String]
    public let tags: [String]
    public let setupInstructions: String?

    /// Check if all required binaries are available on the system.
    public var binsAvailable: Bool {
        requiredBins.allSatisfy { bin in
            FileManager.default.isExecutableFile(atPath: "/usr/bin/\(bin)")
                || FileManager.default.isExecutableFile(atPath: "/usr/local/bin/\(bin)")
                || FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/\(bin)")
                || (try? shellWhich(bin)) != nil
        }
    }
}

/// A curated skills.sh skill entry from the registry catalog.
public struct SkillEntry: Sendable, Codable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let source: String
    public let description: String
    public let category: String
    public let minModelTier: ModelTier
    public let requiredTools: [String]
    public let tags: [String]
}

/// A curated agent template entry from the registry catalog.
public struct AgentTemplateEntry: Sendable, Codable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let emoji: String
    public let gradientHex: [String]
    public let description: String
    public let skillIDs: [String]
    public let instructions: String
    public let temperature: Float
    public let enableThinking: Bool
    public let knowledgeEnabled: Bool
    public let learningEnabled: Bool
}

/// A pre-configured bundle combining model, skills, MCP servers, and tools.
public struct BundleEntry: Sendable, Codable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let description: String
    public let model: String
    public let minTier: ModelTier
    public let skills: [String]
    public let mcpServers: [String]
    public let nativeTools: [String]
}

// MARK: - Curated Registry

/// Fetches and caches curated catalogs from the SBBender GitHub registry.
public actor CuratedRegistry {
    private let baseURL: URL
    private var modelCache: [ModelEntry]?
    private var mcpCache: [MCPServerEntry]?
    private var skillCache: [SkillEntry]?
    private var bundleCache: [BundleEntry]?
    private var templateCache: [AgentTemplateEntry]?

    /// Initialize with a custom base URL (useful for testing with local files).
    public init(baseURL: URL = URL(string: "https://raw.githubusercontent.com/carlos-searchingbinary-com/SBBender/main/registry")!) {
        self.baseURL = baseURL
    }

    /// Initialize for loading from a local registry directory.
    public init(localDirectory: URL) {
        self.baseURL = localDirectory
    }

    // MARK: - Fetch Catalogs

    /// Fetch all curated models.
    public func models() async throws -> [ModelEntry] {
        if let cached = modelCache { return cached }
        let entries: [ModelEntry] = try await fetch("models.json")
        modelCache = entries
        return entries
    }

    /// Fetch all curated MCP servers.
    public func mcpServers() async throws -> [MCPServerEntry] {
        if let cached = mcpCache { return cached }
        let entries: [MCPServerEntry] = try await fetch("mcp-servers.json")
        mcpCache = entries
        return entries
    }

    /// Fetch all curated skills.
    public func skills() async throws -> [SkillEntry] {
        if let cached = skillCache { return cached }
        let entries: [SkillEntry] = try await fetch("skills.json")
        skillCache = entries
        return entries
    }

    /// Fetch all curated bundles.
    public func bundles() async throws -> [BundleEntry] {
        if let cached = bundleCache { return cached }
        let entries: [BundleEntry] = try await fetch("bundles.json")
        bundleCache = entries
        return entries
    }

    /// Fetch all curated agent templates.
    public func agentTemplates() async throws -> [AgentTemplateEntry] {
        if let cached = templateCache { return cached }
        let entries: [AgentTemplateEntry] = try await fetch("agent-templates.json")
        templateCache = entries
        return entries
    }

    // MARK: - Filtered Queries

    /// Models compatible with the given hardware, sorted featured-first then by RAM.
    public func recommendedModels(for hardware: HardwareInfo) async throws -> [ModelEntry] {
        let all = try await models()
        return all
            .filter { $0.minTier <= hardware.modelTier }
            .sorted { a, b in
                if a.featured != b.featured { return a.featured }
                return a.ramRequired < b.ramRequired
            }
    }

    /// Models matching a specific category.
    public func models(category: String) async throws -> [ModelEntry] {
        let all = try await models()
        return all.filter { $0.category == category }
    }

    /// Featured models for the given hardware tier.
    public func featuredModels(for hardware: HardwareInfo) async throws -> [ModelEntry] {
        let all = try await models()
        return all.filter { $0.featured && $0.minTier <= hardware.modelTier }
    }

    /// MCP servers compatible with the given model tier.
    public func compatibleMCPServers(for tier: ModelTier) async throws -> [MCPServerEntry] {
        let all = try await mcpServers()
        return all.filter { $0.minModelTier <= tier }
    }

    /// Bundles compatible with the given hardware.
    public func compatibleBundles(for hardware: HardwareInfo) async throws -> [BundleEntry] {
        let all = try await bundles()
        return all.filter { $0.minTier <= hardware.modelTier }
    }

    // MARK: - Cache Management

    /// Clear all cached data, forcing a re-fetch on next access.
    public func refresh() {
        modelCache = nil
        mcpCache = nil
        skillCache = nil
        bundleCache = nil
        templateCache = nil
    }

    // MARK: - Private

    private func fetch<T: Decodable & Sendable>(_ filename: String) async throws -> T {
        let url: URL
        if baseURL.isFileURL {
            url = baseURL.appendingPathComponent(filename)
        } else {
            url = baseURL.appendingPathComponent(filename)
        }

        let data: Data
        if url.isFileURL {
            data = try Data(contentsOf: url)
        } else {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.cachePolicy = .reloadRevalidatingCacheData
            let (d, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw RegistryError.fetchFailed(filename, (response as? HTTPURLResponse)?.statusCode ?? 0)
            }
            data = d
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw RegistryError.decodingFailed(filename, error)
        }
    }
}

// MARK: - Errors

public enum RegistryError: LocalizedError, Sendable {
    case fetchFailed(String, Int)
    case decodingFailed(String, Error)

    public var errorDescription: String? {
        switch self {
        case .fetchFailed(let file, let status):
            "Failed to fetch \(file) (HTTP \(status))"
        case .decodingFailed(let file, let error):
            "Failed to decode \(file): \(error.localizedDescription)"
        }
    }
}

// MARK: - Helper

private func shellWhich(_ binary: String) throws -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    process.arguments = [binary]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus == 0
}
