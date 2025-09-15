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
        return true
    }

    // ✅ 실제 드래그 중일 때 값 업데이트
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let point = touch.location(in: self)
        let percentage = max(0, min(1, point.x / bounds.width))
        // 실제 트랙(rect) 기준으로 퍼센트 계산 (좌우 여백 보정)
        let track = self.trackRect(forBounds: bounds)
        let x = max(track.minX, min(point.x, track.maxX))
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

    @Environment(\.colorScheme) private var colorScheme

    // Helper to generate a resizable track image with a given color and size
    private func makeTrackImage(color: UIColor,
                                trackHeight: CGFloat,
                                trackWidth: CGFloat,
                                capInset: CGFloat) -> UIImage {
        let cornerRadius = trackHeight / 2
        let size = CGSize(width: trackWidth, height: trackHeight)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: cornerRadius)
            color.setFill()
            path.fill()
        }
        return image.resizableImage(
            withCapInsets: UIEdgeInsets(top: 0, left: capInset, bottom: 0, right: capInset),
            resizingMode: .stretch
        )
    }

    func makeUIView(context: Context) -> ThickerSlider {
        let slider = ThickerSlider(frame: .zero)
        slider.trackHeight = 6
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)

        let thumbSize = CGSize(width: 16, height: 16)
        let thumb = UIGraphicsImageRenderer(size: thumbSize).image { context in
            let rect = CGRect(origin: .zero, size: thumbSize)
            let path = UIBezierPath(ovalIn: rect)
            UIColor.black.withAlphaComponent(0.001).setFill()
            path.fill()
        }
        slider.setThumbImage(thumb, for: .normal)

        // Generate dynamic track images so colors adapt to Light/Dark mode
        let trackHeight = slider.trackHeight
        let trackWidth: CGFloat = 12
        let capInset: CGFloat = 6

        let minImage = makeTrackImage(
            color: UIColor(Color("mainText")),
            trackHeight: trackHeight,
            trackWidth: trackWidth,
            capInset: capInset
        )
        let maxImage = makeTrackImage(
            color: UIColor(Color("subText")),
            trackHeight: trackHeight,
            trackWidth: trackWidth,
            capInset: capInset
        )
        slider.setMinimumTrackImage(minImage, for: .normal)
        slider.setMaximumTrackImage(maxImage, for: .normal)

        slider.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged), for: .valueChanged)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.touchDown), for: .touchDown)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.touchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        return slider
    }

    func updateUIView(_ uiView: ThickerSlider, context: Context) {
        // 1) duration 범위 동기화
        let lower = Float(range.lowerBound)
        let upper = Float(range.upperBound)
        if uiView.minimumValue != lower || uiView.maximumValue != upper {
            uiView.minimumValue = lower
            uiView.maximumValue = max(upper, lower + 0.0001) // upper==lower 방지
        }
    
        // 2) 값 동기화(클램프, 애니메이션 OFF)
        let clamped = Float(min(max(value, range.lowerBound), range.upperBound))
        if uiView.value != clamped {
            uiView.setValue(clamped, animated: false)
        }
        // Regenerate images on update so appearance changes (Light/Dark) are reflected
        let trackHeight = uiView.trackHeight
        let trackWidth: CGFloat = 12
        let capInset: CGFloat = 6

        let minImage = makeTrackImage(
            color: UIColor(Color("mainText")),
            trackHeight: trackHeight,
            trackWidth: trackWidth,
            capInset: capInset
        )
        let maxImage = makeTrackImage(
            color: UIColor(Color("subText")),
            trackHeight: trackHeight,
            trackWidth: trackWidth,
            capInset: capInset
        )
        uiView.setMinimumTrackImage(minImage, for: .normal)
        uiView.setMaximumTrackImage(maxImage, for: .normal)
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
    convenience init?(color: UIColor, size: CGSize) {
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        color.setFill()
        UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2).fill()
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let cgImage = image?.cgImage else { return nil }
        self.init(cgImage: cgImage)
    }
    func resize(to size: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, self.scale)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext() ?? self
    }
}

struct MiniPlayerView: View {
    // ✅ 추가: 다운로드 상태 확인용
    @EnvironmentObject var recordListViewModel: RecordListViewModel

    let record: RecordListModel
    @ObservedObject var audioPlayer: AudioPlayerManager
    @State private var playButtonScale: CGFloat = 1.0
    let onDelete: () -> Void
    let onNextEpisode: () -> Void

    // ✅ (선택) 현재 에피소드의 파일명을 넘겨줄 수 있으면 정확도↑
    //    없으면 record.fileURL?.lastPathComponent로 추정
    var episodeFileName: String? = nil

