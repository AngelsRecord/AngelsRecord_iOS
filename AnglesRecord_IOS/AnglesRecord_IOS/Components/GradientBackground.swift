import SwiftUI

struct GradientBackground: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Image(colorScheme == .dark ? "gradientDark" : "gradientLight")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .ignoresSafeArea()
    }
}

#Preview {
    GradientBackground()
}


