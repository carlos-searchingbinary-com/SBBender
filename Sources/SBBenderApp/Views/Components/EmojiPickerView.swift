import SwiftUI

struct EmojiPickerView: View {
    @Binding var selected: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(EmojiCategory.all) { category in
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(category.emojis, id: \.self) { emoji in
                            Button {
                                withAnimation(.spring(duration: 0.2)) {
                                    selected = emoji
                                }
                            } label: {
                                Text(emoji)
                                    .font(.title2)
                                    .frame(width: 36, height: 36)
                                    .background(
                                        selected == emoji
                                            ? Color.accentColor.opacity(0.2)
                                            : Color.clear
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .scaleEffect(selected == emoji ? 1.15 : 1.0)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}
