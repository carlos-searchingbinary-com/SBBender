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

    /// Grid data for heatmap charts.
    public let heatmapData: [HeatmapCell]?

    /// OHLC data for candlestick charts.
    public let candlestickData: [CandlestickPoint]?

    /// Reference lines or markers overlaid on the chart.
    public let annotations: [Annotation]?

    /// Number of bins for histogram charts.
    public let binCount: Int?

    public init(
        type: ChartType,
        title: String? = nil,
        xLabel: String? = nil,
        yLabel: String? = nil,
        data: [DataPoint]? = nil,
        series: [DataSeries]? = nil,
        autoDetected: Bool = false,
        reason: String? = nil,
        heatmapData: [HeatmapCell]? = nil,
        candlestickData: [CandlestickPoint]? = nil,
        annotations: [Annotation]? = nil,
        binCount: Int? = nil
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
        self.heatmapData = heatmapData
        self.candlestickData = candlestickData
        self.annotations = annotations
        self.binCount = binCount
    }

    // MARK: - Chart Types

    public enum ChartType: String, Codable, Sendable, CaseIterable {
        case bar
        case line
        case pie
        case scatter
        case area
        case stackedBar
        case donut
        case histogram
        case heatmap
        case candlestick

        public var displayName: String {
            switch self {
            case .bar: "Bar Chart"
            case .line: "Line Chart"
            case .pie: "Pie Chart"
            case .scatter: "Scatter Plot"
            case .area: "Area Chart"
            case .stackedBar: "Stacked Bar Chart"
            case .donut: "Donut Chart"
            case .histogram: "Histogram"
            case .heatmap: "Heat Map"
            case .candlestick: "Candlestick Chart"
            }
        }

        public var description: String {
            switch self {
            case .bar: "Compare values across categories. Best for discrete comparisons."
            case .line: "Show trends over time or sequential data. Best for temporal patterns."
            case .pie: "Show proportions of a whole. Best for 2-7 categories that sum to a total."
            case .scatter: "Show correlation between two numeric variables. Best for relationship analysis."
            case .area: "Like line charts but with filled regions. Best for cumulative or volume data."
            case .stackedBar: "Compare category breakdowns with stacked segments. Best for part-to-whole comparisons across categories."
            case .donut: "Like a pie chart with a center hole. Best for percentage breakdowns with 3-8 categories."
            case .histogram: "Show distribution of continuous data across bins. Best for frequency analysis."
            case .heatmap: "Show values in a 2D grid with color intensity. Best for correlation matrices and pivot tables."
            case .candlestick: "Show open-high-low-close financial data. Best for stock and price analysis."
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

    // MARK: - Heatmap

    /// A single cell in a heatmap grid.
    public struct HeatmapCell: Codable, Sendable, Equatable {
        public let row: String
        public let column: String
        public let value: Double

        public init(row: String, column: String, value: Double) {
            self.row = row
            self.column = column
            self.value = value
        }
    }

    // MARK: - Candlestick

    /// A single OHLC data point for candlestick charts.
    public struct CandlestickPoint: Codable, Sendable, Equatable {
        public let label: String
        public let open: Double
        public let high: Double
        public let low: Double
        public let close: Double

        public init(label: String, open: Double, high: Double, low: Double, close: Double) {
            self.label = label
            self.open = open
            self.high = high
            self.low = low
            self.close = close
        }
    }

    // MARK: - Annotation

    /// A reference line or marker overlaid on a chart.
    public struct Annotation: Codable, Sendable, Equatable {
        public let label: String
        public let value: Double
        public let style: String?

        public init(label: String, value: Double, style: String? = nil) {
            self.label = label
            self.value = value
            self.style = style
        }
    }
}
