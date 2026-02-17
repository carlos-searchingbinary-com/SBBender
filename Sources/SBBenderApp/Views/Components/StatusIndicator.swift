import SwiftUI

struct StatusIndicator: View {
    let status: AgentStatus
    var size: CGFloat = 10

    @State private var isPulsing = false

    var body: some View {
        statusCircle
    }

    @ViewBuilder
    private var statusCircle: some View {
        let scale: CGFloat = isPulsing ? 1.3 : 1.0
        let opacity: Double = isPulsing ? 0.7 : 1.0

        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .scaleEffect(scale)
            .opacity(opacity)
            .animation(pulseAnimation, value: isPulsing)
            .onChange(of: status, initial: true) { _, newValue in
                updatePulsing(newValue)
            }
    }

    private func updatePulsing(_ status: AgentStatus) {
        switch status {
        case .thinking, .working, .streaming:
            isPulsing = true
        default:
            isPulsing = false
        }
    }

    private var color: Color {
        switch status {
        case .idle: return .gray
        case .thinking: return .purple
        case .working: return .orange
        case .streaming: return .blue
        case .error: return .red
        case .done: return .green
        }
    }

    private var pulseAnimation: Animation? {
        guard isPulsing else { return .default }
        switch status {
        case .thinking:
            return .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
        case .working:
            return .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
        case .streaming:
            return .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
        default:
            return nil
        }
    }
}
