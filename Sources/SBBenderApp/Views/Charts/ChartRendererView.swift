import SwiftUI
import Charts
import SBBender

struct ChartRendererView: View {
    let spec: ChartSpec

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = spec.title {
                Text(title)
                    .font(.headline)
            }
            chartContent
                .frame(height: chartHeight)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
    }

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

    // MARK: - Bar

    private var barChart: some View {
        Chart(dataPoints, id: \.label) { point in
            BarMark(
                x: .value(xLabel.isEmpty ? "Category" : xLabel, point.label ?? ""),
                y: .value(yLabel.isEmpty ? "Value" : yLabel, point.value ?? 0)
            )
            .foregroundStyle(.blue.gradient)
        }
        .chartOverlay(content: { _ in annotationOverlay })
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
        }
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
        }
        .chartXAxisLabel(xLabel)
        .chartYAxisLabel(yLabel)
    }

    // MARK: - Pie / Donut

    private func pieChart(innerRadius: CGFloat) -> some View {
        Chart(dataPoints, id: \.label) { point in
            SectorMark(
                angle: .value(point.label ?? "", point.value ?? 0),
                innerRadius: .ratio(innerRadius),
                angularInset: 1
            )
            .foregroundStyle(by: .value("Category", point.label ?? ""))
        }
    }

    // MARK: - Scatter

    private var scatterChart: some View {
        Chart(Array(dataPoints.enumerated()), id: \.offset) { _, point in
            PointMark(
                x: .value(xLabel.isEmpty ? "X" : xLabel, point.x ?? 0),
                y: .value(yLabel.isEmpty ? "Y" : yLabel, point.y ?? 0)
            )
            .foregroundStyle(.blue)
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
            .foregroundStyle(.orange.gradient)
        }
        .chartXAxisLabel(xLabel)
        .chartYAxisLabel(yLabel.isEmpty ? "Count" : yLabel)
    }

    // MARK: - Heatmap

    private var heatmapChart: some View {
        let cells = spec.heatmapData ?? []
        return Chart(Array(cells.enumerated()), id: \.offset) { _, cell in
            RectangleMark(
                x: .value("Column", cell.column),
                y: .value("Row", cell.row)
            )
            .foregroundStyle(by: .value("Value", cell.value))
        }
        .chartForegroundStyleScale(range: Gradient(colors: [.blue, .green, .yellow, .red]))
    }

    // MARK: - Candlestick

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
        }
        .chartYAxisLabel(yLabel.isEmpty ? "Price" : yLabel)
    }

    // MARK: - Annotation Overlay

    @ViewBuilder
    private var annotationOverlay: some View {
        EmptyView() // Annotations rendered via chart overlay in future iteration
    }
}
