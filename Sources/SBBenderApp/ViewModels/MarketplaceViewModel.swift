import Foundation
import SwiftUI
import SBBender

extension SkillListEntry: Identifiable, Hashable {
    public var id: String { slug }
    public func hash(into hasher: inout Hasher) { hasher.combine(slug) }
}

@MainActor
@Observable
final class MarketplaceViewModel {
    var installedSlugs: Set<String> = []
    var installingSlugs: Set<String> = []
    var errorMessage: String?
    var selectedSkill: SkillListEntry?
    var parsedManifest: SkillManifest?
    var isParsingDrop: Bool = false

    // MARK: - skills.sh Registry Search
    var searchQuery: String = ""
    var searchResults: [SkillsShEntry] = []
    var isSearching: Bool = false
    var installedSkillsShNames: Set<String> = []

    // MARK: - skills.sh Preview
    var selectedSkillsShEntry: SkillsShEntry?
    var previewContent: SkillsShContent?
    var isLoadingPreview: Bool = false

    private var searchTask: Task<Void, Never>?

    /// Search the skills.sh registry with debouncing.
    func search(appState: AppState) {
        searchTask?.cancel()
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task {
            // Debounce 300ms
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            do {
                let client = appState.skillsShClient
                let results = try await client.search(query: query)
                guard !Task.isCancelled else { return }
                searchResults = results
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = "Search failed: \(error.localizedDescription)"
                searchResults = []
            }
            isSearching = false
        }
    }

    /// Fetch SKILL.md content for preview.
    func fetchPreview(entry: SkillsShEntry, appState: AppState) async {
        isLoadingPreview = true
        previewContent = nil
        errorMessage = nil

        do {
            let client = appState.skillsShClient
            let content = try await client.fetchSkill(entry)
            previewContent = content
        } catch {
            errorMessage = "Failed to load skill: \(error.localizedDescription)"
        }

        isLoadingPreview = false
    }

    /// Install a skill from the skills.sh registry.
    func installFromRegistry(entry: SkillsShEntry, appState: AppState) async {
        errorMessage = nil
        installingSlugs.insert(entry.name)

        do {
            let client = appState.skillsShClient
            let skill = try await client.install(entry)
            installedSkillsShNames.insert(skill.name)
            installedSlugs.insert(skill.id)
        } catch {
            errorMessage = "Install failed: \(error.localizedDescription)"
        }

        installingSlugs.remove(entry.name)
    }

    /// Uninstall a skills.sh skill by name.
    func uninstallSkillsSh(name: String, appState: AppState) async {
        errorMessage = nil
        do {
            let client = appState.skillsShClient
            try await client.uninstall(name: name)
            installedSkillsShNames.remove(name)
            installedSlugs.remove("skills-sh-\(name)")
        } catch {
            errorMessage = "Uninstall failed: \(error.localizedDescription)"
        }
    }

    /// Load installed skills.sh skills from disk.
    func loadInstalledSkillsSh(appState: AppState) async {
        do {
            let client = appState.skillsShClient
            let skills = try await client.listInstalled()
            installedSkillsShNames = Set(skills.map(\.name))
            for skill in skills {
                installedSlugs.insert(skill.id)
            }
        } catch {
            // Not fatal
        }
    }

    // MARK: - OpenClaw (Containerized) Install

    /// Install a containerized skill from the ClawHub registry by slug.
    func installFromRegistry(skill: SkillListEntry, appState: AppState) async {
        errorMessage = nil
        installingSlugs.insert(skill.slug)

        if #available(macOS 26, *) {
            do {
                let manager = try await appState.getOrCreateClawHubManager()
                let installed = try await manager.install(slug: skill.slug, version: skill.version)
                installedSlugs.insert(installed.id)
            } catch {
                errorMessage = "Install failed: \(error.localizedDescription)"
            }
        } else {
            errorMessage = "Containerized skill installation requires macOS 26 or later."
        }

