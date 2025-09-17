import SwiftUI

struct GradientBackground: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // 밑배경 (라이트/다크 각각)
            (colorScheme == .dark ? Color(hex: 0x303030) : Color(hex: 0xF2F3F7))
                .ignoresSafeArea()

            // Figma 값 그대로: 좌→우 그라디언트 + 레이어 전체 30% 불투명도
            LinearGradient(
                stops: [
                    .init(color: Color(hex: 0x001429, alpha: 1.00), location: 0.00),
                    .init(color: Color(hex: 0x194676, alpha: 0.92), location: 0.17),
                    .init(color: Color(hex: 0x89A8C9, alpha: 0.00), location: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(0.30)
            .ignoresSafeArea()
        }
    }
}

#Preview {
    Group {
        GradientBackground()
            .environment(\.colorScheme, .light)
    }
}
