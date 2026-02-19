import Foundation
import SBBenderCore
#if canImport(MLX)
import MLX
#endif

// MARK: - Hardware Info

/// Detected Mac hardware specs for model recommendations.
public struct HardwareInfo: Sendable, Codable, Equatable {
    public let chipName: String
    public let totalRAMBytes: UInt64
    public let gpuMemoryBytes: UInt64
    public let gpuArchitecture: String
    public let recommendedWorkingSetBytes: UInt64

    public var totalRAMGB: Int {
        Int(totalRAMBytes / (1024 * 1024 * 1024))
    }

    public var gpuMemoryGB: Double {
        Double(gpuMemoryBytes) / Double(1024 * 1024 * 1024)
    }

    public var modelTier: ModelTier {
        ModelTier.from(ramBytes: totalRAMBytes)
    }

    /// Detect hardware specs of the current Mac.
    public static func detect() -> HardwareInfo {
        let totalRAM = ProcessInfo.processInfo.physicalMemory
        let chip = sysctlString("machdep.cpu.brand_string") ?? "Unknown"

        #if canImport(MLX)
        let info = GPU.deviceInfo()
        let gpuMem = UInt64(info.memorySize)
        let gpuArch = info.architecture
        let workingSet = UInt64(info.maxRecommendedWorkingSetSize)
        #else
        let gpuMem: UInt64 = totalRAM // Unified memory approximation
        let gpuArch = "unknown"
        let workingSet: UInt64 = totalRAM * 3 / 4
        #endif

        return HardwareInfo(
            chipName: chip,
            totalRAMBytes: totalRAM,
            gpuMemoryBytes: gpuMem,
            gpuArchitecture: gpuArch,
            recommendedWorkingSetBytes: workingSet
        )
    }
}

// MARK: - sysctl Helper

private func sysctlString(_ name: String) -> String? {
    var size: Int = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
    // Truncate at null terminator and decode as UTF-8
    let length = buffer.firstIndex(of: 0) ?? buffer.count
    return String(decoding: buffer[..<length].map { UInt8(bitPattern: $0) }, as: UTF8.self)
}