        installingSlugs.remove(skill.slug)
    }

    // MARK: - Local Skill Installation

    /// Install from a local directory containing SKILL.md
    func installLocal(url: URL, appState: AppState) async {
        errorMessage = nil

        if #available(macOS 26, *) {
            do {
                let manager = try await appState.getOrCreateClawHubManager()
                let skill = try await manager.installLocal(directory: url)
                installedSlugs.insert(skill.id)
            } catch {
                errorMessage = "Local install failed: \(error.localizedDescription)"
            }
        } else {
            errorMessage = "Skill installation requires macOS 26 or later."
        }
    }

    /// Install from a .zip file — unzip to temp, find SKILL.md, install
    func installFromZip(url: URL, appState: AppState) async {
        errorMessage = nil

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sbbender-skill-\(UUID().uuidString)")

        do {
            // Unzip using ditto (macOS built-in)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-xk", url.path, tempDir.path]
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                errorMessage = "Failed to unzip archive."
                return
            }

            // Find SKILL.md in extracted contents
            let skillDir = try findSkillDirectory(in: tempDir)
            await installLocal(url: skillDir, appState: appState)

            // Cleanup
            try? FileManager.default.removeItem(at: tempDir)
        } catch {
            errorMessage = "Zip install failed: \(error.localizedDescription)"
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    /// Parse a dropped directory or file to preview its manifest
    func parseDroppedItem(url: URL, appState: AppState) async {
        isParsingDrop = true
        errorMessage = nil
        parsedManifest = nil

        do {
            let isZip = url.pathExtension.lowercased() == "zip"
            var targetDir = url

            if isZip {
                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("sbbender-preview-\(UUID().uuidString)")
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                process.arguments = ["-xk", url.path, tempDir.path]
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    errorMessage = "Failed to unzip archive."
                    isParsingDrop = false
                    return
                }
                targetDir = try findSkillDirectory(in: tempDir)
            }

            let manifest = try SkillManifestParser.parse(directory: targetDir)
            parsedManifest = manifest
        } catch {
            errorMessage = "Failed to parse skill: \(error.localizedDescription)"
        }

        isParsingDrop = false
    }

    /// Uninstall a skill by slug
    func uninstall(skill: SkillListEntry, appState: AppState) async {
        errorMessage = nil

        if #available(macOS 26, *) {
            do {
                let manager = try await appState.getOrCreateClawHubManager()
                try await manager.uninstall(slug: skill.slug)
                installedSlugs.remove(skill.slug)
            } catch {
                errorMessage = "Uninstall failed: \(error.localizedDescription)"
            }
        }
    }

    /// Sync installed slugs from ClawHubManager and skills.sh.
    func loadInstalled(appState: AppState) async {
        if #available(macOS 26, *) {
            if let manager = await appState.clawHubManager {
                let skills = await manager.allSkills()
                installedSlugs = Set(skills.map(\.id))
            }
        }
        await loadInstalledSkillsSh(appState: appState)
    }

    // MARK: - Helpers

    private func findSkillDirectory(in baseDir: URL) throws -> URL {
        // Check if SKILL.md is at root
        let rootSkill = baseDir.appendingPathComponent("SKILL.md")
        if FileManager.default.fileExists(atPath: rootSkill.path) {
            return baseDir
        }
        // Check one level deep
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: baseDir, includingPropertiesForKeys: nil
        ) {
            for item in contents {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                    let nested = item.appendingPathComponent("SKILL.md")
                    if FileManager.default.fileExists(atPath: nested.path) {
                        return item
                    }
                }
            }
        }
        throw MarketplaceError.noSkillMD
    }
}

enum MarketplaceError: LocalizedError {
    case registryError(status: Int)
    case noSkillMD

    var errorDescription: String? {
        switch self {
        case .registryError(let status):
            return "Registry returned HTTP \(status)"
        case .noSkillMD:
            return "No SKILL.md found in the provided directory or archive"
        }
    }
}
