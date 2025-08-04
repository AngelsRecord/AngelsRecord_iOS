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
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        return true
    }
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

        let thumbSize = CGSize(width: 16, height: 16)
        let thumb = UIGraphicsImageRenderer(size: thumbSize).image { context in
            let rect = CGRect(origin: .zero, size: thumbSize)
            let path = UIBezierPath(ovalIn: rect)
            UIColor.black.withAlphaComponent(0.001).setFill()
            path.fill()
        }
        slider.setThumbImage(thumb, for: .normal)

        let trackHeight = slider.trackHeight
        let cornerRadius = trackHeight / 2
        let trackWidth: CGFloat = 12
        let capInset: CGFloat = 6
        let trackSize = CGSize(width: trackWidth, height: trackHeight)
        let minTrackImage = UIGraphicsImageRenderer(size: trackSize).image { _ in
            let path = UIBezierPath(
                roundedRect: CGRect(origin: .zero, size: trackSize),
                cornerRadius: cornerRadius
            )
            UIColor.label.setFill()
            path.fill()
        }

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
    let record: RecordListModel
    @ObservedObject var audioPlayer: AudioPlayerManager
    let onDelete: () -> Void
    let onNextEpisode: () -> Void

    var body: some View {
        HStack(spacing: 16) {
        
            Image("mainimage_yet")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                Text(record.title)
                    .font(Font.SFPro.Medium.s16)
                    .foregroundColor(.mainText)
                    .lineLimit(1)
                
                Text(formattedDate(record.addedDate))
                    .font(Font.SFPro.Medium.s14)
                    .foregroundColor(.subText)
                    .lineLimit(1)
            }
            
            Spacer()
            Button(action: {
                audioPlayer.togglePlayPause()
            }) {
                Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
            }
            
            Button(action: {
                onNextEpisode()
            }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
            }
        }
        .offset(y: -10)
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(height: 90)
        .background(
            Color(UIColor.systemBackground)
                .cornerRadius(12)
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
            onDelete: {},
            onNextEpisode: {}
        )
    }
    .background(Color.gray.opacity(0.1))
}


struct PlaybackSliderView: View {
    @Binding var value: Double
    var duration: Double
    @Binding var isDragging: Bool
    var onSeek: (Double) -> Void
  
  @Binding var displayedTime: Double

@ObservedObject var audioPlayer: AudioPlayerManager
@State private var isDraggingSlider = false
@State private var internalValue: Double = 0
@State private var lastSeekTime = Date.distantPast


    var body: some View {
        VStack(spacing: 6) {
            CustomProgressSlider(
                value: $internalValue,
                range: 0...max(duration, 1),
                onEditingChanged: { dragging in
                    isDraggingSlider = dragging

                    if !dragging {
                        lastSeekTime = Date()
                        let finalValue = internalValue
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            onSeek(finalValue)
                        }
                    }
                },
                isDragging: $isDraggingSlider
            )
            .scaleEffect(
                CGSize(width: isDraggingSlider ? 1.03 : 1.0, height: isDraggingSlider ? 1.15 : 1.0),
                anchor: .center
            )
            .animation(.easeInOut(duration: 0.2), value: isDraggingSlider)
            .frame(width: 335, height: 24)
            .padding(.top, 4)

            HStack {

                Text(formatTime(displayedTime))
                Spacer()
                Text("-" + formatTime(duration - displayedTime))
            }
            .font(.footnote)
            .monospacedDigit()
            .foregroundColor(.secondary)
            .frame(width: 335)
            .scaleEffect(
                CGSize(width: isDraggingSlider ? 1.03 : 1.0, height: isDraggingSlider ? 1.03 : 1.0),
                anchor: .center
            )
            .animation(.easeInOut(duration: 0.2), value: isDraggingSlider)
        }
        .onAppear {
            internalValue = value
        }
        .onChange(of: value) { newValue in
            guard !isDragging else { return }
            guard Date().timeIntervalSince(lastSeekTime) > 0.4 else { return }
            withAnimation(.linear(duration: 0.4)) {
                if newValue >= duration - 1 {
                    internalValue = duration
                } else {
                    internalValue = min(newValue, duration * 0.998)
                }
            }
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

            Image(systemName: "speaker.wave.3.fill")
        }
        .frame(width: 335)
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
