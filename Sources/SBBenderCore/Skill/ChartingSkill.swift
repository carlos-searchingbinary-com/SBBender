import Foundation
import os

/// A NativeTool that creates chart specifications from data.
///
/// The skill validates data, auto-detects the best chart type when not specified,
/// and returns a structured `ChartSpec` JSON that the chat view renders with Swift Charts.
///
/// Actions:
/// - `chart`: Create a chart from data. Returns a `ChartSpec` JSON with `__chart__: true`.
/// - `types`: List available chart types with descriptions and when to use each.
public final class ChartingSkill: @unchecked Sendable, NativeTool {
    public let id = "charting"
    public let name = "createChart"
    public let description = """
        Create data visualizations (bar, line, pie, scatter, area charts). \
        Pass data as an array of {label, value} objects for categorical charts \
        or {x, y} for scatter plots. The chart type can be auto-detected from the data shape. \
        Use action 'chart' to create, or 'types' to see available chart types.
        """

    private let logger = Logger(subsystem: "com.sbbender", category: "ChartingSkill")

    public init() {}

    public var isAvailable: Bool {
        get async { true }
    }

    public var toolParameters: JSONSchema {
        JSONSchema(
            properties: [
                "action": .string("The action: 'chart' or 'types'"),
                "type": .string("Chart type: 'bar', 'line', 'pie', 'scatter', 'area', 'stackedBar', 'donut', 'histogram', 'heatmap', 'candlestick', or 'auto' (default). When 'auto', the best type is detected from the data."),
                "title": .string("Chart title displayed above the visualization."),
                "xLabel": .string("X-axis label. Optional."),
                "yLabel": .string("Y-axis label. Optional."),
                "data": .string("JSON array of data points: [{\"label\": \"A\", \"value\": 10}] for categorical, or [{\"x\": 1.0, \"y\": 2.0}] for scatter. For histograms, [{\"value\": 42}] raw numeric values."),
                "series": .string("JSON array of named series for multi-series charts: [{\"name\": \"Series1\", \"data\": [{\"label\": \"A\", \"value\": 10}]}]"),
                "binCount": .string("Number of bins for histogram charts. If omitted, auto-calculated via Sturges' rule."),
                "heatmapData": .string("JSON array of heatmap cells: [{\"row\": \"A\", \"column\": \"X\", \"value\": 0.9}]"),
                "candlestickData": .string("JSON array of OHLC points: [{\"label\": \"Mon\", \"open\": 150, \"high\": 155, \"low\": 148, \"close\": 153}]"),
                "annotations": .string("JSON array of reference lines/markers: [{\"label\": \"Target\", \"value\": 120, \"style\": \"line\"}]"),
            ],
            required: ["action"]
        )
    }

    public func asTool() -> Tool {
        let skill = self
        return Tool(
            name: name,
            description: description,
            parameters: toolParameters,
            stopAfterCall: true
        ) { arguments, _ in
            let args = try JSONDecoder().decode(DecodedArgs.self, from: Data(arguments.utf8))
            var params: [String: String] = [:]
            if let t = args.type { params["type"] = t }
            if let t = args.title { params["title"] = t }
            if let t = args.xLabel { params["xLabel"] = t }
            if let t = args.yLabel { params["yLabel"] = t }
            if let d = args.data { params["data"] = d.jsonString }
            if let s = args.series { params["series"] = s.jsonString }
            if let b = args.binCount { params["binCount"] = String(b) }
            if let h = args.heatmapData { params["heatmapData"] = h }
            if let c = args.candlestickData { params["candlestickData"] = c }
            if let a = args.annotations { params["annotations"] = a }
            let result = try await skill.execute(input: NativeToolInput(
                text: args.action,
                parameters: params
            ))
            return result.output
        }
    }

    public func execute(input: NativeToolInput) async throws -> NativeToolResult {
        guard let action = input.text, !action.isEmpty else {
            throw SBBenderError.skillExecutionFailed(skill: name, reason: "No action provided. Use 'chart' or 'types'.")
        }

        let start = CFAbsoluteTimeGetCurrent()

        switch action.lowercased() {
        case "chart":
            let spec = try buildChartSpec(from: input.parameters)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let jsonData = try encoder.encode(spec)
            let json = String(data: jsonData, encoding: .utf8) ?? "{}"

            return NativeToolResult(
                output: json,
                structuredData: [
                    "action": "chart",
                    "type": spec.type.rawValue,
                    "autoDetected": spec.autoDetected ? "true" : "false",
                ],
                confidence: 1.0,
                latency: CFAbsoluteTimeGetCurrent() - start
            )

        case "types":
            let output = listTypes()
            return NativeToolResult(
                output: output,
                structuredData: ["action": "types"],
                confidence: 1.0,
                latency: CFAbsoluteTimeGetCurrent() - start
            )

        default:
            throw SBBenderError.skillExecutionFailed(
                skill: name,
                reason: "Unknown action '\(action)'. Use 'chart' or 'types'."
            )
        }
    }

