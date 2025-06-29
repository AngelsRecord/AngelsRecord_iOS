import SwiftUI

struct MiniPlayerView: View {
    let record: RecordListModel
    @ObservedObject var audioPlayer: AudioPlayerManager
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // 앨범 이미지
            Image("mainimage_yet")
                .resizable()
                .scaledToFit()
                .frame(width: 50, height: 50)
                .cornerRadius(8)
            
            // 제목과 아티스트
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(record.artist)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // 재생/일시정지 버튼
            Button(action: {
                audioPlayer.togglePlayPause()
            }) {
                Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
            }
            
            // 다음곡 버튼
            Button(action: {
                // 다음곡 기능 (현재는 빈 액션)
            }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(height: 66)
        .background(
            Color(UIColor.systemBackground)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: -5)
        )
    }
}

#Preview {
    VStack {
        Spacer()
        
        MiniPlayerView(
            record: RecordListModel(
                title: "Ep.1 대나무숲",
                artist: "6월 22일",
                duration: 205.0
            ),
            audioPlayer: AudioPlayerManager(),
            onDelete: {}
        )
    }
    .background(Color.gray.opacity(0.1))
}
