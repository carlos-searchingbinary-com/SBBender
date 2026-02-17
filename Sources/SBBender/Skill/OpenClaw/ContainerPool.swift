import Foundation
import os

#if canImport(Containerization)
import Containerization
#endif

/// A managed container handle returned by the pool.
@available(macOS 26, *)
public struct ManagedContainer: Sendable {
    /// Unique identifier for this container instance.
    public let id: String
    /// The profile this container was created for.
    public let profile: ContainerProfile
    /// When the container was created.
    public let createdAt: Date
    /// Number of times this container has been used for execution.
    public internal(set) var executionCount: Int

    #if canImport(Containerization)
    /// The underlying Containerization container (nil for testing/non-container contexts).
    let container: LinuxContainer?
    #endif

    public init(id: String, profile: ContainerProfile, createdAt: Date = Date(), executionCount: Int = 0) {
        self.id = id
        self.profile = profile
        self.createdAt = createdAt
        self.executionCount = executionCount
        #if canImport(Containerization)
        self.container = nil
        #endif
    }

    #if canImport(Containerization)
    init(id: String, profile: ContainerProfile, container: LinuxContainer) {
        self.id = id
        self.profile = profile
        self.createdAt = Date()
        self.executionCount = 0
        self.container = container
    }
    #endif
}

/// Actor-based pool for warm container reuse.
///
/// Containers are keyed by ``ContainerProfile``. The pool maintains warm containers
/// ready for immediate use, avoiding cold-start latency for repeated skill executions.
///
/// Containers are destroyed when they exceed ``maxAge`` or ``maxExecutions``.
@available(macOS 26, *)
public actor ContainerPool {
    /// Maximum number of warm containers in the pool.
    public let maxPoolSize: Int
    /// Maximum age of a pooled container before it's destroyed on release.
    public let maxAge: TimeInterval
    /// Maximum number of executions per container before it's destroyed on release.
    public let maxExecutions: Int

    private let imageManager: ContainerImageManager
    private var pool: [ContainerProfile: [ManagedContainer]] = [:]
    private var activeCount: Int = 0

    public init(
        imageManager: ContainerImageManager,
        maxPoolSize: Int = 4,
        maxAge: TimeInterval = 300,  // 5 minutes
        maxExecutions: Int = 10
    ) {
        self.imageManager = imageManager
        self.maxPoolSize = maxPoolSize
        self.maxAge = maxAge
        self.maxExecutions = maxExecutions
    }

    /// Acquire a container matching the given profile.
    ///
    /// Returns a warm container from the pool if available, or creates a new one.
    public func acquire(profile: ContainerProfile) async throws -> ManagedContainer {
        // Try to get a warm container from the pool
        if var containers = pool[profile], !containers.isEmpty {
            var container = containers.removeLast()
            if containers.isEmpty {
                pool.removeValue(forKey: profile)
            } else {
                pool[profile] = containers
            }
            container.executionCount += 1
            activeCount += 1
            Log.container.debug("Reusing warm container \(container.id) for profile \(profile.baseImage.rawValue)")
            return container
        }

        // No warm container available — create a new one
        let container = try await createContainer(profile: profile)
        activeCount += 1
        Log.container.info("Created new container \(container.id) for profile \(profile.baseImage.rawValue)")
        return container
    }

    /// Release a container back to the pool.
    ///
    /// If the container has exceeded max age or executions, it's destroyed instead.
    public func release(_ container: ManagedContainer) async {
        activeCount -= 1
        let age = Date().timeIntervalSince(container.createdAt)

        if age > maxAge || container.executionCount >= maxExecutions {
            Log.container.debug("Destroying container \(container.id) (age: \(age)s, execs: \(container.executionCount))")
            await destroyContainer(container)
            return
        }

        // Return to pool if under capacity
        let currentPoolCount = pool.values.reduce(0) { $0 + $1.count }
        if currentPoolCount >= maxPoolSize {
            Log.container.debug("Pool full, destroying container \(container.id)")
            await destroyContainer(container)
            return
        }

        pool[container.profile, default: []].append(container)
        Log.container.debug("Container \(container.id) returned to pool")
    }

    /// Pre-warm containers for the given profiles.
    public func warmUp(profiles: [ContainerProfile]) async throws {
        for profile in profiles {
            try await imageManager.ensureImage(for: profile)
            let container = try await createContainer(profile: profile)
            pool[profile, default: []].append(container)
            Log.container.info("Warmed container for profile \(profile.baseImage.rawValue)")
        }
    }

    /// Destroy all pooled containers and reset the pool.
    public func drainAll() async {
        for (_, containers) in pool {
            for container in containers {
                await destroyContainer(container)
            }
        }
        pool.removeAll()
        Log.container.info("Container pool drained")
    }

    /// Current number of warm containers in the pool.
    public var warmCount: Int {
        pool.values.reduce(0) { $0 + $1.count }
    }

    /// Current number of containers in active use.
    public var activeContainerCount: Int {
        activeCount
    }

    // MARK: - Private

    private func createContainer(profile: ContainerProfile) async throws -> ManagedContainer {
        try await imageManager.ensureImage(for: profile)
        let id = "sbb-\(profile.baseImage.rawValue)-\(UUID().uuidString.prefix(8))"

        #if canImport(Containerization)
        return try await createLinuxContainer(id: id, profile: profile)
        #else
        throw SBBenderError.containerNotAvailable("Containerization framework not available")
        #endif
    }

    #if canImport(Containerization)
    private func createLinuxContainer(id: String, profile: ContainerProfile) async throws -> ManagedContainer {
        // Create container using Apple Containerization framework
        // This is a placeholder — the actual API calls depend on the VirtualMachineManager
        // instance and image store setup which happens at the application level.
        throw SBBenderError.containerNotAvailable(
            "Container creation requires VirtualMachineManager — use ContainerizedSkill.execute() for managed lifecycle"
        )
    }
    #endif

    private func destroyContainer(_ container: ManagedContainer) async {
        #if canImport(Containerization)
        if let linuxContainer = container.container {
            do {
                try await linuxContainer.stop()
            } catch {
                Log.container.warning("Failed to stop container \(container.id): \(error)")
            }
        }
        #endif
    }
}
