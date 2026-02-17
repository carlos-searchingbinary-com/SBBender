import Testing
import Foundation
@testable import SBBender

@Suite("ContainerProfile")
struct ContainerProfileTests {

    @Test("minimal profile for shell-only skill")
    func minimalProfile() {
        let manifest = SkillManifest(
            name: "echo-test",
            slug: "echo-test",
            description: "Just echoes input",
            version: "1.0.0",
            requirements: SkillRequirements(bins: ["sh"]),
            localPath: URL(fileURLWithPath: "/tmp/test")
        )

        let profile = ContainerProfile.from(manifest: manifest)
        #expect(profile.baseImage == .minimal)
        #expect(profile.cpus == 2)
        #expect(profile.memoryMB == 512)
    }

    @Test("node profile when bins contain node")
    func nodeProfile() {
        let manifest = SkillManifest(
            name: "scraper",
            slug: "scraper",
            description: "Web scraper",
            version: "1.0.0",
            requirements: SkillRequirements(bins: ["node", "npx"]),
            localPath: URL(fileURLWithPath: "/tmp/test")
        )

        let profile = ContainerProfile.from(manifest: manifest)
        #expect(profile.baseImage == .node)
    }

    @Test("python profile when bins contain python")
    func pythonProfile() {
        let manifest = SkillManifest(
            name: "analyzer",
            slug: "analyzer",
            description: "Data analyzer",
            version: "1.0.0",
            requirements: SkillRequirements(bins: ["python3"]),
            localPath: URL(fileURLWithPath: "/tmp/test")
        )

        let profile = ContainerProfile.from(manifest: manifest)
        #expect(profile.baseImage == .python)
    }

    @Test("full profile when both node and python needed")
    func fullProfile() {
        let manifest = SkillManifest(
            name: "polyglot",
            slug: "polyglot",
            description: "Uses both runtimes",
            version: "1.0.0",
            requirements: SkillRequirements(bins: ["node", "python3"]),
            localPath: URL(fileURLWithPath: "/tmp/test")
        )

        let profile = ContainerProfile.from(manifest: manifest)
        #expect(profile.baseImage == .full)
    }

    @Test("node profile inferred from primaryEnv")
    func nodeFromPrimaryEnv() {
        let manifest = SkillManifest(
            name: "js-skill",
            slug: "js-skill",
            description: "JS skill",
            version: "1.0.0",
            primaryEnv: "node",
            localPath: URL(fileURLWithPath: "/tmp/test")
        )

        let profile = ContainerProfile.from(manifest: manifest)
        #expect(profile.baseImage == .node)
    }

    @Test("python profile inferred from primaryEnv")
    func pythonFromPrimaryEnv() {
        let manifest = SkillManifest(
            name: "py-skill",
            slug: "py-skill",
            description: "Python skill",
            version: "1.0.0",
            primaryEnv: "python",
            localPath: URL(fileURLWithPath: "/tmp/test")
        )

        let profile = ContainerProfile.from(manifest: manifest)
        #expect(profile.baseImage == .python)
    }

    @Test("network inferred from API-related env vars")
    func networkInferredFromEnv() {
        let manifest = SkillManifest(
            name: "api-caller",
            slug: "api-caller",
            description: "Calls APIs",
            version: "1.0.0",
            requirements: SkillRequirements(env: ["OPENAI_API_KEY", "BASE_URL"]),
            localPath: URL(fileURLWithPath: "/tmp/test")
        )

        let profile = ContainerProfile.from(manifest: manifest)
        #expect(profile.needsNetwork == true)
    }

    @Test("no network for local-only skill")
    func noNetworkForLocalSkill() {
        let manifest = SkillManifest(
            name: "formatter",
            slug: "formatter",
            description: "Formats text locally",
            version: "1.0.0",
            requirements: SkillRequirements(env: ["OUTPUT_FORMAT"]),
            localPath: URL(fileURLWithPath: "/tmp/test")
        )

        let profile = ContainerProfile.from(manifest: manifest)
        #expect(profile.needsNetwork == false)
    }

    @Test("image references are correct")
    func imageReferences() {
        #expect(ContainerProfile(baseImage: .minimal).imageReference == "alpine:latest")
        #expect(ContainerProfile(baseImage: .node).imageReference == "node:lts-alpine")
        #expect(ContainerProfile(baseImage: .python).imageReference == "python:3-alpine")
        #expect(ContainerProfile(baseImage: .full).imageReference == "alpine:latest")
    }

    @Test("profiles are hashable for use as dictionary keys")
    func hashable() {
        let p1 = ContainerProfile(baseImage: .node, needsNetwork: false)
        let p2 = ContainerProfile(baseImage: .node, needsNetwork: false)
        let p3 = ContainerProfile(baseImage: .python, needsNetwork: true)

        var set: Set<ContainerProfile> = []
        set.insert(p1)
        set.insert(p2) // duplicate
        set.insert(p3)

        #expect(set.count == 2)
    }

    @Test("anyBins also influence profile selection")
    func anyBinsInfluence() {
        let manifest = SkillManifest(
            name: "flexible",
            slug: "flexible",
            description: "Uses npm from anyBins",
            version: "1.0.0",
            requirements: SkillRequirements(anyBins: ["npm", "yarn"]),
            localPath: URL(fileURLWithPath: "/tmp/test")
        )

        let profile = ContainerProfile.from(manifest: manifest)
        #expect(profile.baseImage == .node)
    }
}
