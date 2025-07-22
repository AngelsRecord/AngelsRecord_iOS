import AVFoundation
import MediaPlayer
import SwiftUI

struct PlayerView: View {
    @State public var record: RecordListModel
    @ObservedObject public var audioPlayer: AudioPlayerManager
    var onDismiss: () -> Void
    var nextItems: [RecordListModel]

    @Environment(\.dismiss) var dismiss
    @State private var isDragging = false
    @State private var sliderValue: Double = 0
    @State private var displayedTime: Double = 0
    @State private var volume: Float = AVAudioSession.sharedInstance().outputVolume
    @State private var animatedVolume: Float = AVAudioSession.sharedInstance().outputVolume
    @State private var dragOffset: CGFloat = 0
    @State private var volumeUpdateTimer: Timer?
    @State private var systemVolumeManager = SystemVolumeManager()

    @State private var isExpanded = true
    @State private var showPlaylist = false

    @Namespace var animation

    private var volumeObserver = SystemVolumeObserver()

    public init(record: RecordListModel, audioPlayer: AudioPlayerManager, onDismiss: @escaping () -> Void, nextItems: [RecordListModel]) {
        _record = State(initialValue: record)
        self.record = record
        self.audioPlayer = audioPlayer
        self.onDismiss = onDismiss
        self.nextItems = nextItems
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.001)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Capsule()
                    .frame(width: 40, height: 5)
                    .foregroundColor(.gray)
                    .padding(.top, 10)
                    .padding(.bottom, 10)