    // MARK: - Chart Building

    private func buildChartSpec(from params: [String: String]) throws -> ChartSpec {
        // Parse data
        var dataPoints = try parseDataPoints(params["data"])
        let dataSeries = try parseDataSeries(params["series"])

        // Parse new specialized data fields
        let heatmapData = try parseHeatmapData(params["heatmapData"])
        let candlestickData = try parseCandlestickData(params["candlestickData"])
        let annotations = try parseAnnotations(params["annotations"])
        let binCount = params["binCount"].flatMap { Int($0) }

        // Heatmap and candlestick use their own data fields
        let hasSpecializedData = heatmapData != nil || candlestickData != nil

        guard dataPoints != nil || dataSeries != nil || hasSpecializedData else {
            throw SBBenderError.skillExecutionFailed(
                skill: name,
                reason: "Either 'data', 'series', 'heatmapData', or 'candlestickData' is required for the 'chart' action."
            )
        }

        // Determine chart type
        let requestedType = params["type"]?.lowercased() ?? "auto"
        let (chartType, autoDetected, reason) = resolveChartType(
            requested: requestedType,
            data: dataPoints,
            series: dataSeries,
            heatmapData: heatmapData,
            candlestickData: candlestickData
        )

        // Validate data for the chosen chart type
        try validateData(
            type: chartType,
            data: dataPoints,
            series: dataSeries,
            heatmapData: heatmapData,
            candlestickData: candlestickData
        )

        // Histogram: auto-bin raw values into label+value DataPoints
        var resolvedBinCount = binCount
        if chartType == .histogram, let rawPoints = dataPoints {
            let values = rawPoints.compactMap(\.value)
            let needsBinning = rawPoints.allSatisfy { $0.label == nil && $0.value != nil }
            if needsBinning && values.count >= 3 {
                let numBins = binCount ?? Int(ceil(log2(Double(values.count)) + 1))
                resolvedBinCount = numBins
                dataPoints = buildHistogramBins(values: values, binCount: numBins)
            }
        }

        return ChartSpec(
            type: chartType,
            title: params["title"],
            xLabel: params["xLabel"],
            yLabel: params["yLabel"],
            data: dataPoints,
            series: dataSeries,
            autoDetected: autoDetected,
            reason: reason,
            heatmapData: heatmapData,
            candlestickData: candlestickData,
            annotations: annotations,
            binCount: resolvedBinCount
        )
    }

    // MARK: - Auto-Detection

