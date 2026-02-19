import Testing
import Foundation
@testable import SBBenderCore

@Suite("Workflow Tests")
struct WorkflowTests {

    @Test("Simple function step")
    func testFunctionStep() async throws {
        let step = FunctionStep(name: "uppercase") { input in
            StepIO(text: input.text.uppercased(), data: input.data)
        }

        let result = try await step.execute(input: .text("hello"))
        #expect(result.text == "HELLO")
    }

    @Test("Sequential steps")
    func testSequentialSteps() async throws {
        let step = SequentialSteps(
            name: "pipeline",
            steps: [
                FunctionStep(name: "step1") { input in
                    StepIO(text: input.text + " world")
                },
                FunctionStep(name: "step2") { input in
                    StepIO(text: input.text.uppercased())
                },
            ]
        )

        let result = try await step.execute(input: .text("hello"))
        #expect(result.text == "HELLO WORLD")
    }

    @Test("Parallel steps with merge")
    func testParallelSteps() async throws {
        let step = ParallelSteps(
            name: "parallel",
            steps: [
                FunctionStep(name: "a") { _ in StepIO(text: "Result A") },
                FunctionStep(name: "b") { _ in StepIO(text: "Result B") },
            ]
        )

        let result = try await step.execute(input: .text("input"))
        #expect(result.text.contains("Result A") || result.text.contains("Result B"))
    }

    @Test("Conditional step - true branch")
    func testConditionalTrue() async throws {
        let step = ConditionalStep(
            name: "check",
            condition: { $0.text.contains("yes") },
            ifTrue: FunctionStep(name: "true") { _ in StepIO(text: "Took true branch") },
            ifFalse: FunctionStep(name: "false") { _ in StepIO(text: "Took false branch") }
        )

        let result = try await step.execute(input: .text("yes please"))
        #expect(result.text == "Took true branch")
    }

    @Test("Conditional step - false branch")
    func testConditionalFalse() async throws {
        let step = ConditionalStep(
            name: "check",
            condition: { $0.text.contains("yes") },
            ifTrue: FunctionStep(name: "true") { _ in StepIO(text: "Took true branch") },
            ifFalse: FunctionStep(name: "false") { _ in StepIO(text: "Took false branch") }
        )

        let result = try await step.execute(input: .text("no thanks"))
        #expect(result.text == "Took false branch")
    }

    @Test("Loop step with condition")
    func testLoopStep() async throws {
        let step = LoopStep(
            name: "counter",
            step: FunctionStep(name: "increment") { input in
                let current = Int(input.text) ?? 0
                return StepIO(text: "\(current + 1)", data: input.data)
            },
            maxIterations: 10,
            shouldContinue: { output, _ in
                (Int(output.text) ?? 0) < 5
            }
        )

        let result = try await step.execute(input: .text("0"))
        #expect(result.text == "5")
    }

    @Test("Router step")
    func testRouterStep() async throws {
        let step = RouterStep(
            name: "router",
            router: { input in
                input.text.contains("code") ? "coder" : "writer"
            },
            routes: [
                "coder": FunctionStep(name: "code") { _ in StepIO(text: "```swift\nprint(\"hello\")```") },
                "writer": FunctionStep(name: "write") { _ in StepIO(text: "A beautifully written essay") },
            ]
        )

        let codeResult = try await step.execute(input: .text("write some code"))
        #expect(codeResult.text.contains("swift"))

        let writeResult = try await step.execute(input: .text("write an essay"))
        #expect(writeResult.text.contains("essay"))
    }

    @Test("Router step with default")
    func testRouterDefault() async throws {
        let step = RouterStep(
            name: "router",
            router: { _ in "unknown" },
            routes: ["known": FunctionStep(name: "k") { _ in StepIO(text: "known") }],
            defaultStep: FunctionStep(name: "default") { _ in StepIO(text: "default response") }
        )

        let result = try await step.execute(input: .text("anything"))
        #expect(result.text == "default response")
    }

    @Test("Router step throws when no route and no default")
    func testRouterNoDefault() async {
        let step = RouterStep(
            name: "router",
            router: { _ in "missing" },
            routes: ["existing": FunctionStep(name: "e") { _ in StepIO(text: "x") }]
        )

        await #expect(throws: SBBenderError.self) {
            try await step.execute(input: .text("test"))
        }
    }

    @Test("Agent step integration")
    func testAgentStep() async throws {
        let agent = Agent(
            configuration: AgentConfiguration(name: "StepAgent"),
            model: MockProvider(responses: ["Processed output"])
        )

        let step = AgentStep(name: "agent-step", agent: agent)
        let result = try await step.execute(input: .text("Process this"))
        #expect(result.text == "Processed output")
    }

    @Test("Full workflow execution")
    func testFullWorkflow() async throws {
        let workflow = Workflow(
            name: "TestWorkflow",
            step: SequentialSteps(
                name: "main",
                steps: [
                    FunctionStep(name: "prepare") { input in
                        StepIO(text: "Prepared: \(input.text)")
                    },
                    FunctionStep(name: "process") { input in
                        StepIO(text: input.text.uppercased())
                    },
                ]
            )
        )

        let result = try await workflow.run("hello")
        #expect(result.output.text == "PREPARED: HELLO")
        #expect(result.latency > 0)
    }
}
