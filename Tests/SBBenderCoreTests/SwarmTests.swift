import Testing
import Foundation
@testable import SBBenderCore

@Suite("Swarm Tests")
struct SwarmTests {

    @Test("Sequential swarm execution")
    func testSequential() async throws {
        let agent1 = Agent(
            configuration: AgentConfiguration(name: "Summarizer"),
            model: MockProvider(responses: ["Summary: The text discusses AI."])
        )
        let agent2 = Agent(
            configuration: AgentConfiguration(name: "Translator"),
            model: MockProvider(responses: ["Resumen: El texto habla sobre IA."])
        )

        let swarm = Swarm(
            name: "Pipeline",
            mode: .sequential,
            members: [agent1, agent2]
        )

        let result = try await swarm.run("Translate this summary of AI")
        #expect(result.memberResults.count == 2)
        #expect(result.content.contains("Summary") || result.content.contains("Resumen"))
    }

    @Test("Parallel swarm execution")
    func testParallel() async throws {
        let agent1 = Agent(
            configuration: AgentConfiguration(name: "Fast"),
            model: MockProvider(responses: ["Result A"])
        )
        let agent2 = Agent(
            configuration: AgentConfiguration(name: "Slow"),
            model: MockProvider(responses: ["Result B"])
        )

        let swarm = Swarm(
            name: "Parallel",
            mode: .parallel,
            members: [agent1, agent2]
        )

        let result = try await swarm.run("Process this")
        #expect(result.memberResults.count == 2)
        #expect(result.content.contains("Result A") || result.content.contains("Result B"))
    }

    @Test("Routed swarm execution")
    func testRouted() async throws {
        let codeAgent = Agent(
            id: "code-agent",
            configuration: AgentConfiguration(name: "Coder"),
            model: MockProvider(responses: ["func hello() {}"])
        )
        let chatAgent = Agent(
            id: "chat-agent",
            configuration: AgentConfiguration(name: "Chatter"),
            model: MockProvider(responses: ["Hello! How are you?"])
        )

        let swarm = Swarm(
            name: "Router",
            mode: .route { input in
                input.lowercased().contains("code") ? "code-agent" : "chat-agent"
            },
            members: [codeAgent, chatAgent]
        )

        let codeResult = try await swarm.run("Write me some code")
        #expect(codeResult.memberResults.count == 1)
        #expect(codeResult.content.contains("func"))

        let chatResult = try await swarm.run("Hello there")
        #expect(chatResult.content.contains("Hello"))
    }

    @Test("Autonomous swarm with leader")
    func testAutonomous() async throws {
        let leader = Agent(
            configuration: AgentConfiguration(name: "Leader"),
            model: MockProvider(responses: ["I'll handle this myself: The answer is 42."])
        )
        let worker = Agent(
            id: "worker-1",
            configuration: AgentConfiguration(name: "Worker"),
            model: MockProvider(responses: ["Working..."])
        )

        let swarm = Swarm(
            name: "AutoSwarm",
            mode: .autonomous,
            leader: leader,
            members: [worker]
        )

        let result = try await swarm.run("What is the answer?")
        // Leader didn't delegate (no DELEGATE: prefix), so its response is the result
        #expect(!result.memberResults.isEmpty)
    }

    @Test("Autonomous swarm requires leader")
    func testAutonomousRequiresLeader() async {
        let agent = Agent(
            configuration: AgentConfiguration(name: "Solo"),
            model: MockProvider()
        )

        let swarm = Swarm(
            name: "NoLeader",
            mode: .autonomous,
            members: [agent]
        )

        await #expect(throws: SBBenderError.self) {
            try await swarm.run("Test")
        }
    }
}