    private func resolveChartType(
        requested: String,
        data: [ChartSpec.DataPoint]?,
        series: [ChartSpec.DataSeries]?,
        heatmapData: [ChartSpec.HeatmapCell]? = nil,
        candlestickData: [ChartSpec.CandlestickPoint]? = nil
    ) -> (ChartSpec.ChartType, Bool, String?) {
        // Explicit type requested
        if requested != "auto" {
            // Try exact match first, then case-insensitive match
            if let explicit = ChartSpec.ChartType(rawValue: requested) {
                return (explicit, false, nil)
            }
            if let explicit = ChartSpec.ChartType.allCases.first(where: { $0.rawValue.lowercased() == requested }) {
                return (explicit, false, nil)
            }
        }

        // Auto-detect from specialized data fields first
        if let heatmapData, !heatmapData.isEmpty {
            return (.heatmap, true, "\(heatmapData.count) heatmap cells provided → heat map")
        }

        if let candlestickData, !candlestickData.isEmpty {
            return (.candlestick, true, "\(candlestickData.count) OHLC points provided → candlestick chart")
        }

        // Auto-detect from data shape
        let points = data ?? series?.first?.data ?? []

        // Check for histogram: all numeric values, no labels, >10 points
        if series == nil && points.count > 10 {
            let allNumericNoLabels = points.allSatisfy { $0.label == nil && $0.value != nil }
            if allNumericNoLabels {
                return (.histogram, true, "\(points.count) raw numeric values without labels → histogram")
            }
        }

        // Check for scatter data (x/y coordinates)
        if points.allSatisfy({ $0.x != nil && $0.y != nil }) && !points.isEmpty {
            return (.scatter, true, "\(points.count) data points with x/y coordinates → scatter plot")
        }

        // Check for temporal labels → line chart
        if hasTemporalLabels(points) {
            if series != nil && (series?.count ?? 0) > 1 {
                return (.line, true, "Temporal labels with \(series!.count) series → multi-line chart")
            }
            return (.line, true, "Sequential/temporal labels detected → line chart")
        }

        // Check for pie/donut chart conditions
        let categoryCount = points.count
        if categoryCount >= 2 && series == nil {
            let values = points.compactMap(\.value)
            if values.count == categoryCount && values.allSatisfy({ $0 > 0 }) {
                // If values look like proportions or parts of a whole
                let total = values.reduce(0, +)
                let maxRatio = (values.max() ?? 0) / total
                // Pie works well when no single slice dominates overwhelmingly
                if maxRatio < 0.85 {
                    // Many categories (>6) → donut is better than pie
                    if categoryCount > 6 {
                        return (.donut, true, "\(categoryCount) categories with proportional values → donut chart (better than pie for 7+ categories)")
                    }
                    // Pie for <= 6 categories
                    if categoryCount <= 6 {
                        return (.pie, true, "\(categoryCount) categories with proportional values → pie chart")
                    }
                }
            }
        }

        // Multi-series → grouped bar
        if let series, series.count > 1 {
            return (.bar, true, "\(series.count) data series with categories → grouped bar chart")
        }

        // Many categories → bar (they can scroll)
        if categoryCount > 0 {
            return (.bar, true, "\(categoryCount) categories with values → bar chart")
        }

        // Fallback
        return (.bar, true, "Default chart type → bar chart")
    }

    private func hasTemporalLabels(_ points: [ChartSpec.DataPoint]) -> Bool {
        guard points.count >= 3 else { return false }
        let labels = points.compactMap(\.label)
        guard labels.count == points.count else { return false }

        // Check common temporal patterns
        let temporalPatterns: [String] = [
            // Year patterns
            "^\\d{4}$",
            // Month abbreviations
            "^(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)",
            // Quarter patterns
            "^Q[1-4]",
            // Date patterns
            "^\\d{4}-\\d{2}",
            "^\\d{1,2}/\\d{1,2}",
            // Day names
            "^(Mon|Tue|Wed|Thu|Fri|Sat|Sun)",
            // Week patterns
            "^W\\d{1,2}$",
            "^Week\\s?\\d",
        ]

        let matchCount = labels.filter { label in
            temporalPatterns.contains { pattern in
                label.range(of: pattern, options: .regularExpression, range: nil, locale: nil) != nil
            }
        }.count

        // If most labels match temporal patterns
        return matchCount > labels.count / 2
    }

    // MARK: - Validation

