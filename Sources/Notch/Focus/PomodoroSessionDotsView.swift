import SwiftUI

struct PomodoroSessionDotsView: View {
    let current: Int
    let total: Int
    let isFocus: Bool
    let tint: Color
    var dotSize: CGFloat = 5
    var spacing: CGFloat = 5
    var indicatorSize: CGFloat = 9
    
    @State private var pulse = false
    
    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(fillColor(for: index))
                    .frame(width: dotSize, height: dotSize)
                    .overlay {
                        if isFocus && index == current {
                            Circle()
                                .stroke(tint.opacity(0.4), lineWidth: 1.5)
                                .frame(width: indicatorSize, height: indicatorSize)
                                .scaleEffect(pulse ? 1.2 : 1.0)
                                .opacity(pulse ? 0.6 : 1.0)
                        }
                    }
                    .frame(width: indicatorSize, height: indicatorSize)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
    
    private func fillColor(for index: Int) -> Color {
        if index < current {
            return tint
        } else if isFocus && index == current {
            return tint.opacity(0.3)
        } else {
            return tint.opacity(0.16)
        }
    }
}
