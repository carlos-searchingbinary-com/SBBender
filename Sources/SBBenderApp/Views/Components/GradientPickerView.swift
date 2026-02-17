import SwiftUI

struct GradientPickerView: View {
    @Binding var selectedHex: [String]

    private let columns = Array(repeating: GridItem(.fixed(36), spacing: 8), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(GradientPreset.all) { preset in
                Button {
                    withAnimation(.spring(duration: 0.2)) {
                        selectedHex = preset.hex
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: preset.hex.map { Color(hex: $0) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 32, height: 32)
                        if selectedHex == preset.hex {
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(preset.name)
            }
        }
    }
}
