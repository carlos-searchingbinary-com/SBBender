import SwiftUI
import SBBender

struct ToolCallCard: View {
    let toolCall: ToolCall

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "wrench.fill")
                .font(.system(size: 9))
            Text(toolCall.name)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.orange.opacity(0.1)))
    }
}

/// Groups tool calls by name and renders compact badges with counts.
struct ToolCallBadges: View {
    let toolCalls: [ToolCall]

    private var grouped: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for call in toolCalls {
            if counts[call.name] == nil {
                order.append(call.name)
            }
            counts[call.name, default: 0] += 1
        }
        return order.map { (name: $0, count: counts[$0]!) }
    }

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(grouped, id: \.name) { item in
                HStack(spacing: 4) {
                    Image(systemName: "wrench.fill")
                        .font(.system(size: 9))
                    Text(item.count > 1 ? "\(item.name) \u{00d7}\(item.count)" : item.name)
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.orange.opacity(0.1)))
            }
        }
    }
}
