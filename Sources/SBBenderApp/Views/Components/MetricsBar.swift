import SwiftUI
import SBBender

struct MetricsBar: View {
    @Environment(AppState.self) private var appState
    let metrics: RunMetrics
    let statusMessage: String

    var body: some View {
        HStack(spacing: 16) {
            if appState.showAdvancedFeatures && metrics.modelCalls > 0 {
                metricItem(icon: "brain", label: "Model", value: "\(metrics.modelCalls)")
            }

            if metrics.toolCalls > 0 {
                metricItem(icon: "wrench", label: "Actions", value: "\(metrics.toolCalls)")
            }

            if appState.showAdvancedFeatures && metrics.totalTokens > 0 {
                metricItem(icon: "number", label: "Tokens", value: "\(metrics.totalTokens)")
            }

            metricItem(icon: "clock", label: "Response time", value: "\(String(format: "%.1f", metrics.totalLatency))s")

            if !statusMessage.isEmpty {
                Spacer()
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func metricItem(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(label): \(value)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
