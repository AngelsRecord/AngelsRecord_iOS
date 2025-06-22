import SwiftUI

struct SplashView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note.house.fill")
                .font(.system(size: 80))
                .foregroundColor(.primary)
                .symbolEffect(.pulse)
            
            Text("AngelsRecord")
                .font(.title)
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
    }
} 