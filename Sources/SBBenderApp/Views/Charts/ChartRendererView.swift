import SwiftUI
import Charts
import SBBender
import AppKit

struct ChartRendererView: View {
    let spec: ChartSpec

    @State private var hoveredLabel: String?
    @State private var hoveredValue: Double?
    @State private var hoveredPoint: CGPoint?
    @State private var hoveredSeries: String?
    @State private var showSavePanel = false
    @State private var copyFeedback = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title + action buttons
            HStack {
                if let title = spec.title {
                    Text(title)
                        .font(.headline)
                }
                Spacer()
                chartActions
            }
            .padding(.bottom, 6)

            chartContent
                .frame(height: chartHeight)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
    }

    // MARK: - Action Buttons

    private var chartActions: some View {
        HStack(spacing: 4) {
            Button {
                copyChartToClipboard()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: copyFeedback ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                    Text(copyFeedback ? "Copied" : "Copy")
                        .font(.caption2)
                }
                .foregroundStyle(copyFeedback ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(.quaternary))

            Button {
                saveChartToFile()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 10))
                    Text("Save")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(.quaternary))
        }
    }

    // MARK: - Chart Height

    private var chartHeight: CGFloat {
        switch spec.type {
        case .heatmap:
            let rows = Set(spec.heatmapData?.map(\.row) ?? []).count
            return max(200, CGFloat(rows) * 40)
        case .pie, .donut:
            return 260
        default:
            return 300
        }
    }

    // MARK: - Chart Content Dispatch

    @ViewBuilder
    private var chartContent: some View {
        switch spec.type {
        case .bar:
            barChart
        case .stackedBar:
            stackedBarChart
        case .line:
            lineChart
        case .area:
            areaChart
        case .pie:
            pieChart(innerRadius: 0)
        case .donut:
            pieChart(innerRadius: 0.4)
        case .scatter:
            scatterChart
        case .histogram:
            histogramChart
        case .heatmap:
            heatmapChart
        case .candlestick:
            candlestickChart
        }
    }

    // MARK: - Helpers

    private var dataPoints: [ChartSpec.DataPoint] { spec.data ?? [] }
    private var dataSeries: [ChartSpec.DataSeries] { spec.series ?? [] }
    private var xLabel: String { spec.xLabel ?? "" }
    private var yLabel: String { spec.yLabel ?? "" }

    // MARK: - Categorical Tooltip Overlay

    /// Shared hover overlay for categorical charts (bar, line, area, histogram, stacked bar).
    /// Uses ChartProxy to resolve the hovered x-category and show a tooltip.
    private func categoricalOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geo in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let origin = geo[proxy.plotFrame!]
                        let relativeX = location.x - origin.minX
                        if let label: String = proxy.value(atX: relativeX) {
                            hoveredLabel = label
                            hoveredPoint = location
                            // Find the value for this label
                            if let point = dataPoints.first(where: { $0.label == label }) {
                                hoveredValue = point.value
                            } else if let series = dataSeries.first, let point = series.data.first(where: { $0.label == label }) {
                                hoveredValue = point.value
                            }
                        }
                    case .ended:
                        hoveredLabel = nil
                        hoveredValue = nil
                        hoveredPoint = nil
                    }
                }
        }
    }

    /// Tooltip popover view for categorical data.
    @ViewBuilder
    private var categoricalTooltip: some View {
        if let label = hoveredLabel, let value = hoveredValue {
            tooltipView(label: label, value: formatValue(value))
        }
    }

    // MARK: - Bar

    private var barChart: some View {
        Chart(dataPoints, id: \.label) { point in
            BarMark(
                x: .value(xLabel.isEmpty ? "Category" : xLabel, point.label ?? ""),
                y: .value(yLabel.isEmpty ? "Value" : yLabel, point.value ?? 0)
            )
            .foregroundStyle(hoveredLabel == point.label ? Color.blue : Color.blue.opacity(0.8))
        }
        .chartOverlay { proxy in categoricalOverlay(proxy: proxy) }
        .overlay(alignment: .topLeading) { categoricalTooltip }
        .chartXAxisLabel(xLabel)
        .chartYAxisLabel(yLabel)
    }

    // MARK: - Stacked Bar

    private var stackedBarChart: some View {
        Chart {
            ForEach(dataSeries, id: \.name) { s in
                ForEach(s.data, id: \.label) { point in
                    BarMark(
                        x: .value(xLabel.isEmpty ? "Category" : xLabel, point.label ?? ""),
                        y: .value(yLabel.isEmpty ? "Value" : yLabel, point.value ?? 0)
                    )
                    .foregroundStyle(by: .value("Series", s.name))
                }
            }
        }
        .chartOverlay { proxy in categoricalOverlay(proxy: proxy) }
        .overlay(alignment: .topLeading) {
            if let label = hoveredLabel {
                // Show all series values for this category
                let seriesValues = dataSeries.compactMap { s -> (String, Double)? in
                    guard let pt = s.data.first(where: { $0.label == label }) else { return nil }
                    return (s.name, pt.value ?? 0)
                }
                if !seriesValues.isEmpty {
                    tooltipView(label: label, lines: seriesValues)
                }
            }
        }
        .chartXAxisLabel(xLabel)
        .chartYAxisLabel(yLabel)
    }

    // MARK: - Line

    private var lineChart: some View {
        Chart(dataPoints, id: \.label) { point in
            LineMark(
                x: .value(xLabel.isEmpty ? "X" : xLabel, point.label ?? ""),
                y: .value(yLabel.isEmpty ? "Y" : yLabel, point.value ?? 0)
            )
            if hoveredLabel == point.label {
                PointMark(
                    x: .value(xLabel.isEmpty ? "X" : xLabel, point.label ?? ""),
                    y: .value(yLabel.isEmpty ? "Y" : yLabel, point.value ?? 0)
                )
                .foregroundStyle(.blue)
                .symbolSize(40)
            }
        }
        .chartOverlay { proxy in categoricalOverlay(proxy: proxy) }
        .overlay(alignment: .topLeading) { categoricalTooltip }
        .chartXAxisLabel(xLabel)
        .chartYAxisLabel(yLabel)
    }

    // MARK: - Area

    private var areaChart: some View {
        Chart(dataPoints, id: \.label) { point in
            AreaMark(
                x: .value(xLabel.isEmpty ? "X" : xLabel, point.label ?? ""),
                y: .value(yLabel.isEmpty ? "Y" : yLabel, point.value ?? 0)
            )
            .foregroundStyle(.blue.opacity(0.3).gradient)

            if hoveredLabel == point.label {
                PointMark(
                    x: .value(xLabel.isEmpty ? "X" : xLabel, point.label ?? ""),
                    y: .value(yLabel.isEmpty ? "Y" : yLabel, point.value ?? 0)
                )
                .foregroundStyle(.blue)
                .symbolSize(40)
            }
        }
        .chartOverlay { proxy in categoricalOverlay(proxy: proxy) }
        .overlay(alignment: .topLeading) { categoricalTooltip }
        .chartXAxisLabel(xLabel)
        .chartYAxisLabel(yLabel)
    }

    // MARK: - Pie / Donut

    @State private var hoveredAngle: Double?

    private func pieChart(innerRadius: CGFloat) -> some View {
        let total = dataPoints.compactMap(\.value).reduce(0, +)

        return Chart(dataPoints, id: \.label) { point in
            SectorMark(
                angle: .value(point.label ?? "", point.value ?? 0),
                innerRadius: .ratio(innerRadius),
                angularInset: 1
            )
            .foregroundStyle(by: .value("Category", point.label ?? ""))
            .opacity(hoveredLabel == nil || hoveredLabel == point.label ? 1.0 : 0.5)
        }
        .chartAngleSelection(value: $hoveredAngle)
        .onChange(of: hoveredAngle) { _, newAngle in
            guard let newAngle else {
                hoveredLabel = nil
                hoveredValue = nil
                return
            }
            // Walk through cumulative angles to find the slice
            var cumulative = 0.0
            for point in dataPoints {
                let val = point.value ?? 0
                cumulative += val
                if newAngle <= cumulative {
                    hoveredLabel = point.label
                    hoveredValue = val
                    return
                }
            }
        }
        .overlay(alignment: .center) {
            if let label = hoveredLabel, let value = hoveredValue {
                VStack(spacing: 2) {
                    Text(label)
                        .font(.caption.bold())
                    Text(formatValue(value))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if total > 0, let v = hoveredValue {
                        Text("\(String(format: "%.1f", v / total * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(.ultraThickMaterial))
            }
        }
    }

    // MARK: - Scatter

    @State private var hoveredScatterIdx: Int?

    private var scatterChart: some View {
        Chart(Array(dataPoints.enumerated()), id: \.offset) { idx, point in
            PointMark(
                x: .value(xLabel.isEmpty ? "X" : xLabel, point.x ?? 0),
                y: .value(yLabel.isEmpty ? "Y" : yLabel, point.y ?? 0)
            )
            .foregroundStyle(hoveredScatterIdx == idx ? .red : .blue)
            .symbolSize(hoveredScatterIdx == idx ? 80 : 30)
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let origin = geo[proxy.plotFrame!]
                            let relX = location.x - origin.minX
                            let relY = location.y - origin.minY
                            guard let xVal: Double = proxy.value(atX: relX),
                                  let yVal: Double = proxy.value(atY: relY) else {
                                hoveredScatterIdx = nil
                                return
                            }
                            // Find nearest point
                            var closest: Int?
                            var minDist = Double.infinity
                            for (i, pt) in dataPoints.enumerated() {
                                let dx = (pt.x ?? 0) - xVal
                                let dy = (pt.y ?? 0) - yVal
                                let dist = dx * dx + dy * dy
                                if dist < minDist {
                                    minDist = dist
                                    closest = i
                                }
                            }
                            hoveredScatterIdx = closest
                            hoveredPoint = location
                        case .ended:
                            hoveredScatterIdx = nil
                            hoveredPoint = nil
                        }
                    }
            }
        }
        .overlay(alignment: .topLeading) {
            if let idx = hoveredScatterIdx, idx < dataPoints.count {
                let pt = dataPoints[idx]
                tooltipView(
                    label: pt.label ?? "Point \(idx + 1)",
                    lines: [
                        ("x", pt.x ?? 0),
                        ("y", pt.y ?? 0),
                    ]
                )
            }
        }
        .chartXAxisLabel(xLabel)
        .chartYAxisLabel(yLabel)
    }

    // MARK: - Histogram

    private var histogramChart: some View {
        Chart(dataPoints, id: \.label) { point in
            BarMark(
                x: .value("Bin", point.label ?? ""),
                y: .value("Count", point.value ?? 0)
            )
            .foregroundStyle(hoveredLabel == point.label ? Color.orange : Color.orange.opacity(0.8))
        }
        .chartOverlay { proxy in categoricalOverlay(proxy: proxy) }
        .overlay(alignment: .topLeading) { categoricalTooltip }
        .chartXAxisLabel(xLabel)
        .chartYAxisLabel(yLabel.isEmpty ? "Count" : yLabel)
    }

    // MARK: - Heatmap

    @State private var hoveredCellIdx: Int?

    private var heatmapChart: some View {
        let cells = spec.heatmapData ?? []
        return Chart(Array(cells.enumerated()), id: \.offset) { idx, cell in
            RectangleMark(
                x: .value("Column", cell.column),
                y: .value("Row", cell.row)
            )
            .foregroundStyle(by: .value("Value", cell.value))
            .opacity(hoveredCellIdx == nil || hoveredCellIdx == idx ? 1.0 : 0.6)
        }
        .chartForegroundStyleScale(range: Gradient(colors: [.blue, .green, .yellow, .red]))
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let origin = geo[proxy.plotFrame!]
                            let relX = location.x - origin.minX
                            let relY = location.y - origin.minY
                            guard let col: String = proxy.value(atX: relX),
                                  let row: String = proxy.value(atY: relY) else {
                                hoveredCellIdx = nil
                                return
                            }
                            hoveredCellIdx = cells.firstIndex(where: { $0.column == col && $0.row == row })
                            hoveredPoint = location
                        case .ended:
                            hoveredCellIdx = nil
                            hoveredPoint = nil
                        }
                    }
            }
        }
        .overlay(alignment: .topLeading) {
            if let idx = hoveredCellIdx, idx < cells.count {
                let cell = cells[idx]
                tooltipView(
                    label: "\(cell.row) / \(cell.column)",
                    value: formatValue(cell.value)
                )
            }
        }
    }

    // MARK: - Candlestick

    @State private var hoveredCandleLabel: String?

    private var candlestickChart: some View {
        let points = spec.candlestickData ?? []
        return Chart(Array(points.enumerated()), id: \.offset) { _, point in
            RuleMark(
                x: .value("Date", point.label),
                yStart: .value("Low", point.low),
                yEnd: .value("High", point.high)
            )
            .foregroundStyle(.secondary)
            .lineStyle(StrokeStyle(lineWidth: 1))

            RectangleMark(
                x: .value("Date", point.label),
                yStart: .value("Open", min(point.open, point.close)),
                yEnd: .value("Close", max(point.open, point.close)),
                width: 12
            )
            .foregroundStyle(point.close >= point.open ? .green : .red)
            .opacity(hoveredCandleLabel == nil || hoveredCandleLabel == point.label ? 1.0 : 0.5)
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let origin = geo[proxy.plotFrame!]
                            let relX = location.x - origin.minX
                            if let label: String = proxy.value(atX: relX) {
                                hoveredCandleLabel = label
                                hoveredPoint = location
                            }
                        case .ended:
                            hoveredCandleLabel = nil
                            hoveredPoint = nil
                        }
                    }
            }
        }
        .overlay(alignment: .topLeading) {
            if let label = hoveredCandleLabel,
               let point = points.first(where: { $0.label == label }) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.caption.bold())
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 1) {
                        GridRow {
                            Text("O").font(.caption2).foregroundStyle(.secondary)
                            Text(formatValue(point.open)).font(.caption2)
                        }
                        GridRow {
                            Text("H").font(.caption2).foregroundStyle(.secondary)
                            Text(formatValue(point.high)).font(.caption2)
                        }
                        GridRow {
                            Text("L").font(.caption2).foregroundStyle(.secondary)
                            Text(formatValue(point.low)).font(.caption2)
                        }
                        GridRow {
                            Text("C").font(.caption2).foregroundStyle(.secondary)
                            Text(formatValue(point.close)).font(.caption2)
                                .foregroundStyle(point.close >= point.open ? .green : .red)
                        }
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(.ultraThickMaterial))
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            }
        }
        .chartYAxisLabel(yLabel.isEmpty ? "Price" : yLabel)
    }

    // MARK: - Tooltip Views

    private func tooltipView(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.bold())
            Text(value)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(.ultraThickMaterial))
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        .padding(8)
    }

    private func tooltipView(label: String, lines: [(String, Double)]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.bold())
            ForEach(lines, id: \.0) { name, val in
                HStack(spacing: 4) {
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(formatValue(val))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(.ultraThickMaterial))
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        .padding(8)
    }

    // MARK: - Value Formatting

    private func formatValue(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e10 {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }

    // MARK: - Copy & Save

    private func renderChartImage() -> NSImage? {
        let renderer = ImageRenderer(content: exportableChart)
        renderer.scale = 2.0
        return renderer.nsImage
    }

    /// A standalone chart view for export (no hover state, includes title).
    private var exportableChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = spec.title {
                Text(title)
                    .font(.headline)
            }
            exportChartContent
                .frame(width: 600, height: chartHeight)
        }
        .padding(16)
        .background(Color.white)
    }

    /// Chart content without interactive overlays for clean export.
    @ViewBuilder
    private var exportChartContent: some View {
        switch spec.type {
        case .bar:
            Chart(dataPoints, id: \.label) { point in
                BarMark(
                    x: .value(xLabel.isEmpty ? "Category" : xLabel, point.label ?? ""),
                    y: .value(yLabel.isEmpty ? "Value" : yLabel, point.value ?? 0)
                )
                .foregroundStyle(.blue.gradient)
            }
            .chartXAxisLabel(xLabel)
            .chartYAxisLabel(yLabel)
        case .stackedBar:
            Chart {
                ForEach(dataSeries, id: \.name) { s in
                    ForEach(s.data, id: \.label) { point in
                        BarMark(
                            x: .value(xLabel.isEmpty ? "Category" : xLabel, point.label ?? ""),
                            y: .value(yLabel.isEmpty ? "Value" : yLabel, point.value ?? 0)
                        )
                        .foregroundStyle(by: .value("Series", s.name))
                    }
                }
            }
            .chartXAxisLabel(xLabel)
            .chartYAxisLabel(yLabel)
        case .line:
            Chart(dataPoints, id: \.label) { point in
                LineMark(
                    x: .value(xLabel.isEmpty ? "X" : xLabel, point.label ?? ""),
                    y: .value(yLabel.isEmpty ? "Y" : yLabel, point.value ?? 0)
                )
            }
            .chartXAxisLabel(xLabel)
            .chartYAxisLabel(yLabel)
        case .area:
            Chart(dataPoints, id: \.label) { point in
                AreaMark(
                    x: .value(xLabel.isEmpty ? "X" : xLabel, point.label ?? ""),
                    y: .value(yLabel.isEmpty ? "Y" : yLabel, point.value ?? 0)
                )
                .foregroundStyle(.blue.opacity(0.3).gradient)
            }
            .chartXAxisLabel(xLabel)
            .chartYAxisLabel(yLabel)
        case .pie:
            Chart(dataPoints, id: \.label) { point in
                SectorMark(
                    angle: .value(point.label ?? "", point.value ?? 0),
                    angularInset: 1
                )
                .foregroundStyle(by: .value("Category", point.label ?? ""))
            }
        case .donut:
            Chart(dataPoints, id: \.label) { point in
                SectorMark(
                    angle: .value(point.label ?? "", point.value ?? 0),
                    innerRadius: .ratio(0.4),
                    angularInset: 1
                )
                .foregroundStyle(by: .value("Category", point.label ?? ""))
            }
        case .scatter:
            Chart(Array(dataPoints.enumerated()), id: \.offset) { _, point in
                PointMark(
                    x: .value(xLabel.isEmpty ? "X" : xLabel, point.x ?? 0),
                    y: .value(yLabel.isEmpty ? "Y" : yLabel, point.y ?? 0)
                )
                .foregroundStyle(.blue)
            }
            .chartXAxisLabel(xLabel)
            .chartYAxisLabel(yLabel)
        case .histogram:
            Chart(dataPoints, id: \.label) { point in
                BarMark(
                    x: .value("Bin", point.label ?? ""),
                    y: .value("Count", point.value ?? 0)
                )
                .foregroundStyle(.orange.gradient)
            }
            .chartXAxisLabel(xLabel)
            .chartYAxisLabel(yLabel.isEmpty ? "Count" : yLabel)
        case .heatmap:
            let cells = spec.heatmapData ?? []
            Chart(Array(cells.enumerated()), id: \.offset) { _, cell in
                RectangleMark(
                    x: .value("Column", cell.column),
                    y: .value("Row", cell.row)
                )
                .foregroundStyle(by: .value("Value", cell.value))
            }
            .chartForegroundStyleScale(range: Gradient(colors: [.blue, .green, .yellow, .red]))
        case .candlestick:
            let points = spec.candlestickData ?? []
            Chart(Array(points.enumerated()), id: \.offset) { _, point in
                RuleMark(
                    x: .value("Date", point.label),
                    yStart: .value("Low", point.low),
                    yEnd: .value("High", point.high)
                )
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1))
                RectangleMark(
                    x: .value("Date", point.label),
                    yStart: .value("Open", min(point.open, point.close)),
                    yEnd: .value("Close", max(point.open, point.close)),
                    width: 12
                )
                .foregroundStyle(point.close >= point.open ? .green : .red)
            }
            .chartYAxisLabel(yLabel.isEmpty ? "Price" : yLabel)
        }
    }

    private func copyChartToClipboard() {
        guard let image = renderChartImage() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        copyFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copyFeedback = false
        }
    }

    private func saveChartToFile() {
        guard let image = renderChartImage(),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = (spec.title ?? "chart").replacingOccurrences(of: " ", with: "_") + ".png"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? pngData.write(to: url)
            }
        }
    }
}
