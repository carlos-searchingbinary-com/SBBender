import SwiftUI

struct AgentAvatar: View {
    let emoji: String
    let gradientHex: [String]
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: gradientHex.map { Color(hex: $0) },
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            Text(emoji)
                .font(.system(size: size * 0.5))
        }
        .frame(width: size, height: size)
    }
}
