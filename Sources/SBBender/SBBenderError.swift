import Foundation

/// All errors thrown by the SBBender runtime.
public enum SBBenderError: LocalizedError, Sendable {
    // Model
    case modelNotLoaded
    case modelNotAvailable(String)
    case generationFailed(String)
    case allProvidersFailed([String])

    // Tool
    case toolNotFound(String)
    case toolExecutionFailed(tool: String, reason: String)
    case invalidArguments(String)
    case toolCallLimitExceeded(Int)

    // Agent
    case agentNotReady(String)
    case runCancelled
    case maxIterationsExceeded(Int)

    // Storage
    case storageError(String)
    case sessionNotFound(String)
    case migrationFailed(String)

    // Knowledge
    case knowledgeInsertFailed(String)
    case knowledgeSearchFailed(String)

    // Skill
    case skillNotAvailable(String)
    case skillExecutionFailed(skill: String, reason: String)

    // Container / OpenClaw
    case containerStartFailed(String)
    case containerExecFailed(skill: String, exitCode: Int32, stderr: String)
    case containerTimeout(skill: String, seconds: TimeInterval)
    case containerNotAvailable(String)
    case skillManifestInvalid(path: String, reason: String)
    case skillInstallFailed(slug: String, reason: String)
    case skillPermissionDenied(skill: String, resource: String)
    case clawHubRegistryError(String)

    // Swarm
    case swarmDelegationFailed(String)
    case memberNotFound(String)

    // Workflow
    case workflowStepFailed(step: String, reason: String)

    // General
    case invalidConfiguration(String)
    case jsonParsingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Model is not loaded"
        case .modelNotAvailable(let name):
            return "Model provider '\(name)' is not available"
        case .generationFailed(let reason):
            return "Generation failed: \(reason)"
        case .allProvidersFailed(let providers):
            return "All providers failed: \(providers.joined(separator: ", "))"
        case .toolNotFound(let name):
            return "Tool '\(name)' not found"
        case .toolExecutionFailed(let tool, let reason):
            return "Tool '\(tool)' execution failed: \(reason)"
        case .invalidArguments(let reason):
            return "Invalid arguments: \(reason)"
        case .toolCallLimitExceeded(let limit):
            return "Tool call limit exceeded: \(limit)"
        case .agentNotReady(let reason):
            return "Agent not ready: \(reason)"
        case .runCancelled:
            return "Run was cancelled"
        case .maxIterationsExceeded(let max):
            return "Maximum iterations exceeded: \(max)"
        case .storageError(let reason):
            return "Storage error: \(reason)"
        case .sessionNotFound(let id):
            return "Session '\(id)' not found"
        case .migrationFailed(let reason):
            return "Migration failed: \(reason)"
        case .knowledgeInsertFailed(let reason):
            return "Knowledge insert failed: \(reason)"
        case .knowledgeSearchFailed(let reason):
            return "Knowledge search failed: \(reason)"
        case .skillNotAvailable(let name):
            return "Skill '\(name)' not available"
        case .skillExecutionFailed(let skill, let reason):
            return "Skill '\(skill)' execution failed: \(reason)"
        case .containerStartFailed(let reason):
            return "Container start failed: \(reason)"
        case .containerExecFailed(let skill, let exitCode, let stderr):
            return "Container exec failed for '\(skill)' (exit \(exitCode)): \(stderr)"
        case .containerTimeout(let skill, let seconds):
            return "Container timed out for '\(skill)' after \(seconds)s"
        case .containerNotAvailable(let reason):
            return "Container runtime not available: \(reason)"
        case .skillManifestInvalid(let path, let reason):
            return "Invalid skill manifest at '\(path)': \(reason)"
        case .skillInstallFailed(let slug, let reason):
            return "Failed to install skill '\(slug)': \(reason)"
        case .skillPermissionDenied(let skill, let resource):
            return "Permission denied for skill '\(skill)': \(resource)"
        case .clawHubRegistryError(let reason):
            return "ClawHub registry error: \(reason)"
        case .swarmDelegationFailed(let reason):
            return "Swarm delegation failed: \(reason)"
        case .memberNotFound(let name):
            return "Swarm member '\(name)' not found"
        case .workflowStepFailed(let step, let reason):
            return "Workflow step '\(step)' failed: \(reason)"
        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"
        case .jsonParsingFailed(let reason):
            return "JSON parsing failed: \(reason)"
        }
    }
}
