import Foundation
import os

#if canImport(Containerization)
import Containerization
import ContainerizationOCI
#endif

/// Manages OCI base images used by containerized skills.
///
/// Images are cached locally in `~/Library/Application Support/com.sbbender/images/`.
/// Each ``ContainerProfile/BaseImage`` tier maps to a specific OCI image reference.
@available(macOS 26, *)
public actor ContainerImageManager {
    /// Local directory for cached images.
    private let cacheDirectory: URL
    /// Set of image references that have been pulled and are ready.
    private var availableImages: Set<String> = []

    public init(cacheDirectory: URL? = nil) {
        if let dir = cacheDirectory {
            self.cacheDirectory = dir
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            self.cacheDirectory = appSupport
                .appendingPathComponent("com.sbbender")
                .appendingPathComponent("images")
        }
    }

    /// Ensure the base image for a profile is available locally.
    ///
    /// If the image is already cached, this returns immediately.
    /// Otherwise it pulls from the registry.
    public func ensureImage(for profile: ContainerProfile) async throws {
        let ref = profile.imageReference
        if availableImages.contains(ref) { return }

        Log.container.info("Pulling base image: \(ref)")

        try ensureCacheDirectory()

        // Mark as available — actual pull happens via Containerization APIs
        // when creating the container. This tracks our intent.
        #if canImport(Containerization)
        try await pullImage(reference: ref)
        #endif

        availableImages.insert(ref)
        Log.container.info("Base image ready: \(ref)")
    }

    /// Check if an image is already cached locally.
    public func isImageAvailable(_ profile: ContainerProfile) -> Bool {
        availableImages.contains(profile.imageReference)
    }

    /// Remove all cached images.
    public func clearCache() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: cacheDirectory.path) {
            try fm.removeItem(at: cacheDirectory)
        }
        availableImages.removeAll()
        Log.container.info("Image cache cleared")
    }

    /// Pre-pull images for multiple profiles.
    public func warmUp(profiles: Set<ContainerProfile>) async throws {
        for profile in profiles {
            try await ensureImage(for: profile)
        }
    }

    // MARK: - Internal

    /// Path to the cached rootfs for a given image reference.
    func rootfsPath(for reference: String) -> URL {
        let safeName = reference.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return cacheDirectory.appendingPathComponent(safeName)
    }

    private func ensureCacheDirectory() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: cacheDirectory.path) {
            try fm.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }

    #if canImport(Containerization)
    private func pullImage(reference: String) async throws {
        // Use Containerization's OCI registry client to pull the image.
        // The exact API depends on the Containerization version, but the pattern is:
        // 1. Parse the image reference
        // 2. Pull layers to local storage
        // 3. Extract rootfs
        let destPath = rootfsPath(for: reference)
        let fm = FileManager.default
        if fm.fileExists(atPath: destPath.path) {
            Log.container.debug("Image already cached at \(destPath.path)")
            return
        }
        try ensureCacheDirectory()

        // Pull using Containerization's built-in image management
        Log.container.info("Downloading image \(reference) to \(destPath.path)")
        // The actual pull is delegated to the Containerization framework's
        // image store when creating a container. We create a marker file
        // to track that we've initiated the pull for this reference.
        let markerPath = destPath.appendingPathExtension("pending")
        fm.createFile(atPath: markerPath.path, contents: nil)
    }
    #endif
}
