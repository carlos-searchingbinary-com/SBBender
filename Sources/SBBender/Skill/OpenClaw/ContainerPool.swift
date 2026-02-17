import Foundation
import os

#if canImport(Containerization)
import Containerization
import ContainerizationExtras
import ContainerizationOCI
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

    #if canImport(Containerization)
    /// The container manager used to create Linux containers.
    /// Set via ``setContainerManager(_:)`` before calling ``acquire(profile:)``.
    private var containerManager: ContainerManager?
    #endif

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

    #if canImport(Containerization)
    /// Set the ContainerManager used to create Linux containers.
    ///
    /// Must be called before ``acquire(profile:)``. The manager handles VM lifecycle
    /// and OCI image pulling internally.
    public func setContainerManager(_ manager: ContainerManager) {
        self.containerManager = manager
    }
    #endif

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
        throw SBBenderError.containerNotAvailable("Containerized skills require macOS 26 or later with Apple Containerization support.")
        #endif
    }

    #if canImport(Containerization)
    private func createLinuxContainer(id: String, profile: ContainerProfile) async throws -> ManagedContainer {
        guard var manager = containerManager else {
            throw SBBenderError.containerNotAvailable(
                "Linux container runtime not configured. Containerized skills require a Linux kernel to be set up. This is an advanced feature — most skills work without containers."
            )
        }

        let reference = profile.imageReference
        let rootfsSize: UInt64 = 2048 * 1024 * 1024 // 2 GB

        let container = try await manager.create(
            id,
            reference: reference,
            rootfsSizeInBytes: rootfsSize
        ) { config in
            config.cpus = profile.cpus
            config.memoryInBytes = profile.memoryMB * 1024 * 1024
            config.hostname = id

            config.process.arguments = ["/bin/sh"]
            config.process.workingDirectory = "/"
            config.process.environmentVariables = [
                "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
                "HOME=/root",
                "LANG=C.UTF-8",
            ]

            if profile.needsNetwork {
                config.interfaces.append(try NATInterface(
                    ipv4Address: try CIDRv4("192.168.64.2/24"),
                    ipv4Gateway: try IPv4Address("192.168.64.1")
                ))
                config.dns = DNS(nameservers: ["8.8.8.8", "1.1.1.1"])
            }
        }

        try await container.create()
        try await container.start()

        self.containerManager = manager
        Log.container.info("Linux container \(id) started with image \(reference)")
        return ManagedContainer(id: id, profile: profile, container: container)
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
            // Clean up the container from the manager
            if var manager = containerManager {
                try? manager.delete(container.id)
                self.containerManager = manager
            }
        }
        #endif
    }
}
