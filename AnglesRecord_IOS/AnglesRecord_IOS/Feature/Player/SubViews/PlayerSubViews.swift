import SwiftUI
import UIKit
import AVKit

// MARK: - 커스텀 UISlider (트랙 두께 조정)
class ThickerSlider: UISlider {
    var trackHeight: CGFloat = 6

    override func trackRect(forBounds bounds: CGRect) -> CGRect {
        let original = super.trackRect(forBounds: bounds)
        return CGRect(
            x: original.origin.x,
            y: original.origin.y + (original.height - trackHeight) / 2,
            width: original.width,
            height: trackHeight
        )
    }

    // ✅ 아무 곳에서 드래그 시작 가능
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        return true  // 슬라이드 시작은 허용하되 값은 아직 변경하지 않음
    }

    // ✅ 실제 드래그 중일 때 값 업데이트
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let point = touch.location(in: self)
        let percentage = max(0, min(1, point.x / bounds.width))
        let delta = Float(percentage) * (maximumValue - minimumValue)
        let newValue = minimumValue + delta

        setValue(newValue, animated: false)
        sendActions(for: .valueChanged)
        return true
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
        slider.trackHeight = 6
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)

        // Thumb
        let thumbSize = CGSize(width: 16, height: 16)
        let thumb = UIGraphicsImageRenderer(size: thumbSize).image { context in
            let rect = CGRect(origin: .zero, size: thumbSize)
            let path = UIBezierPath(ovalIn: rect)
            UIColor.black.withAlphaComponent(0.001).setFill()
            path.fill()
        }
        slider.setThumbImage(thumb, for: .normal)

        // 둥근 트랙 이미지 만들기 (width는 최소 8 이상, 가운데 stretch 가능하게)
        let trackHeight = slider.trackHeight
        let cornerRadius = trackHeight / 2
        let trackWidth: CGFloat = 12  // ✅ 좌우 6px씩 모서리를 cap으로 보호
        let capInset: CGFloat = 6

        let trackSize = CGSize(width: trackWidth, height: trackHeight)

        // 왼쪽 (진행된) 트랙 이미지
        let minTrackImage = UIGraphicsImageRenderer(size: trackSize).image { _ in
            let path = UIBezierPath(
                roundedRect: CGRect(origin: .zero, size: trackSize),
                cornerRadius: cornerRadius
            )
            UIColor.label.setFill()
            path.fill()
        }

        // 오른쪽 (남은) 트랙 이미지
        let maxTrackImage = UIGraphicsImageRenderer(size: trackSize).image { _ in
            let path = UIBezierPath(
                roundedRect: CGRect(origin: .zero, size: trackSize),
                cornerRadius: cornerRadius
            )
            UIColor.systemGray5.setFill()
            path.fill()
        }

        let capInsets = UIEdgeInsets(top: 0, left: capInset, bottom: 0, right: capInset)

        slider.setMinimumTrackImage(
            minTrackImage.resizableImage(withCapInsets: capInsets, resizingMode: .stretch),
            for: .normal
        )

        slider.setMaximumTrackImage(
            maxTrackImage.resizableImage(withCapInsets: capInsets, resizingMode: .stretch),
            for: .normal
        )

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
        HStack(spacing: 16) {
            // 앨범 이미지
            Image("mainimage_yet")
                .resizable()
                .scaledToFit()
                .frame(width: 50, height: 50)
                .cornerRadius(8)
            
            // 제목과 아티스트
            VStack(alignment: .leading, spacing: 4) {
                Text(record.title)
                    .font(Font.SFPro.Medium.s16)
                    .foregroundColor(.mainText)
                    .lineLimit(1)
                
                Text(record.artist)
                    .font(Font.SFPro.Medium.s14)
                    .foregroundColor(.subText)
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


struct PlaybackSliderView: View {
    @Binding var value: Double
    var duration: Double
    @Binding var isDragging: Bool
    var onSeek: (Double) -> Void
    @ObservedObject var audioPlayer: AudioPlayerManager
    @State private var lastSeekTime = Date.distantPast

    var body: some View {
        VStack(spacing: 6) {
            CustomProgressSlider(
                value: $value,
                range: 0...max(duration, 1),
                onEditingChanged: { dragging in
                    isDragging = dragging
                    if !dragging {
                        lastSeekTime = Date()
                        let finalValue = value
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            onSeek(finalValue)
                        }
                    }
                },
                isDragging: $isDragging
            )
            .scaleEffect(
                CGSize(width: isDragging ? 1.03 : 1.0, height: isDragging ? 1.15 : 1.0),
                anchor: .center
            )
            .animation(.easeInOut(duration: 0.25), value: isDragging)
            .frame(width: 335, height: 24)
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
            .scaleEffect(x: isDragging ? 1.03 : 1.0)
            .animation(.easeInOut(duration: 0.25), value: isDragging)
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
