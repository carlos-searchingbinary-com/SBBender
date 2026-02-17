import Foundation
#if canImport(MLX)
import MLX
#endif

// MARK: - Model Tier

/// Hardware capability tier used to recommend compatible models.
public enum ModelTier: String, Sendable, Codable, CaseIterable, Comparable {
    case small   // 8GB RAM — up to 4B params (Q4)
    case medium  // 16GB RAM — up to 8B params (Q4)
    case large   // 32GB RAM — up to 32B params (Q4)
    case xlarge  // 64GB+ RAM — up to 70B params (Q4)

    public var displayName: String {
        switch self {
        case .small: "Small (8 GB)"
        case .medium: "Medium (16 GB)"
        case .large: "Large (32 GB)"
        case .xlarge: "XL (64 GB+)"
        }
    }

    public var maxParamBillions: Int {
        switch self {
        case .small: 4
        case .medium: 8
        case .large: 32
        case .xlarge: 70
        }
    }

    private var sortOrder: Int {
        switch self {
        case .small: 0
        case .medium: 1
        case .large: 2
        case .xlarge: 3
        }
    }

    public static func < (lhs: ModelTier, rhs: ModelTier) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    /// Derive tier from total RAM in bytes.
    public static func from(ramBytes: UInt64) -> ModelTier {
        let gb = ramBytes / (1024 * 1024 * 1024)
        switch gb {
        case ..<12: return .small
        case 12..<24: return .medium
        case 24..<48: return .large
        default: return .xlarge
        }
    }
}

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
