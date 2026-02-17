import Foundation

/// Permission model for containerized OpenClaw skills.
///
/// By default, skills run with maximum restriction:
/// - No environment variables exposed
/// - No network access
/// - 30 second timeout
/// - 1 MB output limit
///
/// Users must explicitly approve permissions via ``SkillPermissionDelegate``.
public struct SkillPermissions: Sendable, Codable, Equatable {
    /// Only user-approved environment variable key-value pairs are injected into the container.
    public var approvedEnvVars: [String: String]
    /// Whether the container has network access. Default: `false`.
    public var networkAccess: Bool
    /// Maximum execution time before the container is killed. Default: 30s.
    public var timeoutSeconds: TimeInterval
    /// Maximum bytes of stdout/stderr captured. Default: 1 MB.
    public var maxOutputBytes: Int

    public static let defaultTimeout: TimeInterval = 30
    public static let defaultMaxOutput: Int = 1_048_576 // 1 MB

    public init(
        approvedEnvVars: [String: String] = [:],
        networkAccess: Bool = false,
        timeoutSeconds: TimeInterval = SkillPermissions.defaultTimeout,
        maxOutputBytes: Int = SkillPermissions.defaultMaxOutput
    ) {
        self.approvedEnvVars = approvedEnvVars
        self.networkAccess = networkAccess
        self.timeoutSeconds = timeoutSeconds
        self.maxOutputBytes = maxOutputBytes
    }

    /// A fully locked-down permission set. No env vars, no network, 30s timeout.
    public static let locked = SkillPermissions()
}

/// Delegate that the host app implements to approve or deny skill permission requests.
///
/// Called during skill installation or first execution when the skill declares
/// requirements that need user consent.
public protocol SkillPermissionDelegate: Sendable {
    /// Approve which environment variables (and their values) to expose to a skill.
    ///
    /// - Parameters:
    ///   - skill: The skill's slug/name requesting the variables.
    ///   - requested: The env var names declared in the skill manifest.
    /// - Returns: A dictionary of approved key-value pairs. Return empty to deny all.
    func approveEnvironmentVariables(
        skill: String,
        requested: [String]
    ) async -> [String: String]

    /// Approve whether a skill may have network access inside its container.
    ///
    /// - Parameter skill: The skill's slug/name requesting network access.
    /// - Returns: `true` to allow network access, `false` to deny.
    func approveNetworkAccess(skill: String) async -> Bool
}

/// A default delegate that denies all permission requests.
public struct DenyAllPermissionDelegate: SkillPermissionDelegate {
    public init() {}

    public func approveEnvironmentVariables(skill: String, requested: [String]) async -> [String: String] {
        [:]
    }

    public func approveNetworkAccess(skill: String) async -> Bool {
        false
    }
}

/// A delegate that auto-approves all permission requests. Use only for testing.
public struct AllowAllPermissionDelegate: SkillPermissionDelegate {
    public let envVars: [String: String]

    public init(envVars: [String: String] = [:]) {
        self.envVars = envVars
    }

    public func approveEnvironmentVariables(skill: String, requested: [String]) async -> [String: String] {
        var approved: [String: String] = [:]
        for key in requested {
            if let value = envVars[key] {
                approved[key] = value
            }
        }
        return approved
    }

    public func approveNetworkAccess(skill: String) async -> Bool {
        true
    }
}
