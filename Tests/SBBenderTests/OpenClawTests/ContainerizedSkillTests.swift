import Testing
import Foundation
@testable import SBBender

@Suite("ContainerizedSkill")
struct ContainerizedSkillTests {

    // MARK: - Command Detection

    @available(macOS 26, *)
    @Test("detects run.sh as primary script")
    func detectRunSh() {
        let manifest = makeManifest(files: ["run.sh", "main.mjs", "main.py"])
        let skill = makeSkill(manifest: manifest)
        let command = skill.buildCommand()
        #expect(command == ["/bin/sh", "/skill/run.sh"])
    }

    @available(macOS 26, *)
    @Test("detects main.mjs when no run.sh")
    func detectMainMjs() {
        let manifest = makeManifest(files: ["main.mjs", "main.py", "utils.js"])
        let skill = makeSkill(manifest: manifest)
        let command = skill.buildCommand()
        #expect(command == ["/usr/local/bin/node", "/skill/main.mjs"])
    }

    @available(macOS 26, *)
    @Test("detects main.js when no mjs")
    func detectMainJs() {
        let manifest = makeManifest(files: ["main.js", "config.json"])
        let skill = makeSkill(manifest: manifest)
        let command = skill.buildCommand()
        #expect(command == ["/usr/local/bin/node", "/skill/main.js"])
    }

    @available(macOS 26, *)
    @Test("detects main.py")
    func detectMainPy() {
        let manifest = makeManifest(files: ["main.py", "requirements.txt"])
        let skill = makeSkill(manifest: manifest)
        let command = skill.buildCommand()
        #expect(command == ["/usr/local/bin/python3", "/skill/main.py"])
    }

    @available(macOS 26, *)
    @Test("detects main.sh")
    func detectMainSh() {
        let manifest = makeManifest(files: ["main.sh"])
        let skill = makeSkill(manifest: manifest)
        let command = skill.buildCommand()
        #expect(command == ["/bin/sh", "/skill/main.sh"])
    }

    @available(macOS 26, *)
    @Test("falls back to first executable-looking file")
    func fallbackToFirstExecutable() {
        let manifest = makeManifest(files: ["config.json", "process.py", "data.txt"])
        let skill = makeSkill(manifest: manifest)
        let command = skill.buildCommand()
        #expect(command == ["/usr/local/bin/python3", "/skill/process.py"])
    }

    @available(macOS 26, *)
    @Test("last resort command when no scripts found")
    func lastResort() {
        let manifest = makeManifest(files: ["config.json", "data.txt"])
        let skill = makeSkill(manifest: manifest)
        let command = skill.buildCommand()
        #expect(command.first == "/bin/sh")
    }

    // MARK: - Environment Variables

    @available(macOS 26, *)
    @Test("builds env vars with only approved vars from manifest")
    func envVarsFiltering() {
        let manifest = SkillManifest(
            name: "test",
            slug: "test",
            description: "Test",
            version: "1.0.0",
            requirements: SkillRequirements(env: ["API_KEY", "SECRET"]),
            localPath: URL(fileURLWithPath: "/tmp/test")
        )
        let permissions = SkillPermissions(
            approvedEnvVars: [
                "API_KEY": "approved-key",
                "SECRET": "approved-secret",
                "EXTRA": "not-in-manifest",  // should be filtered out
            ]
        )
        let skill = makeSkill(manifest: manifest, permissions: permissions)
        let env = skill.buildEnvironmentVariables()

        #expect(env.contains("API_KEY=approved-key"))
        #expect(env.contains("SECRET=approved-secret"))
        #expect(!env.contains(where: { $0.hasPrefix("EXTRA=") }))
        // Should always have PATH
        #expect(env.contains(where: { $0.hasPrefix("PATH=") }))
    }

    @available(macOS 26, *)
    @Test("no extra env vars when permissions are locked")
    func lockedEnvVars() {
        let manifest = SkillManifest(
            name: "test",
            slug: "test",
            description: "Test",
            version: "1.0.0",
            requirements: SkillRequirements(env: ["API_KEY"]),
            localPath: URL(fileURLWithPath: "/tmp/test")
        )
        let skill = makeSkill(manifest: manifest, permissions: .locked)
        let env = skill.buildEnvironmentVariables()

        #expect(!env.contains(where: { $0.hasPrefix("API_KEY=") }))
        #expect(env.count == 3) // PATH, HOME, LANG
    }

    // MARK: - Skill Protocol

    @available(macOS 26, *)
    @Test("skill has correct id and name")
    func skillIdentity() {
        let manifest = makeManifest(files: [])
        let skill = makeSkill(manifest: manifest)
        #expect(skill.id == "openclaw-test-skill")
        #expect(skill.name == "test-skill")
        #expect(skill.description == "A test skill")
    }

    @available(macOS 26, *)
    @Test("skill produces tool with correct parameters")
    func skillAsTool() {
        let manifest = makeManifest(files: [])
        let skill = makeSkill(manifest: manifest)
        let tool = skill.asTool()
        #expect(tool.name == "test-skill")
        #expect(tool.description == "A test skill")
    }

    // MARK: - Helpers

    private func makeManifest(files: [String]) -> SkillManifest {
        SkillManifest(
            name: "test-skill",
            slug: "test-skill",
            description: "A test skill",
            version: "1.0.0",
            supportingFiles: files,
            localPath: URL(fileURLWithPath: "/tmp/test")
        )
    }

    @available(macOS 26, *)
    private func makeSkill(
        manifest: SkillManifest? = nil,
        permissions: SkillPermissions = .locked
    ) -> ContainerizedSkill {
        let m = manifest ?? makeManifest(files: [])
        let imageManager = ContainerImageManager()
        let pool = ContainerPool(imageManager: imageManager)
        return ContainerizedSkill(manifest: m, permissions: permissions, pool: pool)
    }
}
