import Foundation

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