    // MARK: - Derived state
    private var currentFileName: String? {
        if let episodeFileName { return episodeFileName }
        return record.fileURL?.lastPathComponent
    }

    private var isDownloading: Bool {
        guard let fn = currentFileName else { return false }
        return recordListViewModel.isDownloading(fileName: fn)
    }

    var body: some View {
        HStack(spacing: 16) {

            // ✅ 이미지: 다운로드 중일 땐 tempcover 사용
            (isDownloading ? Image("tempcover") : Image("mainimage_yet"))
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .cornerRadius(8)

            // 제목 + 날짜
            VStack(alignment: .leading, spacing: 4) {
                if isDownloading {
                    // ✅ 다운로드 중 텍스트
                    Text("로드 중...")
                        .font(Font.SFPro.Medium.s16)
                        .foregroundColor(.mainText)
                        .lineLimit(1)
                        .contentTransition(.identity)
                } else {
                    Text(record.title)
                        .font(Font.SFPro.Medium.s16)
                        .foregroundColor(.mainText)
                        .lineLimit(1)
                        .contentTransition(.identity)

                    Text(record.formattedDate)
                        .font(Font.SFPro.Medium.s14)
                        .foregroundColor(.subText)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                // 재생/일시정지 버튼
                Button {
                    withAnimation(.easeIn(duration: 0.1)) { playButtonScale = 0.8 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        audioPlayer.togglePlayPause()
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                            playButtonScale = 1.0
                        }
                    }
                } label: {
                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.primary)
                        .scaleEffect(playButtonScale)
                        .frame(width: 44, height: 44)
                }

                // 다음곡 버튼
                Button(action: { onNextEpisode() }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                }
            }
        }
        .offset(y: -10)
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(height: 90)
        .background(
            Color.background
                .cornerRadius(8)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: -5)
        )
        .padding(.bottom, -40)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M월 d일"
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter.string(from: date)
    }
}

struct VolumeSliderView: View {
    @Binding var volume: Float
    @State private var isDragging = false

    var body: some View {
        HStack(spacing: 16) {
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

            Image(systemName: "speaker.wave.3.fill")
        }
        .frame(maxWidth: .infinity)
    }
}

struct AirPlayButtonView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let routePickerView = AVRoutePickerView()
        routePickerView.activeTintColor = UIColor.label
        routePickerView.tintColor = UIColor.label
        routePickerView.backgroundColor = .clear
        routePickerView.prioritizesVideoDevices = false

        return routePickerView
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

struct PlaybackSliderView: View {
    // 현재 위치(초)
    @Binding var value: Double
    // 총 길이(초)
    let duration: Double
    // 드래그 중 여부
    @Binding var isDragging: Bool
    // 드래그 종료 시 호출되는 시킹
    let onSeek: (Double) -> Void
    // 좌측 라벨에 보여줄 “지금까지 재생된 시간(초)”
    @Binding var displayedTime: Double

    // 필요 시 상위에서 넘겨받는 객체/키 (뷰 리셋용)
    let audioPlayer: AudioPlayerManager
    let trackKey: String

    var body: some View {
        VStack(spacing: 6) {
            // 0으로 나눔/범위 0 방지용으로 최소 0.1 보장
            let safeDuration = max(duration, 0.1)

            CustomProgressSlider(
                value: $value,
                range: 0...safeDuration,
                onEditingChanged: { editing in
                    isDragging = editing
                    if !editing {
                        // 드래그 끝 → 실제 시킹
                        onSeek(value)
                    }
                },
                isDragging: $isDragging
            )
            .frame(height: 28)
            // value가 바뀔 때 라벨도 즉시 갱신(드래그 중 실시간 반영 포함)
            .onChange(of: value) { newVal in
                displayedTime = clamp(newVal, min: 0, max: safeDuration)
            }

            HStack {
                Text(formatTime(displayedTime))
                    .font(.caption)
                    .foregroundColor(.subText)
                    .monospacedDigit()

                Spacer()

                Text(formatTime(safeDuration))
                    .font(.caption)
                    .foregroundColor(.subText)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 24)
        .id(trackKey)
    }

    // MARK: - Helpers
    private func clamp(_ v: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(v, max))
    }

    private func formatTime(_ t: Double) -> String {
        guard t.isFinite && !t.isNaN else { return "0:00" }
        let secs = Int(t.rounded())
        let m = secs / 60
        let s = secs % 60
        return String(format: "%d:%02d", m, s)
    }
}
