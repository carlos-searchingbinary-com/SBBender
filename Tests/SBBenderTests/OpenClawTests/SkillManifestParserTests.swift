import Testing
import Foundation
@testable import SBBender

@Suite("SkillManifest Parser")
struct SkillManifestParserTests {

    // MARK: - Frontmatter Extraction

    @Test("extracts YAML frontmatter and body")
    func extractFrontmatter() {
        let content = """
        ---
        name: test-skill
        description: A test skill
        ---
        # Instructions

        Run this skill to test things.
        """

        let result = SkillManifestParser.extractFrontmatter(from: content)
        #expect(result != nil)
        #expect(result!.yaml.contains("name: test-skill"))
        #expect(result!.yaml.contains("description: A test skill"))
        #expect(result!.body.contains("# Instructions"))
        #expect(result!.body.contains("Run this skill to test things."))
    }

    @Test("returns nil for content without frontmatter")
    func noFrontmatter() {
        let content = "# Just a markdown file\nNo frontmatter here."
        #expect(SkillManifestParser.extractFrontmatter(from: content) == nil)
    }

    @Test("returns nil for content with only opening delimiter")
    func onlyOpeningDelimiter() {
        let content = "---\nname: test\nNo closing delimiter"
        #expect(SkillManifestParser.extractFrontmatter(from: content) == nil)
    }

    // MARK: - YAML Parsing

    @Test("parses simple string scalars")
    func parseStringScalars() {
        let yaml = """
        name: web-scraper
        description: Scrapes web pages
        version: 1.2.3
        """
        let fields = SkillManifestParser.parseYAMLFrontmatter(yaml)
        #expect(fields["name"] as? String == "web-scraper")
        #expect(fields["description"] as? String == "Scrapes web pages")
        #expect(fields["version"] as? String == "1.2.3")
    }

    @Test("parses quoted strings")
    func parseQuotedStrings() {
        let yaml = """
        name: "my skill"
        description: 'A skill with colons: inside'
        """
        let fields = SkillManifestParser.parseYAMLFrontmatter(yaml)
        #expect(fields["name"] as? String == "my skill")
        #expect(fields["description"] as? String == "A skill with colons: inside")
    }

    @Test("parses inline arrays")
    func parseInlineArrays() {
        let yaml = """
        os: [linux, darwin]
        """
        let fields = SkillManifestParser.parseYAMLFrontmatter(yaml)
        let os = fields["os"] as? [String]
        #expect(os == ["linux", "darwin"])
    }

    @Test("parses block arrays")
    func parseBlockArrays() {
        let yaml = """
        os:
          - linux
          - darwin
          - windows
        """
        let fields = SkillManifestParser.parseYAMLFrontmatter(yaml)
        let os = fields["os"] as? [String]
        #expect(os == ["linux", "darwin", "windows"])
    }

    @Test("parses nested objects")
    func parseNestedObjects() {
        let yaml = """
        requires:
          env: [OPENAI_API_KEY, BASE_URL]
          bins: [node, npx]
          install: [npm install]
        """
        let fields = SkillManifestParser.parseYAMLFrontmatter(yaml)
        let requires = fields["requires"] as? [String: Any]
        #expect(requires != nil)
        #expect((requires?["env"] as? [String]) == ["OPENAI_API_KEY", "BASE_URL"])
        #expect((requires?["bins"] as? [String]) == ["node", "npx"])
        #expect((requires?["install"] as? [String]) == ["npm install"])
    }

    @Test("parses nested objects with block arrays")
    func parseNestedBlockArrays() {
        let yaml = """
        requires:
          bins:
            - node
            - npx
          env:
            - API_KEY
        """
        let fields = SkillManifestParser.parseYAMLFrontmatter(yaml)
        let requires = fields["requires"] as? [String: Any]
        #expect(requires != nil)
        #expect((requires?["bins"] as? [String]) == ["node", "npx"])
        #expect((requires?["env"] as? [String]) == ["API_KEY"])
    }

    @Test("skips comments and empty lines")
    func skipsComments() {
        let yaml = """
        # This is a comment
        name: test

        # Another comment
        version: 1.0.0
        """
        let fields = SkillManifestParser.parseYAMLFrontmatter(yaml)
        #expect(fields["name"] as? String == "test")
        #expect(fields["version"] as? String == "1.0.0")
    }

    // MARK: - Full SKILL.md Parsing

    @Test("parses a complete SKILL.md from directory")
    func parseFullSkillMD() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sbbender-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create SKILL.md
        let skillMD = """
        ---
        name: web-scraper
        slug: web-scraper
        description: Scrapes web pages and returns structured data
        version: 1.0.0
        primaryEnv: node
        os: [linux]
        requires:
          env: [OPENAI_API_KEY]
          bins: [node, npx]
          install: [npm install]
        ---
        # Web Scraper

        This skill scrapes web pages using Puppeteer.

        ## Usage

        Pass a URL as input and receive structured data.
        """
        try skillMD.write(to: tempDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        // Create supporting files
        try "console.log('hello')".write(
            to: tempDir.appendingPathComponent("main.mjs"), atomically: true, encoding: .utf8
        )
        try "{}".write(
            to: tempDir.appendingPathComponent("package.json"), atomically: true, encoding: .utf8
        )

        let manifest = try SkillManifestParser.parse(directory: tempDir)

        #expect(manifest.name == "web-scraper")
        #expect(manifest.slug == "web-scraper")
        #expect(manifest.description == "Scrapes web pages and returns structured data")
        #expect(manifest.version == "1.0.0")
        #expect(manifest.primaryEnv == "node")
        #expect(manifest.os == ["linux"])
        #expect(manifest.requirements.env == ["OPENAI_API_KEY"])
        #expect(manifest.requirements.bins == ["node", "npx"])
        #expect(manifest.requirements.install == ["npm install"])
        #expect(manifest.instructions.contains("# Web Scraper"))
        #expect(manifest.instructions.contains("Puppeteer"))
        #expect(manifest.supportingFiles.contains("main.mjs"))
        #expect(manifest.supportingFiles.contains("package.json"))
    }

    @Test("auto-generates slug from name")
    func autoSlug() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sbbender-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let skillMD = """
        ---
        name: My Cool Skill
        description: Does cool things
        ---
        Instructions here.
        """
        try skillMD.write(to: tempDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let manifest = try SkillManifestParser.parse(directory: tempDir)
        #expect(manifest.slug == "my-cool-skill")
    }

    @Test("throws for missing SKILL.md")
    func missingSkillMD() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sbbender-test-\(UUID().uuidString)")

        #expect(throws: SBBenderError.self) {
            try SkillManifestParser.parse(directory: tempDir)
        }
    }

    @Test("throws for missing name field")
    func missingName() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sbbender-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let skillMD = """
        ---
        description: Missing name
        ---
        Body
        """
        try skillMD.write(to: tempDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        #expect(throws: SBBenderError.self) {
            try SkillManifestParser.parse(directory: tempDir)
        }
    }

    // MARK: - String Helpers

    @Test("slugified converts names correctly")
    func slugified() {
        #expect("My Cool Skill".slugified == "my-cool-skill")
        #expect("web-scraper".slugified == "web-scraper")
        #expect("Hello World 123".slugified == "hello-world-123")
        #expect("Special!@#Chars".slugified == "specialchars")
    }

    @Test("unquoted removes surrounding quotes")
    func unquoted() {
        #expect("\"hello\"".unquoted == "hello")
        #expect("'hello'".unquoted == "hello")
        #expect("hello".unquoted == "hello")
        #expect("\"\"".unquoted == "")
    }
}
