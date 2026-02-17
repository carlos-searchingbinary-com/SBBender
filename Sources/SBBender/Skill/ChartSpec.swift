import Foundation

/// Structured chart specification returned by ChartingSkill.
///
/// The `__chart__` marker in the JSON output lets the chat view detect and render
/// charts inline using Swift Charts. Each chart type has specific data requirements.
public struct ChartSpec: Codable, Sendable, Equatable {

    /// Marker field for chat view detection.
    public let __chart__: Bool  // swiftlint:disable:this identifier_name

    /// The chart type to render.
    public let type: ChartType

    /// Chart title displayed above the visualization.
    public let title: String?

    /// X-axis label (bar, line, scatter, area).
    public let xLabel: String?

    /// Y-axis label (bar, line, scatter, area).
    public let yLabel: String?

    /// Single-series data points.
    public let data: [DataPoint]?

    /// Multi-series data (grouped bar, multi-line).
    public let series: [DataSeries]?

    /// Whether the chart type was auto-detected from the data shape.
    public let autoDetected: Bool

    /// Human-readable explanation of why this chart type was chosen.
    public let reason: String?

    public init(
        type: ChartType,
        title: String? = nil,
        xLabel: String? = nil,
        yLabel: String? = nil,
        data: [DataPoint]? = nil,
        series: [DataSeries]? = nil,
        autoDetected: Bool = false,
        reason: String? = nil
    ) {
        self.__chart__ = true
        self.type = type
        self.title = title
        self.xLabel = xLabel
        self.yLabel = yLabel
        self.data = data
        self.series = series
        self.autoDetected = autoDetected
        self.reason = reason
    }

    // MARK: - Chart Types

    public enum ChartType: String, Codable, Sendable, CaseIterable {
        case bar
        case line
        case pie
        case scatter
        case area

        public var displayName: String {
            switch self {
            case .bar: "Bar Chart"
            case .line: "Line Chart"
            case .pie: "Pie Chart"
            case .scatter: "Scatter Plot"
            case .area: "Area Chart"
            }
        }

        public var description: String {
            switch self {
            case .bar: "Compare values across categories. Best for discrete comparisons."
            case .line: "Show trends over time or sequential data. Best for temporal patterns."
            case .pie: "Show proportions of a whole. Best for 2-7 categories that sum to a total."
            case .scatter: "Show correlation between two numeric variables. Best for relationship analysis."
            case .area: "Like line charts but with filled regions. Best for cumulative or volume data."
            }
        }
    }

    // MARK: - Data Points

    /// A single data point. Use `label`+`value` for categorical charts (bar, line, pie, area)
    /// or `x`+`y` for scatter plots.
    public struct DataPoint: Codable, Sendable, Equatable {
        /// Category label (bar, line, pie, area).
        public let label: String?
        /// Numeric value (bar, line, pie, area).
        public let value: Double?
        /// X coordinate (scatter).
        public let x: Double?
        /// Y coordinate (scatter).
        public let y: Double?
        /// Optional point label (scatter).
        public let name: String?

        public init(label: String? = nil, value: Double? = nil, x: Double? = nil, y: Double? = nil, name: String? = nil) {
            self.label = label
            self.value = value
            self.x = x
            self.y = y
            self.name = name
        }
    }

    // MARK: - Data Series

    /// A named series for multi-series charts (grouped bar, multi-line).
    public struct DataSeries: Codable, Sendable, Equatable {
        public let name: String
        public let data: [DataPoint]

        public init(name: String, data: [DataPoint]) {
            self.name = name
            self.data = data
        }
    }
}
