import SwiftUI

struct SplashView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(.splashIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 283, height: 203)

            Spacer()
            
            Text("© ANGELS")
                .font(Font.SFPro.SemiBold.s13)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.background)
    }
}

#Preview {
    SplashView()
}
