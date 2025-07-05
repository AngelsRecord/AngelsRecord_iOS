import AVFoundation
import MediaPlayer
import SwiftUI

struct PlayerView: View {
    public let record: RecordListModel
    @ObservedObject public var audioPlayer: AudioPlayerManager
    var onDismiss: () -> Void

    @Environment(\.dismiss) var dismiss
    @State private var isDragging = false
    @State private var sliderValue: Double = 0
    @State private var displayedTime: Double = 0
    @State private var volume: Float = AVAudioSession.sharedInstance().outputVolume
    @State private var animatedVolume: Float = AVAudioSession.sharedInstance().outputVolume
    @State private var dragOffset: CGFloat = 0
    @State private var volumeUpdateTimer: Timer?

    @State private var isExpanded = true
    @State private var showPlaylist = false

    private var volumeObserver = SystemVolumeObserver()

    public init(record: RecordListModel, audioPlayer: AudioPlayerManager, onDismiss: @escaping () -> Void) {
        self.record = record
        self.audioPlayer = audioPlayer
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.001)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Capsule()
                    .frame(width: 40, height: 5)
                    .foregroundColor(.gray)
                    .padding(.top, 55)
                    .padding(.bottom, 10)

                Image("mainimage_yet")
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .scaleEffect(audioPlayer.isPlaying ? 1.0 : 0.95)
                    .cornerRadius(16)
                    .shadow(radius: 10)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .animation(.easeInOut(duration: 0.3), value: audioPlayer.isPlaying)

                VStack(spacing: 16) {
                    VStack(spacing: 4) {
                        Text(formattedDate(record.addedDate))
                            .font(.caption)
                            .foregroundColor(.subText)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                // MARK: - Title

                                MarqueeText(
                                    text: record.title,
                                    font: UIFont.SFPro.SemiBold.s16,
                                    leftFade: 16,
                                    rightFade: 16,
                                    startDelay: 3.0,
                                    alignment: .leading
                                )
                                .makeCompact()
                                .foregroundColor(.mainText)

                                Text("엔젤스")
                                    .font(.subheadline)
                                    .foregroundColor(.subText)
                            }

                            Spacer()

                            // MARK: - 배속 버튼

                            Menu {
                                Button("2x") { audioPlayer.setRate(2.0) }
                                Button("1.75x") { audioPlayer.setRate(1.75) }
                                Button("1.5x") { audioPlayer.setRate(1.5) }
                                Button("1x") { audioPlayer.setRate(1.0) }
                                Button("0.75x") { audioPlayer.setRate(0.75) }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .padding(10)
                                    .background(Color(UIColor.systemGray5))
                                    .clipShape(Circle())
                                    .foregroundColor(.mainText)
                            }
                            .alignmentGuide(.firstTextBaseline) { context in
                                context[.firstTextBaseline]
                            }
                        }
                    }
                    .padding(.horizontal, 24)

                    PlaybackSliderView(
                        value: $sliderValue,
                        duration: audioPlayer.duration,
                        isDragging: $isDragging,
                        onSeek: { newValue in
                            audioPlayer.seek(to: newValue)
                        },
                        displayedTime: $displayedTime
                    )
                    .onReceive(audioPlayer.$currentTime) { newValue in
                        if !isDragging {
                            withAnimation(.linear(duration: 0.2)) {
                                sliderValue = newValue // 슬라이더는 부드럽게
                            }
                            displayedTime = newValue // 시간 표시는 즉시 변경
                        }
                    }
                    .padding(.horizontal, 24)

                    HStack(spacing: 50) {
                        Button {
                            audioPlayer.skip(seconds: -15)
                        } label: {
                            Image(systemName: "gobackward.15")
                                .font(.system(size: 28))
                                .foregroundColor(.mainText)
                        }

                        Button {
                            audioPlayer.togglePlayPause()
                        } label: {
                            Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.mainText)
                        }

                        Button {
                            audioPlayer.skip(seconds: 30)
                        } label: {
                            Image(systemName: "goforward.30")
                                .font(.system(size: 28))
                                .foregroundColor(.mainText)
                        }
                    }
                    .padding(.top, 8)
                    .scaleEffect(isDragging ? 1.0125 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: isDragging)

                    VolumeSliderView(volume: $animatedVolume)
                        .scaleEffect(isDragging ? 1.0125 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: isDragging)
                        .padding(.horizontal, 24)

                    HStack(spacing: 50) {
                        AirPlayButtonView()
                            .frame(width: 24, height: 24)
                            .foregroundColor(.mainText)

                        // MARK: - PlayListView

                        Button(action: {
                            if isExpanded {
                                withAnimation(.spring()) {
                                    isExpanded = false
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    withAnimation(.spring()) {
                                        showPlaylist = true
                                    }
                                }
                            } else {
                                withAnimation(.spring()) {
                                    showPlaylist = false
                                    isExpanded = true
                                }
                            }
                        }) {
                            Image(systemName: "list.bullet")
                                .font(.title3)
                                .foregroundColor(.mainText)
                        }
                    }
                    .scaleEffect(isDragging ? 1.0125 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: isDragging)
                    .padding(.top, 8)

                    Spacer(minLength: 32)
                }
                .padding(.top, 40)
                .padding(.bottom, 24)
            }
            .offset(y: max(0, dragOffset))
            .scaleEffect(dragScale)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.height > 0 {
                            dragOffset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if value.translation.height > 150 {
                            onDismiss()
                        } else {
                            withAnimation(.spring()) {
                                dragOffset = 0
                            }
                        }
                    }
            )
            .animation(.easeOut(duration: 0.2), value: dragOffset)
        }
        .background(HiddenSystemVolumeView().frame(width: 0, height: 0))
        .onAppear {
            volumeObserver.onVolumeChange = { newVolume in
                DispatchQueue.main.async {
                    self.volume = newVolume
                    self.startVolumeAnimation()
                }
            }
        }
    }

    private var dragScale: CGFloat {
        let maxOffset: CGFloat = 300
        let scale = 1 - (min(dragOffset, maxOffset) / maxOffset) * 0.1
        return scale
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M월 d일"
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter.string(from: date)
    }

    private func startVolumeAnimation() {
        volumeUpdateTimer?.invalidate()

        volumeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { timer in
            let step: Float = 0.02
            if abs(animatedVolume - volume) < step {
                animatedVolume = volume
                timer.invalidate()
            } else if animatedVolume < volume {
                animatedVolume += step
            } else {
                animatedVolume -= step
            }
        }
    }
}

class SystemVolumeObserver {
    private var observation: NSKeyValueObservation?
    private let audioSession = AVAudioSession.sharedInstance()

    var onVolumeChange: ((Float) -> Void)?

    init() {
        try? audioSession.setActive(true)
        observation = audioSession.observe(\AVAudioSession.outputVolume, options: [.new]) { [weak self] _, change in
            if let newVolume = change.newValue {
                self?.onVolumeChange?(newVolume)
            }
        }
    }

    deinit {
        observation?.invalidate()
    }
}

struct HiddenSystemVolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.alpha = 0.0001
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
