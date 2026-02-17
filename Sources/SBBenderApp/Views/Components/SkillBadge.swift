import SwiftUI

struct SkillBadge: View {
    let name: String
    var icon: String = "sparkle"
    var isEnabled: Bool = true

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(name)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(isEnabled ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
        .foregroundStyle(isEnabled ? .primary : .secondary)
        .clipShape(Capsule())
    }
}