    private func validateData(
        type: ChartSpec.ChartType,
        data: [ChartSpec.DataPoint]?,
        series: [ChartSpec.DataSeries]?,
        heatmapData: [ChartSpec.HeatmapCell]? = nil,
        candlestickData: [ChartSpec.CandlestickPoint]? = nil
    ) throws {
        switch type {
        case .scatter:
            let points = data ?? series?.first?.data ?? []
            guard points.allSatisfy({ $0.x != nil && $0.y != nil }) else {
                throw SBBenderError.skillExecutionFailed(
                    skill: name,
                    reason: "Scatter charts require data points with 'x' and 'y' numeric fields."
                )
            }

        case .pie:
            let points = data ?? []
            guard !points.isEmpty else {
                throw SBBenderError.skillExecutionFailed(skill: name, reason: "Pie charts require 'data' (not 'series').")
            }
            let values = points.compactMap(\.value)
            guard values.count == points.count else {
                throw SBBenderError.skillExecutionFailed(
                    skill: name,
                    reason: "Pie charts require every data point to have a numeric 'value'."
                )
            }
            guard values.allSatisfy({ $0 >= 0 }) else {
                throw SBBenderError.skillExecutionFailed(
                    skill: name,
                    reason: "Pie chart values must be non-negative."
                )
            }

        case .donut:
            let points = data ?? []
            guard !points.isEmpty else {
                throw SBBenderError.skillExecutionFailed(skill: name, reason: "Donut charts require 'data' (not 'series').")
            }
            let values = points.compactMap(\.value)
            guard values.count == points.count else {
                throw SBBenderError.skillExecutionFailed(
                    skill: name,
                    reason: "Donut charts require every data point to have a numeric 'value'."
                )
            }
            guard values.allSatisfy({ $0 >= 0 }) else {
                throw SBBenderError.skillExecutionFailed(
                    skill: name,
                    reason: "Donut chart values must be non-negative."
                )
            }

        case .stackedBar:
            guard let series, !series.isEmpty else {
                throw SBBenderError.skillExecutionFailed(
                    skill: name,
                    reason: "Stacked bar charts require 'series' data with multiple named series."
                )
            }
            let allPoints = series.flatMap(\.data)
            let hasLabels = allPoints.allSatisfy { $0.label != nil }
            let hasValues = allPoints.allSatisfy { $0.value != nil }
            guard hasLabels && hasValues else {
                throw SBBenderError.skillExecutionFailed(
                    skill: name,
                    reason: "Stacked Bar Chart requires data points with 'label' and 'value' fields."
                )
            }

        case .histogram:
            let points = data ?? []
            let values = points.compactMap(\.value)
            guard values.count >= 3 else {
                throw SBBenderError.skillExecutionFailed(
                    skill: name,
                    reason: "Histogram requires at least 3 numeric values."
                )
            }

        case .heatmap:
            guard let heatmapData, !heatmapData.isEmpty else {
                throw SBBenderError.skillExecutionFailed(
                    skill: name,
                    reason: "Heatmap charts require 'heatmapData' with row, column, and value fields."
                )
            }

        case .candlestick:
            guard let candlestickData, !candlestickData.isEmpty else {
                throw SBBenderError.skillExecutionFailed(
                    skill: name,
                    reason: "Candlestick charts require 'candlestickData' with label, open, high, low, close fields."
                )
            }
            for point in candlestickData {
                guard point.high >= point.low else {
                    throw SBBenderError.skillExecutionFailed(
                        skill: name,
                        reason: "Candlestick data point '\(point.label)' has high (\(point.high)) < low (\(point.low))."
                    )
                }
            }

        case .bar, .line, .area:
            let points = data ?? series?.flatMap(\.data) ?? []
            guard !points.isEmpty else {
                throw SBBenderError.skillExecutionFailed(
                    skill: name,
                    reason: "\(type.displayName) requires at least one data point."
                )
            }
            // Categorical charts need label+value
            let hasLabels = points.allSatisfy { $0.label != nil }
            let hasValues = points.allSatisfy { $0.value != nil }
            guard hasLabels && hasValues else {
                throw SBBenderError.skillExecutionFailed(
                    skill: name,
                    reason: "\(type.displayName) requires data points with 'label' and 'value' fields."
                )
            }
        }
    }

    // MARK: - Parsing

    private func parseDataPoints(_ json: String?) throws -> [ChartSpec.DataPoint]? {
        guard let json, !json.isEmpty else { return nil }
        do {
            return try JSONDecoder().decode([ChartSpec.DataPoint].self, from: Data(json.utf8))
        } catch {
            throw SBBenderError.skillExecutionFailed(
                skill: name,
                reason: "Invalid 'data' JSON: \(error.localizedDescription). Expected array of {label, value} or {x, y} objects."
            )
        }
    }

    private func parseDataSeries(_ json: String?) throws -> [ChartSpec.DataSeries]? {
        guard let json, !json.isEmpty else { return nil }
        do {
            return try JSONDecoder().decode([ChartSpec.DataSeries].self, from: Data(json.utf8))
        } catch {
            throw SBBenderError.skillExecutionFailed(
                skill: name,
                reason: "Invalid 'series' JSON: \(error.localizedDescription). Expected array of {name, data: [{label, value}]} objects."
            )
        }
    }