                // MARK: - 현재 재생 Card

                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 0) {
                        Image("mainimage_yet")
                            .resizable()
                            .aspectRatio(1, contentMode: .fit)
                            .matchedGeometryEffect(id: "coverImage", in: animation)
                            .scaleEffect(isExpanded ? (audioPlayer.isPlaying ? 1.0 : 0.95) : 1.0)
                            .frame(width: isExpanded ? nil : 60,
                                   height: isExpanded ? nil : 60)
                            .frame(maxWidth: isExpanded ? .infinity : 60, alignment: isExpanded ? .center : .leading)
                            .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 16 : 4))
                            .shadow(radius: isExpanded ? 10 : 0)
                            .padding(.trailing, isExpanded ? 0 : 12)
                            .padding(.top, 16)
                            .animation(.spring(), value: isExpanded)
                            .animation(.easeInOut(duration: 0.3), value: audioPlayer.isPlaying)

                        if !isExpanded { // 버튼 클릭했을 때
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    MarqueeText(
                                        text: record.title,
                                        font: .systemFont(ofSize: 16, weight: .semibold),
                                        leftFade: 16,
                                        rightFade: 16,
                                        startDelay: 1.0
                                    )
                                    .makeCompact()
                                    .frame(height: 24)

                                    Text("엔젤스")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                }

                                Spacer()

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
                            .padding(.top, 16)
                        }
                    } // 현재 재생 사진

                    if isExpanded {
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
                        .padding(.top, 32)
                    }
                }
                if showPlaylist {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("재생 목록")
                                .font(.title3)
                                .fontWeight(.semibold)

                            Spacer()
                        }
                        .padding(.top, 36)
                        .padding(.bottom, 10)

                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(nextItems) { item in
                                    playlistItemButton(for: item)
                                }
                                Spacer().frame(height: 10)
                            }
                            .padding(.top, 10)
                        }
                        .frame(height: 350)
                        .overlay(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.background.opacity(0.0), Color.background]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 30)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                        )
                    }
                    .padding(.bottom, 150)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(), value: showPlaylist)
                }

                Spacer()
            }
            .padding(.horizontal, 24)

            // MARK: - 재생 컨트롤 영역

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 0) {
                    PlaybackSliderView(
                        value: $sliderValue,
                        duration: audioPlayer.duration,
                        isDragging: $isDragging,
                        onSeek: { newValue in
                            audioPlayer.seek(to: newValue)
                        },
                        displayedTime: $displayedTime,
                        audioPlayer: audioPlayer
                    )
                    .onReceive(audioPlayer.$currentTime) { newValue in
                        if !isDragging {
                            withAnimation(.linear(duration: 0.2)) {
                                sliderValue = newValue
                            }
                            displayedTime = newValue // 시간 표시
                        }
                    }

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
                    .padding(.top, 36)
                    .scaleEffect(isDragging ? 1.0125 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: isDragging)

                    VolumeSliderView(volume: Binding(
                        get: { self.animatedVolume },
                        set: { newVolume in
                            self.animatedVolume = newVolume
                            self.volume = newVolume
                            self.systemVolumeManager.setSystemVolume(newVolume)
                        }
                    ))
                    .scaleEffect(isDragging ? 1.0125 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: isDragging)
                    .padding(.top, 32)

                    HStack(spacing: 50) {
                        AirPlayButtonView()
                            .frame(width: 24, height: 24)
                            .foregroundColor(.mainText)

                        // MARK: - PlayListView

                        Button(action: {
                            if isExpanded {
                                withAnimation(.spring()) {
                                    isExpanded = false
                                    showPlaylist = true
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
                    .padding(.top, 12)
                }
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
                .background(
                    Color.background
                        .ignoresSafeArea(edges: .horizontal)
                        .ignoresSafeArea(edges: .bottom)
                )
            }
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
//        }
        .background(HiddenSystemVolumeView().frame(width: 0, height: 0))
        .onAppear {
            volumeObserver.onVolumeChange = { newVolume in
                DispatchQueue.main.async {
                    self.volume = newVolume
                    self.animatedVolume = newVolume // ✅ 슬라이더 동기화
                    self.audioPlayer.setVolume(newVolume) // ✅ 시스템 볼륨 → audioPlayer 반영
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
        formatter.dateFormat = "MMM d" // 예: May 15
        formatter.locale = Locale(identifier: "en_US") // 영어로 표기
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

    private func playlistItemButton(for item: RecordListModel) -> some View {
        Button(action: {
            self.audioPlayer.stop()
            if let url = item.fileURL {
                self.audioPlayer.prepareToPlay(url: url)
                self.audioPlayer.play(item)
            }
            self.record = item
        }) {
            PlayListView(record: item)
        }
        .buttonStyle(PlainButtonStyle())
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

struct PlayerView_Previews: PreviewProvider {
    static var previews: some View {
        PlayerView(
            record: mockRecord,
            audioPlayer: mockAudioPlayer,
            onDismiss: {},
            nextItems: [
                mockNext1, mockNext2, mockNext3, mockNext4, mockNext5,
                mockNext6, mockNext7, mockNext8, mockNext9, mockNext10
            ]
        )
        .preferredColorScheme(.light)
    }

    static var mockRecord: RecordListModel {
        RecordListModel(
            title: "테스트 녹음인데 엄청 길게 작성해서 테스트를 또 해볼려고 하압니다.",
//            title: "짧게.",
            artist: "엔젤스",
            duration: 120.0, // seconds
            fileURL: URL(fileURLWithPath: "/dev/null")
        )
    }

    static var mockAudioPlayer: AudioPlayerManager {
        let player = AudioPlayerManager()
        player.duration = 120.0
        player.currentTime = 45.0
        player.isPlaying = true
        return player
    }

    static var mockNext1: RecordListModel {
        RecordListModel(
            title: "다음 녹음 1",
            artist: "엔젤스",
            duration: 90.0,
            fileURL: URL(fileURLWithPath: "/dev/null")
        )
    }

    static var mockNext2: RecordListModel {
        RecordListModel(
            title: "다음 녹음 2",
            artist: "엔젤스",
            duration: 100.0,
            fileURL: URL(fileURLWithPath: "/dev/null")
        )
    }

    static var mockNext3: RecordListModel {
        RecordListModel(
            title: "다음 녹음 3",
            artist: "엔젤스",
            duration: 95.0,
            fileURL: URL(fileURLWithPath: "/dev/null")
        )
    }

    static var mockNext4: RecordListModel {
        RecordListModel(
            title: "다음 녹음 4",
            artist: "엔젤스",
            duration: 110.0,
            fileURL: URL(fileURLWithPath: "/dev/null")
        )
    }

    static var mockNext5: RecordListModel {
        RecordListModel(
            title: "다음 녹음 5",
            artist: "엔젤스",
            duration: 87.0,
            fileURL: URL(fileURLWithPath: "/dev/null")
        )
    }

    static var mockNext6: RecordListModel {
        RecordListModel(
            title: "다음 녹음 6",
            artist: "엔젤스",
            duration: 93.0,
            fileURL: URL(fileURLWithPath: "/dev/null")
        )
    }

    static var mockNext7: RecordListModel {
        RecordListModel(
            title: "다음 녹음 7",
            artist: "엔젤스",
            duration: 105.0,
            fileURL: URL(fileURLWithPath: "/dev/null")
        )
    }

    static var mockNext8: RecordListModel {
        RecordListModel(
            title: "다음 녹음 8",
            artist: "엔젤스",
            duration: 101.0,
            fileURL: URL(fileURLWithPath: "/dev/null")
        )
    }

    static var mockNext9: RecordListModel {
        RecordListModel(
            title: "다음 녹음 9",
            artist: "엔젤스",
            duration: 98.0,
            fileURL: URL(fileURLWithPath: "/dev/null")
        )
    }

    static var mockNext10: RecordListModel {
        RecordListModel(
            title: "다음 녹음 10",
            artist: "엔젤스",
            duration: 112.0,
            fileURL: URL(fileURLWithPath: "/dev/null")
        )
    }
}
