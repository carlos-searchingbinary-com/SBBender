import Foundation

/// Runtime profile derived from a ``SkillManifest``, used to select the appropriate
/// container base image and resource limits.
public struct ContainerProfile: Sendable, Hashable, Codable {
    /// Base container image type.
    public let baseImage: BaseImage
    /// Whether the skill needs network access inside the container.
    public let needsNetwork: Bool
    /// Number of CPU cores to allocate (default 2).
    public let cpus: Int
    /// Memory limit in megabytes (default 512).
    public let memoryMB: UInt64

    /// Pre-defined base image tiers.
    public enum BaseImage: String, Sendable, Hashable, Codable {
        /// Alpine Linux only (~5 MB). Shell scripts, curl.
        case minimal
        /// Node.js LTS on Alpine (~50 MB).
        case node
        /// Python 3 on Alpine (~50 MB).
        case python
        /// Node + Python + Go on Alpine.
        case full
    }

    public init(
        baseImage: BaseImage = .minimal,
        needsNetwork: Bool = false,
        cpus: Int = 2,
        memoryMB: UInt64 = 512
    ) {
        self.baseImage = baseImage
        self.needsNetwork = needsNetwork
        self.cpus = cpus
        self.memoryMB = memoryMB
    }

    /// Derive a container profile from a skill manifest.
    ///
    /// Logic:
    /// - `node` or `npx` in bins → `.node`
    /// - `python` or `python3` in bins → `.python`
    /// - Both node and python → `.full`
    /// - Otherwise → `.minimal`
    public static func from(manifest: SkillManifest) -> ContainerProfile {
        let allBins = Set(manifest.requirements.bins + manifest.requirements.anyBins)
        let needsNode = allBins.contains("node") || allBins.contains("npx") || allBins.contains("npm")
        let needsPython = allBins.contains("python") || allBins.contains("python3") || allBins.contains("pip")

        // Also infer from primaryEnv
        let envNode = manifest.primaryEnv == "node" || manifest.primaryEnv == "javascript"
        let envPython = manifest.primaryEnv == "python"

        let wantsNode = needsNode || envNode
        let wantsPython = needsPython || envPython

        let baseImage: BaseImage
        if wantsNode && wantsPython {
            baseImage = .full
        } else if wantsNode {
            baseImage = .node
        } else if wantsPython {
            baseImage = .python
        } else {
            baseImage = .minimal
        }

        // Infer network need from env vars (common patterns)
        let networkHints = Set(["API_KEY", "API_URL", "BASE_URL", "ENDPOINT", "WEBHOOK"])
        let needsNetwork = manifest.requirements.env.contains { envVar in
            networkHints.contains(where: { envVar.uppercased().contains($0) })
        }

        return ContainerProfile(
            baseImage: baseImage,
            needsNetwork: needsNetwork,
            cpus: 2,
            memoryMB: 512
        )
    }

    /// OCI image reference for this profile's base image.
    public var imageReference: String {
        switch baseImage {
        case .minimal: return "alpine:latest"
        case .node: return "node:lts-alpine"
        case .python: return "python:3-alpine"
        case .full: return "alpine:latest" // Custom image built with node+python
        }
    }
}