    private func parseHeatmapData(_ json: String?) throws -> [ChartSpec.HeatmapCell]? {
        guard let json, !json.isEmpty else { return nil }
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            return try JSONDecoder().decode([ChartSpec.HeatmapCell].self, from: Data(trimmed.utf8))
        } catch {
            throw SBBenderError.skillExecutionFailed(
                skill: name,
                reason: "Invalid 'heatmapData' JSON: \(error.localizedDescription). Expected array of {row, column, value} objects."
            )
        }
    }

    private func parseCandlestickData(_ json: String?) throws -> [ChartSpec.CandlestickPoint]? {
        guard let json, !json.isEmpty else { return nil }
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            return try JSONDecoder().decode([ChartSpec.CandlestickPoint].self, from: Data(trimmed.utf8))
        } catch {
            throw SBBenderError.skillExecutionFailed(
                skill: name,
                reason: "Invalid 'candlestickData' JSON: \(error.localizedDescription). Expected array of {label, open, high, low, close} objects."
            )
        }
    }

    private func parseAnnotations(_ json: String?) throws -> [ChartSpec.Annotation]? {
        guard let json, !json.isEmpty else { return nil }
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            return try JSONDecoder().decode([ChartSpec.Annotation].self, from: Data(trimmed.utf8))
        } catch {
            throw SBBenderError.skillExecutionFailed(
                skill: name,
                reason: "Invalid 'annotations' JSON: \(error.localizedDescription). Expected array of {label, value, style?} objects."
            )
        }
    }

    // MARK: - Histogram Binning

    /// Auto-bin raw numeric values into histogram bins using Sturges' rule.
    private func buildHistogramBins(values: [Double], binCount: Int) -> [ChartSpec.DataPoint] {
        guard let minVal = values.min(), let maxVal = values.max(), binCount > 0 else {
            return []
        }

        // Handle edge case where all values are the same
        let range = maxVal - minVal
        let binWidth = range > 0 ? range / Double(binCount) : 1.0
        let adjustedMin = range > 0 ? minVal : minVal - Double(binCount) / 2.0

        var bins = Array(repeating: 0.0, count: binCount)
        for value in values {
            var index = Int((value - adjustedMin) / binWidth)
            // Clamp the last value into the final bin
            if index >= binCount { index = binCount - 1 }
            if index < 0 { index = 0 }
            bins[index] += 1
        }

        return (0..<binCount).map { i in
            let low = adjustedMin + Double(i) * binWidth
            let high = low + binWidth
            let label = "\(formatBinEdge(low))-\(formatBinEdge(high))"
            return ChartSpec.DataPoint(label: label, value: bins[i])
        }
    }

    private func formatBinEdge(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e10 {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }

    // MARK: - List Types

    private func listTypes() -> String {
        var lines: [String] = ["Available chart types:\n"]
        for chartType in ChartSpec.ChartType.allCases {
            lines.append("  \(chartType.rawValue) — \(chartType.displayName)")
            lines.append("    \(chartType.description)")
            lines.append("")
        }
        lines.append("Tip: Use type 'auto' (or omit it) to let the skill pick the best chart for your data.")
        return lines.joined(separator: "\n")
    }

}

// MARK: - Flexible Input Decoding

/// Flexible input that accepts either a JSON string or an already-decoded array.
enum ChartDataInput: Decodable, Sendable {
    case string(String)
    case array([ChartSpec.DataPoint])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .string(str)
        } else if let arr = try? container.decode([ChartSpec.DataPoint].self) {
            self = .array(arr)
        } else {
            throw DecodingError.typeMismatch(
                ChartDataInput.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Expected string or array of data points")
            )
        }
    }

    var jsonString: String {
        switch self {
        case .string(let s): return s
        case .array(let arr):
            if let data = try? JSONEncoder().encode(arr),
               let str = String(data: data, encoding: .utf8) {
                return str
            }
            return "[]"
        }
    }
}

enum ChartSeriesInput: Decodable, Sendable {
    case string(String)
    case array([ChartSpec.DataSeries])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .string(str)
        } else if let arr = try? container.decode([ChartSpec.DataSeries].self) {
            self = .array(arr)
        } else {
            throw DecodingError.typeMismatch(
                ChartSeriesInput.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Expected string or array of series")
            )
        }
    }

    var jsonString: String {
        switch self {
        case .string(let s): return s
        case .array(let arr):
            if let data = try? JSONEncoder().encode(arr),
               let str = String(data: data, encoding: .utf8) {
                return str
            }
            return "[]"
        }
    }
}

extension ChartingSkill {
    fileprivate struct DecodedArgs: Decodable {
        let action: String
        let type: String?
        let title: String?
        let xLabel: String?
        let yLabel: String?
        let data: ChartDataInput?
        let series: ChartSeriesInput?
        let binCount: Int?
        let heatmapData: String?
        let candlestickData: String?
        let annotations: String?
    }
}
