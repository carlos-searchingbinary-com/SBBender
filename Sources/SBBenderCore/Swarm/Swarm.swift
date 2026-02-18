import Foundation

/// Execution mode for a swarm of agents.
public enum SwarmMode: Sendable {
    /// The leader agent decides which members to delegate to via LLM reasoning.
    case autonomous
    /// Execute all members in the given order.
    case sequential
    /// Execute all members concurrently using TaskGroup.
    case parallel
    /// Route to a specific member based on the router function.
    case route(@Sendable (String) async -> String?)
}

/// A swarm coordinates multiple agents working together.
///
/// Swarms support four execution modes: autonomous (LLM-directed),
/// sequential, parallel, and routed. The swarm maintains its own
/// session and can optionally have a leader agent that orchestrates.
public actor Swarm {
    public let id: String
    public let name: String
    public let mode: SwarmMode
    public let leader: Agent?
    private var members: [String: Agent]
    private var memberOrder: [String]
    public let maxIterations: Int

    public init(
        id: String = UUID().uuidString,
        name: String = "Swarm",
        mode: SwarmMode = .sequential,
        leader: Agent? = nil,
        members: [Agent],
        maxIterations: Int = 10
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.leader = leader
        self.maxIterations = maxIterations

        var dict: [String: Agent] = [:]
        var order: [String] = []
        for m in members {
            // Use the agent's configuration name as the key for routing
            let key = m.id
            dict[key] = m
            order.append(key)
        }
        self.members = dict
        self.memberOrder = order
    }

    /// Run the swarm with the given input.
    public func run(_ input: String) async throws -> SwarmResult {
        let start = CFAbsoluteTimeGetCurrent()
        let runID = UUID().uuidString

        Log.swarm.info("Swarm '\(self.name)' starting run \(runID) in mode: \(String(describing: self.mode))")

        let memberResults: [RunResult]

        switch mode {
        case .sequential:
            memberResults = try await runSequential(input)
        case .parallel:
            memberResults = try await runParallel(input)
        case .autonomous:
            memberResults = try await runAutonomous(input)
        case .route(let router):
            memberResults = try await runRouted(input, router: router)
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - start

        // Aggregate content from all members
        let aggregatedContent = memberResults.map(\.content).joined(separator: "\n\n")

        var aggregatedMetrics = RunMetrics()
        for r in memberResults {
            aggregatedMetrics.totalInputTokens += r.metrics.totalInputTokens
            aggregatedMetrics.totalOutputTokens += r.metrics.totalOutputTokens
            aggregatedMetrics.totalTokens += r.metrics.totalTokens
            aggregatedMetrics.modelCalls += r.metrics.modelCalls
            aggregatedMetrics.toolCalls += r.metrics.toolCalls
        }
        aggregatedMetrics.totalLatency = elapsed

        return SwarmResult(
            runID: runID,
            swarmID: id,
            content: aggregatedContent,
            memberResults: memberResults,
            metrics: aggregatedMetrics
        )
    }

    // MARK: - Execution Modes

    private func runSequential(_ input: String) async throws -> [RunResult] {
        var results: [RunResult] = []
        var currentInput = input

        for key in memberOrder {
            guard let member = members[key] else { continue }
            let result = try await member.run(currentInput)
            currentInput = result.content // Chain: output of one is input to next
            results.append(result)
        }

        return results
    }

    private func runParallel(_ input: String) async throws -> [RunResult] {
        let indexed = try await withThrowingTaskGroup(of: (Int, RunResult).self) { group in
            for (i, key) in memberOrder.enumerated() {
                guard let member = members[key] else { continue }
                let index = i
                group.addTask {
                    (index, try await member.run(input))
                }
            }

            var results: [(Int, RunResult)] = []
            for try await r in group {
                results.append(r)
            }
            return results
        }
        return indexed.sorted { $0.0 < $1.0 }.map(\.1)
    }

    private func runAutonomous(_ input: String) async throws -> [RunResult] {
        guard let leader else {
            throw SBBenderError.swarmDelegationFailed("Autonomous mode requires a leader agent")
        }

        // Collect member results from delegation calls
        let delegationResults = DelegationResultStore()

        // Build member descriptions for the system prompt
        var memberDescriptions: [String] = []
        for key in memberOrder {
            guard let member = members[key] else { continue }
            let name = await member.configuration.name
            memberDescriptions.append(name)
        }
        let memberList = memberDescriptions.joined(separator: ", ")

        // Create a delegate_to tool that the leader calls to assign work
        let capturedMembers = members
        let capturedMemberOrder = memberOrder
        let delegateTool = Tool(
            name: "delegate_to",
            description: "Delegate a task to a team member. Available members: \(memberList)",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "member_name": PropertySchema(type: "string", description: "Name of the team member to delegate to. One of: \(memberList)"),
                    "task": PropertySchema(type: "string", description: "The specific task or instruction for this member"),
                ],
                required: ["member_name", "task"]
            )
        ) { arguments, _ in
            // Parse arguments
            guard let data = arguments.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let memberName = json["member_name"] as? String,
                  let task = json["task"] as? String else {
                return "Error: invalid arguments. Provide member_name and task."
            }

            // Find member by configuration name (case-insensitive)
            var targetAgent: Agent?
            for key in capturedMemberOrder {
                guard let member = capturedMembers[key] else { continue }
                let name = await member.configuration.name
                if name.lowercased() == memberName.lowercased() {
                    targetAgent = member
                    break
                }
            }

            guard let member = targetAgent else {
                return "Error: member '\(memberName)' not found. Available: \(memberList)"
            }

            let result = try await member.run(task)
            await delegationResults.add(result)
            return result.content
        }

        // Register the delegation tool on the leader
        await leader.addTool(delegateTool)

        // Run the leader with context about its role
        let prompt = """
        You are the leader of a team with these members: \(memberList)

        Use the delegate_to tool to assign tasks to team members. You can delegate to one or more members. After receiving their results, synthesize a final answer.

        Task: \(input)
        """

        let leaderResult = try await leader.run(prompt)
        var results = await delegationResults.all

        // Always include the leader's final synthesis
        results.append(leaderResult)

        return results
    }

    private func runRouted(_ input: String, router: @Sendable (String) async -> String?) async throws -> [RunResult] {
        guard let targetID = await router(input) else {
            throw SBBenderError.swarmDelegationFailed("Router returned no target for input")
        }

        guard let member = members[targetID] else {
            throw SBBenderError.memberNotFound(targetID)
        }

        let result = try await member.run(input)
        return [result]
    }
}

/// Thread-safe store for collecting delegation results from tool calls.
private actor DelegationResultStore {
    private var results: [RunResult] = []

    func add(_ result: RunResult) {
        results.append(result)
    }

    var all: [RunResult] {
        results
    }
}

/// Result of a swarm run, containing individual member results.
public struct SwarmResult: Sendable {
    public let runID: String
    public let swarmID: String
    public let content: String
    public let memberResults: [RunResult]
    public let metrics: RunMetrics

    public init(
        runID: String,
        swarmID: String,
        content: String,
        memberResults: [RunResult],
        metrics: RunMetrics
    ) {
        self.runID = runID
        self.swarmID = swarmID
        self.content = content
        self.memberResults = memberResults
        self.metrics = metrics
    }
}
