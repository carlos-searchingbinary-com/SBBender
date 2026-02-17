import SwiftUI
import SBBender

struct ToolCallCard: View {
    let toolCall: ToolCall
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Arguments:")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Text(formatJSON(toolCall.arguments))
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(6)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(4)
            }
            .padding(.vertical, 4)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "wrench.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Text(toolCall.name)
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.06))
        .cornerRadius(8)
    }

    private func formatJSON(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8) else {
            return json
        }
        return str
    }
}
