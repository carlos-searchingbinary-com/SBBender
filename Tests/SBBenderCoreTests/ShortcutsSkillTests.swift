import Testing
@testable import SBBenderCore

@Suite("ShortcutsSkill Tests")
struct ShortcutsSkillTests {

    @Test("Skill availability check")
    func availability() async {
        let skill = ShortcutsSkill()
        let available = await skill.isAvailable
        // /usr/bin/shortcuts exists on macOS
        #expect(available == true)
    }

    @Test("List shortcuts")
    func listShortcuts() async throws {
        let skill = ShortcutsSkill()
        let result = try await skill.execute(input: .text("list"))
        // Result should contain some output (might be empty list)
        #expect(result.structuredData["action"] == "list")
        #expect(result.confidence == 1.0)
        #expect(result.latency > 0)
    }

    @Test("Skill converts to tool")
    func skillToTool() {
        let skill = ShortcutsSkill()
        let tool = skill.asTool()
        #expect(tool.name == "runShortcut")
        #expect(!tool.description.isEmpty)
    }

    @Test("Missing shortcut name throws")
    func missingName() async throws {
        let skill = ShortcutsSkill()
        do {
            _ = try await skill.execute(input: .text(""))
            #expect(Bool(false), "Expected error")
        } catch {
            #expect(error is SBBenderError)
        }
    }
}
