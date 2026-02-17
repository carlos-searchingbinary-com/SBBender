import Foundation

/// Describes the current state of the container runtime needed for OpenClaw containerized skills.
enum ContainerRuntimeStatus: Sendable {
    case ready
    case notSupported
    case kernelMissing
    case initFailed(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .ready: "Container Runtime Ready"
        case .notSupported: "Not Supported"
        case .kernelMissing: "Linux Kernel Not Found"
        case .initFailed(let msg): "Init Failed: \(msg)"
        }
    }

    var guidanceMessage: String? {
        switch self {
        case .ready:
            nil
        case .notSupported:
            "Containerized skills require macOS 26 or later."
        case .kernelMissing:
            "Install Apple's container CLI to download the Linux kernel. Run: brew install apple/container/container && container setup"
        case .initFailed(let msg):
            "Container manager failed to initialize: \(msg)"
        }
    }
}

/// Scan for a vmlinux kernel installed by Apple's `container` CLI tool.
@available(macOS 26, *)
func findVmlinuxKernel() -> URL? {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
    let kernelsDir = appSupport
        .appendingPathComponent("com.apple.container")
        .appendingPathComponent("kernels")

    guard let contents = try? FileManager.default.contentsOfDirectory(
        at: kernelsDir,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: .skipsHiddenFiles
    ) else {
        return nil
    }

    // Find the most recent vmlinux-* file
    return contents
        .filter { $0.lastPathComponent.hasPrefix("vmlinux") }
        .sorted {
            let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return d1 > d2
        }
        .first
}
