import Testing
import Foundation
@testable import SBBender

@Suite("ClawHubManager")
struct ClawHubManagerTests {

    // MARK: - SkillListEntry

    @Test("SkillListEntry is Codable")
    func listEntryCodable() throws {
        let entry = SkillListEntry(
            slug: "web-scraper",
            name: "Web Scraper",
            description: "Scrapes web pages",
            version: "1.0.0",
            author: "openclaw",
            downloads: 1234
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(SkillListEntry.self, from: data)
        #expect(decoded == entry)
    }

    @Test("SkillListEntry array decoding")
    func listEntryArrayDecoding() throws {
        let json = """
        [
            {"slug": "a", "name": "A", "description": "Skill A", "version": "1.0", "author": "x", "downloads": 10},
            {"slug": "b", "name": "B", "description": "Skill B", "version": "2.0", "author": "y", "downloads": 20}
        ]
        """
        let entries = try JSONDecoder().decode([SkillListEntry].self, from: Data(json.utf8))
        #expect(entries.count == 2)
        #expect(entries[0].slug == "a")
        #expect(entries[1].downloads == 20)
    }

    // MARK: - Local Installation

    @available(macOS 26, *)
    @Test("installs skill from local directory")
    func installLocal() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sbbender-clawhub-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a skill directory
        let skillDir = tempDir.appendingPathComponent("my-skill")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)

        let skillMD = """
        ---
        name: my-skill
        description: A local test skill
        version: 1.0.0
        requires:
          bins: [sh]
        ---
        Just a test.
        """
        try skillMD.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try "echo hello".write(to: skillDir.appendingPathComponent("run.sh"), atomically: true, encoding: .utf8)

        let imageManager = ContainerImageManager()
        let pool = ContainerPool(imageManager: imageManager)
        let manager = ClawHubManager(
            pool: pool,
            skillsDirectory: tempDir
        )

        let skill = try await manager.installLocal(directory: skillDir)
        #expect(skill.name == "my-skill")
        #expect(skill.manifest.description == "A local test skill")

        // Should be in allSkills
        let all = await manager.allSkills()
        #expect(all.count == 1)
        #expect(all[0].name == "my-skill")
    }

    @available(macOS 26, *)
    @Test("uninstall removes skill")
    func uninstall() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sbbender-clawhub-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let skillDir = tempDir.appendingPathComponent("to-remove")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)

        let skillMD = """
        ---
        name: to-remove
        description: Will be removed
        version: 1.0.0
        ---
        Temporary skill.
        """
        try skillMD.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let imageManager = ContainerImageManager()
        let pool = ContainerPool(imageManager: imageManager)
        let manager = ClawHubManager(pool: pool, skillsDirectory: tempDir)

        _ = try await manager.installLocal(directory: skillDir)
        let before = await manager.allSkills()
        #expect(before.count == 1)

        try await manager.uninstall(slug: "to-remove")
        let after = await manager.allSkills()
        #expect(after.count == 0)
    }

    @available(macOS 26, *)
    @Test("uninstall throws for unknown skill")
    func uninstallUnknown() async throws {
        let imageManager = ContainerImageManager()
        let pool = ContainerPool(imageManager: imageManager)
        let manager = ClawHubManager(pool: pool)

        await #expect(throws: SBBenderError.self) {
            try await manager.uninstall(slug: "nonexistent")
        }
    }

    @available(macOS 26, *)
    @Test("duplicate install returns existing skill")
    func duplicateInstall() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sbbender-clawhub-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let skillDir = tempDir.appendingPathComponent("dup-skill")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)

        let skillMD = """
        ---
        name: dup-skill
        description: Test dedup
        version: 1.0.0
        ---
        Test.
        """
        try skillMD.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let imageManager = ContainerImageManager()
        let pool = ContainerPool(imageManager: imageManager)
        let manager = ClawHubManager(pool: pool, skillsDirectory: tempDir)

        let first = try await manager.installLocal(directory: skillDir)
        let second = try await manager.installLocal(directory: skillDir)

        #expect(first.id == second.id)
        let all = await manager.allSkills()
        #expect(all.count == 1)
    }

    // MARK: - Permission Delegation

    @available(macOS 26, *)
    @Test("install uses permission delegate for env vars")
    func permissionDelegation() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sbbender-clawhub-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let skillDir = tempDir.appendingPathComponent("needs-env")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)

        let skillMD = """
        ---
        name: needs-env
        description: Needs API key
        version: 1.0.0
        requires:
          env: [MY_API_KEY]
        ---
        Needs env.
        """
        try skillMD.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let delegate = AllowAllPermissionDelegate(envVars: ["MY_API_KEY": "test-key-123"])
        let imageManager = ContainerImageManager()
        let pool = ContainerPool(imageManager: imageManager)
        let manager = ClawHubManager(
            pool: pool,
            permissionDelegate: delegate,
            skillsDirectory: tempDir
        )

        let skill = try await manager.installLocal(directory: skillDir)
        #expect(skill.permissions.approvedEnvVars["MY_API_KEY"] == "test-key-123")
    }

    @available(macOS 26, *)
    @Test("DenyAll delegate results in no env vars")
    func denyAllDelegation() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sbbender-clawhub-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let skillDir = tempDir.appendingPathComponent("denied")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)

        let skillMD = """
        ---
        name: denied
        description: Will be denied env
        version: 1.0.0
        requires:
          env: [SECRET_KEY]
        ---
        Denied.
        """
        try skillMD.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let imageManager = ContainerImageManager()
        let pool = ContainerPool(imageManager: imageManager)
        let manager = ClawHubManager(
            pool: pool,
            permissionDelegate: DenyAllPermissionDelegate(),
            skillsDirectory: tempDir
        )

        let skill = try await manager.installLocal(directory: skillDir)
        #expect(skill.permissions.approvedEnvVars.isEmpty)
        #expect(skill.permissions.networkAccess == false)
    }
}
