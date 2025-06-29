import SwiftUI
import UIKit
import AVKit

// MARK: - 커스텀 UISlider (트랙 두께 조정)
class ThickerSlider: UISlider {
    var trackHeight: CGFloat = 6  // 기본값

    override func trackRect(forBounds bounds: CGRect) -> CGRect {
        let dynamicHeight = max(4, min(10, UIScreen.main.bounds.width * 0.01))  // 예: 너비의 1%, 최소 4 ~ 최대 10
        let original = super.trackRect(forBounds: bounds)
        return CGRect(
            x: original.origin.x,
            y: original.origin.y + (original.height - dynamicHeight) / 2,
            width: original.width,
            height: dynamicHeight
        )
    }
}


// MARK: - SwiftUI 래퍼
struct CustomProgressSlider: UIViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var onEditingChanged: ((Bool) -> Void)? = nil
    @Binding var isDragging: Bool

    func makeUIView(context: Context) -> ThickerSlider {
        let slider = ThickerSlider(frame: .zero)
        slider.trackHeight = 50
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)

        // 핵심: 거의 투명한 thumb (안보이지만 둥글게 처리됨)
        let thumbSize = CGSize(width: 16, height: 16)
        let thumb = UIGraphicsImageRenderer(size: thumbSize).image { context in
            let rect = CGRect(origin: .zero, size: thumbSize)
            let path = UIBezierPath(ovalIn: rect)
            UIColor.black.withAlphaComponent(0.001).setFill()
            path.fill()
        }
        slider.setThumbImage(thumb, for: .normal)

        slider.minimumTrackTintColor = UIColor.label
        slider.maximumTrackTintColor = UIColor.systemGray5

        // 이벤트 연결
        slider.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged), for: .valueChanged)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.touchDown), for: .touchDown)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.touchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        return slider
    }


    func updateUIView(_ uiView: ThickerSlider, context: Context) {
        uiView.value = Float(value)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator
    class Coordinator: NSObject {
        var parent: CustomProgressSlider

        init(_ parent: CustomProgressSlider) {
            self.parent = parent
        }

        @objc func valueChanged(_ sender: UISlider) {
            parent.value = Double(sender.value)
        }

        @objc func touchDown(_ sender: UISlider) {
            parent.isDragging = true
            parent.onEditingChanged?(true)
        }

        @objc func touchUp(_ sender: UISlider) {
            parent.isDragging = false
            parent.onEditingChanged?(false)
        }
    }
}


// MARK: - UIImage Helpers
private extension UIImage {
    /// 원형 단색 이미지 생성 (트랙용)
    convenience init?(color: UIColor, size: CGSize) {
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        color.setFill()
        UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2).fill()
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let cgImage = image?.cgImage else { return nil }
        self.init(cgImage: cgImage)
    }

    /// 크기 변경 (thumb용)
    func resize(to size: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, self.scale)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext() ?? self
    }
}



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


struct PlaybackSliderView: View {
    @Binding var value: Double
    var duration: Double
    @Binding var isDragging: Bool
    var onSeek: (Double) -> Void

    var body: some View {
        VStack(spacing: 6) {
            CustomProgressSlider(
                value: $value,
                range: 0...max(duration, 1),
                onEditingChanged: { dragging in
                    isDragging = dragging
                    if !dragging {
                        onSeek(value)
                    }
                },
                isDragging: $isDragging
            )
            .scaleEffect(isDragging ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isDragging)
            .frame(width: 335, height: 24) // 터치 고려해 전체 높이는 넉넉히
            .padding(.top, 4)

            HStack {
                Text(formatTime(value))
                Spacer()
                Text("-" + formatTime(duration - value))
            }
            .font(.footnote)
            .monospacedDigit()
            .foregroundColor(.secondary)
            .frame(width: 335)
        }
    }

    private func formatTime(_ time: Double) -> String {
        String(format: "%d:%02d", Int(time) / 60, Int(time) % 60)
    }
}

struct VolumeSliderView: View {
    @Binding var volume: Float
    @State private var isDragging = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")

            CustomProgressSlider(
                value: Binding(
                    get: { Double(volume) },
                    set: { newValue in
                        volume = Float(min(newValue, 1.0))
                    }
                ),
                range: 0...1,
                onEditingChanged: { dragging in
                    isDragging = dragging
                },
                isDragging: $isDragging
            )
            .frame(height:48)
            .padding(.vertical, 6)

            Image(systemName: "speaker.wave.3.fill")
        }
        .frame(width: 335)
    }
}

struct AirPlayButtonView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let routePickerView = AVRoutePickerView()
        routePickerView.activeTintColor = UIColor.label  // 연결 시 색상
        routePickerView.tintColor = UIColor.label        // 기본 색상
        routePickerView.backgroundColor = .clear         // 배경 투명

        // Optional: 아이콘 스타일 변경 방지
        routePickerView.prioritizesVideoDevices = false

        return routePickerView
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

//struct PlayerModalWrapperView: View {
//    let record: RecordListModel
//    @ObservedObject var audioPlayer: AudioPlayerManager
//    var onDismiss: () -> Void
//
//    @State private var dragOffset: CGFloat = 0
//
//    var body: some View {
//        ZStack {
//            Color.black.opacity(0.001) // 배경 클릭 방지용
//                .ignoresSafeArea()
//
//            PlayerView(record: record, audioPlayer: audioPlayer)
//                .offset(y: max(0, dragOffset))
//                .scaleEffect(dragScale)
//                .gesture(
//                    DragGesture()
//                        .onChanged { value in
//                            if value.translation.height > 0 {
//                                dragOffset = value.translation.height
//                            }
//                        }
//                        .onEnded { value in
//                            if value.translation.height > 150 {
//                                onDismiss()
//                            } else {
//                                withAnimation(.spring()) {
//                                    dragOffset = 0
//                                }
//                            }
//                        }
//                )
//                .animation(.easeOut(duration: 0.2), value: dragOffset)
//        }
//    }
//
//    private var dragScale: CGFloat {
//        let maxOffset: CGFloat = 300
//        let scale = 1 - (min(dragOffset, maxOffset) / maxOffset) * 0.1
//        return scale
//    }
//}

