import SwiftUI

struct MiniPlayerView: View {
    let record: RecordListModel
    @ObservedObject var audioPlayer: AudioPlayerManager
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 3)
                    
                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: geometry.size.width * (audioPlayer.currentTime / max(audioPlayer.duration, 1)), height: 3)
                }
            }
            .frame(height: 3)

            HStack(spacing: 20) {
                Image(systemName: "waveform")
                    .font(.title2)
                    .foregroundColor(.primary)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: audioPlayer.isPlaying)
                
                Button(action: {
                    audioPlayer.skip(seconds: -15)
                }) {
                    buttonLabel(systemName: "gobackward", text: "15", size: 44)
                }

                Button(action: {
                    audioPlayer.togglePlayPause()
                }) {
                    ZStack {
                        Circle()
                            .stroke(Color.primary, lineWidth: 2)
                            .frame(width: 56, height: 56)
                        Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                    }
                }

                Button(action: {
                    audioPlayer.skip(seconds: 15)
                }) {
                    buttonLabel(systemName: "goforward", text: "15", size: 44)
                }

                Spacer()

                Text("\(formatTime(audioPlayer.currentTime)) / \(formatTime(audioPlayer.duration))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.title2)
                        .foregroundColor(.red)
                }
            }
            .padding()
        }
        .background(
            Color(UIColor.systemBackground)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: -5)
        )
    }

    private func buttonLabel(systemName: String, text: String, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(Color.primary, lineWidth: 2)
                .frame(width: size, height: size)
            VStack(spacing: 0) {
                Image(systemName: systemName).font(.system(size: 16))
                Text(text).font(.system(size: 10))
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        String(format: "%d:%02d", Int(time) / 60, Int(time) % 60)
    }
}
