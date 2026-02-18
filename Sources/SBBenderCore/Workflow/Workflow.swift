import Foundation

/// Input/output for a workflow step.
public struct StepIO: Sendable {
    public var text: String
    public var data: [String: String]

    public init(text: String = "", data: [String: String] = [:]) {
        self.text = text
        self.data = data
    }

    public static func text(_ text: String) -> StepIO {
        StepIO(text: text)
    }
}

/// A single executable step in a workflow.
public protocol WorkflowStep: Sendable {
    var name: String { get }
    func execute(input: StepIO) async throws -> StepIO
}

// MARK: - Step Implementations

/// A step that runs an agent.
public struct AgentStep: WorkflowStep {
    public let name: String
    public let agent: Agent

    public init(name: String, agent: Agent) {
        self.name = name
        self.agent = agent
    }

    public func execute(input: StepIO) async throws -> StepIO {
        let result = try await agent.run(input.text)
        return StepIO(text: result.content, data: input.data)
    }
}

/// A step that runs a custom async function.
public struct FunctionStep: WorkflowStep {
    public let name: String
    private let _execute: @Sendable (StepIO) async throws -> StepIO

    public init(name: String, execute: @escaping @Sendable (StepIO) async throws -> StepIO) {
        self.name = name
        self._execute = execute
    }

    public func execute(input: StepIO) async throws -> StepIO {
        try await _execute(input)
    }
}

/// A composite step that runs sub-steps sequentially.
public struct SequentialSteps: WorkflowStep {
    public let name: String
    public let steps: [any WorkflowStep]

    public init(name: String, steps: [any WorkflowStep]) {
        self.name = name
        self.steps = steps
    }

    public func execute(input: StepIO) async throws -> StepIO {
        var current = input
        for step in steps {
            Log.workflow.debug("Sequential step: \(step.name)")
            current = try await step.execute(input: current)
        }
        return current
    }
}

/// A composite step that runs sub-steps concurrently and merges results.
public struct ParallelSteps: WorkflowStep {
    public let name: String
    public let steps: [any WorkflowStep]
    private let merge: @Sendable ([StepIO]) -> StepIO

    public init(
        name: String,
        steps: [any WorkflowStep],
        merge: @escaping @Sendable ([StepIO]) -> StepIO = { results in
            StepIO(text: results.map(\.text).joined(separator: "\n\n"))
        }
    ) {
        self.name = name
        self.steps = steps
        self.merge = merge
    }

    public func execute(input: StepIO) async throws -> StepIO {
        let results = try await withThrowingTaskGroup(of: StepIO.self) { group in
            for step in steps {
                group.addTask {
                    try await step.execute(input: input)
                }
            }

            var collected: [StepIO] = []
            for try await result in group {
                collected.append(result)
            }
            return collected
        }

        return merge(results)
    }
}

/// A step that loops until a condition is met.
public struct LoopStep: WorkflowStep {
    public let name: String
    public let step: any WorkflowStep
    public let maxIterations: Int
    private let shouldContinue: @Sendable (StepIO, Int) -> Bool

    public init(
        name: String,
        step: any WorkflowStep,
        maxIterations: Int = 10,
        shouldContinue: @escaping @Sendable (StepIO, Int) -> Bool
    ) {
        self.name = name
        self.step = step
        self.maxIterations = maxIterations
        self.shouldContinue = shouldContinue
    }

    public func execute(input: StepIO) async throws -> StepIO {
        var current = input
        for iteration in 0..<maxIterations {
            current = try await step.execute(input: current)
            if !shouldContinue(current, iteration) {
                break
            }
        }
        return current
    }
}

/// A step that branches based on a condition.
public struct ConditionalStep: WorkflowStep {
    public let name: String
    private let condition: @Sendable (StepIO) -> Bool
    public let ifTrue: any WorkflowStep
    public let ifFalse: any WorkflowStep

    public init(
        name: String,
        condition: @escaping @Sendable (StepIO) -> Bool,
        ifTrue: any WorkflowStep,
        ifFalse: any WorkflowStep
    ) {
        self.name = name
        self.condition = condition
        self.ifTrue = ifTrue
        self.ifFalse = ifFalse
    }

    public func execute(input: StepIO) async throws -> StepIO {
        if condition(input) {
            return try await ifTrue.execute(input: input)
        } else {
            return try await ifFalse.execute(input: input)
        }
    }
}

/// A step that routes to one of several sub-steps.
public struct RouterStep: WorkflowStep {
    public let name: String
    private let routes: [String: any WorkflowStep]
    private let router: @Sendable (StepIO) -> String
    private let defaultStep: (any WorkflowStep)?

    public init(
        name: String,
        router: @escaping @Sendable (StepIO) -> String,
        routes: [String: any WorkflowStep],
        defaultStep: (any WorkflowStep)? = nil
    ) {
        self.name = name
        self.router = router
        self.routes = routes
        self.defaultStep = defaultStep
    }

    public func execute(input: StepIO) async throws -> StepIO {
        let routeKey = router(input)
        if let step = routes[routeKey] {
            return try await step.execute(input: input)
        } else if let defaultStep {
            return try await defaultStep.execute(input: input)
        } else {
            throw SBBenderError.workflowStepFailed(step: name, reason: "No route found for '\(routeKey)'")
        }
    }
}

// MARK: - Workflow

/// Orchestrates a sequence of steps into a complete pipeline.
///
/// A Workflow is a structured, deterministic execution plan. Unlike a Swarm
/// (which uses LLM reasoning for delegation), a Workflow follows a predetermined
/// graph of steps.
public actor Workflow {
    public let id: String
    public let name: String
    private let rootStep: any WorkflowStep
    private var storage: (any StorageBackend)?

    public init(
        id: String = UUID().uuidString,
        name: String = "Workflow",
        step: any WorkflowStep,
        storage: (any StorageBackend)? = nil
    ) {
        self.id = id
        self.name = name
        self.rootStep = step
        self.storage = storage
    }

    /// Execute the workflow with the given input.
    public func run(_ input: String) async throws -> WorkflowResult {
        let start = CFAbsoluteTimeGetCurrent()
        let runID = UUID().uuidString

        Log.workflow.info("Workflow '\(self.name)' starting run \(runID)")

        let output = try await rootStep.execute(input: .text(input))
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        Log.workflow.info("Workflow '\(self.name)' completed in \(String(format: "%.2f", elapsed))s")

        return WorkflowResult(
            runID: runID,
            workflowID: id,
            output: output,
            latency: elapsed
        )
    }
}

/// Result of a workflow execution.
public struct WorkflowResult: Sendable {
    public let runID: String
    public let workflowID: String
    public let output: StepIO
    public let latency: TimeInterval

    public init(runID: String, workflowID: String, output: StepIO, latency: TimeInterval) {
        self.runID = runID
        self.workflowID = workflowID
        self.output = output
        self.latency = latency
    }
}
