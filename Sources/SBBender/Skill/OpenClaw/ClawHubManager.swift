import Foundation
import os

#if canImport(Containerization)
import Containerization
#endif

/// Entry in a ClawHub search result.
public struct SkillListEntry: Sendable, Codable, Equatable {
    public let slug: String
    public let name: String
    public let description: String
    public let version: String
    public let author: String
    public let downloads: Int

    public init(slug: String, name: String, description: String, version: String, author: String = "", downloads: Int = 0) {
        self.slug = slug
        self.name = name
        self.description = description
        self.version = version
        self.author = author
        self.downloads = downloads
    }
}

/// Manages the lifecycle of OpenClaw skills from the ClawHub registry.
///
/// Handles searching, installing (from registry or local directory), uninstalling,
/// and tracking installed skills. All installed skills are stored under
/// `~/Library/Application Support/com.sbbender/skills/`.
@available(macOS 26, *)
public actor ClawHubManager {
    /// Base URL for the ClawHub API.
    public let registryURL: URL
    /// Local directory where skills are installed.
    public let skillsDirectory: URL
    /// Container pool shared by all containerized skills.
    private let pool: ContainerPool
    /// Permission delegate for approving skill access.
    private let permissionDelegate: any SkillPermissionDelegate
    /// URLSession for registry API calls.
    private let session: URLSession
    /// Cache of installed skills keyed by slug.
    private var installedSkills: [String: ContainerizedSkill] = [:]

    public init(
        pool: ContainerPool,
        permissionDelegate: any SkillPermissionDelegate = DenyAllPermissionDelegate(),
        registryURL: URL = URL(string: "https://api.clawhub.dev/v1")!,
        skillsDirectory: URL? = nil,
        session: URLSession = .shared
    ) {
        self.pool = pool
        self.permissionDelegate = permissionDelegate
        self.registryURL = registryURL
        self.session = session

        if let dir = skillsDirectory {
            self.skillsDirectory = dir
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            self.skillsDirectory = appSupport
                .appendingPathComponent("com.sbbender")
                .appendingPathComponent("skills")
        }
    }

    // MARK: - Container Configuration

    #if canImport(Containerization)
    /// Forward a `ContainerManager` to the underlying pool so containers can be created.
    ///
    /// Call this once during app startup after detecting a valid Linux kernel.
    public func configureContainerManager(_ manager: ContainerManager) async {
        await pool.setContainerManager(manager)
    }
    #endif

    // MARK: - Registry Operations

    /// Search the ClawHub registry for skills matching a query.
    public func search(query: String) async throws -> [SkillListEntry] {
        let url = registryURL
            .appendingPathComponent("skills")
            .appendingPathComponent("search")

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "q", value: query)]

        guard let requestURL = components.url else {
            throw SBBenderError.clawHubRegistryError("Invalid search URL")
        }

        let (data, response) = try await session.data(from: requestURL)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SBBenderError.clawHubRegistryError("Invalid response type")
        }
        guard httpResponse.statusCode == 200 else {
            throw SBBenderError.clawHubRegistryError("Search failed with status \(httpResponse.statusCode)")
        }

        return try JSONDecoder().decode([SkillListEntry].self, from: data)
    }

    /// Install a skill from the ClawHub registry.
    ///
    /// Flow:
    /// 1. Fetch skill tarball from registry
    /// 2. Extract to skills directory
    /// 3. Parse SKILL.md
    /// 4. Request permission approval via delegate
    /// 5. Create ContainerizedSkill
    public func install(slug: String, version: String = "latest") async throws -> ContainerizedSkill {
        if let existing = installedSkills[slug] {
            Log.openclaw.info("Skill '\(slug)' already installed")
            return existing
        }

        Log.openclaw.info("Installing skill '\(slug)' version \(version)")

        // Download from registry
        let url = registryURL
            .appendingPathComponent("skills")
            .appendingPathComponent(slug)
            .appendingPathComponent(version)
            .appendingPathComponent("download")

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SBBenderError.clawHubRegistryError("Invalid response type")
        }
        guard httpResponse.statusCode == 200 else {
            throw SBBenderError.skillInstallFailed(
                slug: slug,
                reason: "Registry returned status \(httpResponse.statusCode)"
            )
        }

        // Extract to skills directory
        let skillDir = skillsDirectory.appendingPathComponent(slug)
        try extractSkillArchive(data: data, to: skillDir)

        // Parse and create skill
        return try await installLocal(directory: skillDir)
    }

    /// Install a skill from a local directory.
    ///
    /// The directory must contain a valid SKILL.md file.
    public func installLocal(directory: URL) async throws -> ContainerizedSkill {
        let manifest = try SkillManifestParser.parse(directory: directory)

        if let existing = installedSkills[manifest.slug] {
            Log.openclaw.info("Skill '\(manifest.slug)' already installed from \(directory.path)")
            return existing
        }

        // Request permissions
        let permissions = try await requestPermissions(for: manifest)

        let skill = ContainerizedSkill(
            manifest: manifest,
            permissions: permissions,
            pool: pool
        )

        installedSkills[manifest.slug] = skill
        Log.openclaw.info("Installed skill '\(manifest.slug)' from \(directory.path)")

        return skill
    }

    /// Uninstall a skill by slug.
    public func uninstall(slug: String) async throws {
        guard installedSkills.removeValue(forKey: slug) != nil else {
            throw SBBenderError.skillNotAvailable("Skill '\(slug)' is not installed")
        }

        let skillDir = skillsDirectory.appendingPathComponent(slug)
        let fm = FileManager.default
        if fm.fileExists(atPath: skillDir.path) {
            try fm.removeItem(at: skillDir)
        }

        Log.openclaw.info("Uninstalled skill '\(slug)'")
    }

    /// All currently installed skills.
    public func allSkills() -> [any NativeTool] {
        Array(installedSkills.values)
    }

    /// Get a specific installed skill by slug.
    public func skill(for slug: String) -> ContainerizedSkill? {
        installedSkills[slug]
    }

    // MARK: - Private

    private func requestPermissions(for manifest: SkillManifest) async throws -> SkillPermissions {
        var permissions = SkillPermissions.locked

        // Request env var approval if skill declares any
        if !manifest.requirements.env.isEmpty {
            let approved = await permissionDelegate.approveEnvironmentVariables(
                skill: manifest.slug,
                requested: manifest.requirements.env
            )
            permissions.approvedEnvVars = approved
        }

        // Request network access if profile indicates it's needed
        let profile = ContainerProfile.from(manifest: manifest)
        if profile.needsNetwork {
            permissions.networkAccess = await permissionDelegate.approveNetworkAccess(skill: manifest.slug)
        }

        return permissions
    }

    private func extractSkillArchive(data: Data, to directory: URL) throws {
        let fm = FileManager.default

        // Clean existing directory
        if fm.fileExists(atPath: directory.path) {
            try fm.removeItem(at: directory)
        }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        // Write archive data and extract
        // For now, assume the archive is a tar.gz
        let archivePath = directory.appendingPathComponent("_archive.tar.gz")
        try data.write(to: archivePath)

        // Use tar to extract
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["xzf", archivePath.path, "-C", directory.path, "--strip-components=1"]
        try process.run()
        process.waitUntilExit()

        // Clean up archive
        try? fm.removeItem(at: archivePath)

        if process.terminationStatus != 0 {
            throw SBBenderError.skillInstallFailed(
                slug: directory.lastPathComponent,
                reason: "Failed to extract skill archive (exit \(process.terminationStatus))"
            )
        }
    }
}
