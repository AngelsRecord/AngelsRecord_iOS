import AVFoundation
import MediaPlayer
import SwiftUI

struct PlayerView: View {
    @State public var record: RecordListModel
    @ObservedObject public var audioPlayer: AudioPlayerManager
    var onDismiss: () -> Void

    // 전역 재생 큐
    @EnvironmentObject private var playQueue: PlayQueueManager

    @Environment(\.dismiss) var dismiss

    // --- UI State ---
    @State private var isDragging = false
    @State private var sliderValue: Double = 0
    @State private var displayedTime: Double = 0
    @State private var volume: Float = AVAudioSession.sharedInstance().outputVolume
    @State private var animatedVolume: Float = AVAudioSession.sharedInstance().outputVolume
    @State private var dragOffset: CGFloat = 0
    @State private var volumeUpdateTimer: Timer?
    @State private var systemVolumeManager = SystemVolumeManager()
    @State private var playButtonScale: CGFloat = 1.0

    @State private var isExpanded = true
    @State private var showPlaylist = false
    @State private var trackKey: String = ""
    @State private var playlistAutoAlignToken = 0

    // 재정렬 토글
    @State private var editMode: EditMode = .active

    @Namespace var animation
    private var volumeObserver = SystemVolumeObserver()

    // MARK: - Init
    public init(record: RecordListModel, audioPlayer: AudioPlayerManager, onDismiss: @escaping () -> Void) {
        _record = State(initialValue: record)
        self.record = record
        self.audioPlayer = audioPlayer
        self.onDismiss = onDismiss
    }

    // MARK: - Body
    public var body: some View {
        ZStack {
            Color.black.opacity(0.001).ignoresSafeArea()

            VStack(spacing: 0) {
                // 핸들
                Capsule()
                    .frame(width: 40, height: 5)
                    .foregroundColor(.gray)
                    .padding(.top, 10)
                    .padding(.bottom, 10)

                // MARK: - 현재 재생 카드
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 0) {
                        Image("mainimage_yet")
                            .resizable()
                            .aspectRatio(1, contentMode: .fit)
                            .matchedGeometryEffect(id: "coverImage", in: animation)
                            .scaleEffect(isExpanded ? (audioPlayer.isPlaying ? 1.0 : 0.95) : 1.0)
                            .frame(width: isExpanded ? nil : 60,
                                   height: isExpanded ? nil : 60)
                            .frame(maxWidth: isExpanded ? .infinity : 60,
                                   alignment: isExpanded ? .center : .leading)
                            .padding(.trailing, isExpanded ? 0 : 12)
                            .padding(.top, 16)
                            .animation(.spring(), value: isExpanded)
                            .animation(.easeInOut(duration: 0.3), value: audioPlayer.isPlaying)

                        if !isExpanded {
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
                    }

                    if isExpanded {
                        VStack(spacing: 4) {
                            // 날짜 표시는 uploadedAt 기반 formattedDate 사용
                            Text(record.formattedDate)
                                .font(.caption)
                                .foregroundColor(.subText)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
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

                // MARK: - 플리 보이기
                if showPlaylist {
                    PlaylistPanelView(
                        editMode: $editMode,
                        currentId: playQueue.current?.id,
                        items: playQueue.items,
                        onMove: { from, to in playQueue.move(fromOffsets: from, toOffset: to) },
                        onTap: { tapped in
                            if let idx = playQueue.items.firstIndex(where: { $0.id == tapped.id }) {
                                playQueue.setFromRecords(playQueue.items, startAt: idx)
                                record = tapped
                                audioPlayer.play(tapped)
                                trackKey = makeTrackKey(from: tapped)
                                sliderValue = 0; displayedTime = 0; isDragging = false
                                playlistAutoAlignToken &+= 1
                            }
                        },
                        autoAlignToken: playlistAutoAlignToken
                    )
                    .padding(.horizontal, -20)
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
                        onSeek: { newValue in audioPlayer.seek(to: newValue) },
                        displayedTime: $displayedTime,
                        audioPlayer: audioPlayer,
                        trackKey: trackKey
                    )
                    .id(trackKey)
                    .onReceive(audioPlayer.$currentTime) { newValue in
                        if !isDragging {
                            withAnimation(.linear(duration: 0.2)) {
                                sliderValue = newValue
                            }
                            displayedTime = newValue
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
                            withAnimation(.easeIn(duration: 0.1)) {
                                playButtonScale = 0.8
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                audioPlayer.togglePlayPause()
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                                    playButtonScale = 1.0
                                }
                            }
                        } label: {
                            Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.mainText)
                                .scaleEffect(playButtonScale)
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
                    .padding(.horizontal, 24)

                    HStack(spacing: 50) {
                        AirPlayButtonView()
                            .frame(width: 24, height: 24)
                            .foregroundColor(.mainText)

                        HStack(spacing: 16) {
                            // 플레이리스트 토글
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
        .background(HiddenSystemVolumeView().frame(width: 0, height: 0))
        // 트랙 완료 → 큐 기반 다음으로 (없으면 정지)
        .onReceive(audioPlayer.finishedPublisher) { _ in
            guard playQueue.hasNext else { audioPlayer.stop(); return }
            playQueue.advance()
            if let next = playQueue.current {
                record = next
                audioPlayer.play(next)
                trackKey = makeTrackKey(from: next)
                sliderValue = 0; displayedTime = 0; isDragging = false
                playlistAutoAlignToken &+= 1
            }
        }
        .onAppear {
            trackKey = makeTrackKey(from: record)

            // 시스템 볼륨 동기화
            volumeObserver.onVolumeChange = { newVolume in
                DispatchQueue.main.async {
                    self.volume = newVolume
                    self.animatedVolume = newVolume
                    self.audioPlayer.setVolume(newVolume)
                    self.startVolumeAnimation()
                }
            }

            // 리모콘 next/prev → 큐 연동 (MainView에서도 백업으로 세팅 가능)
            audioPlayer.onNextTrack = {
                guard playQueue.hasNext else { audioPlayer.stop(); return }
                playQueue.advance()
                if let next = playQueue.current {
                    record = next
                    audioPlayer.play(next)
                    trackKey = makeTrackKey(from: next)
                    sliderValue = 0; displayedTime = 0; isDragging = false
                }
            }
            audioPlayer.onPrevTrack = {
                guard playQueue.hasPrev else { return }
                playQueue.back()
                if let prev = playQueue.current {
                    record = prev
                    audioPlayer.play(prev)
                    trackKey = makeTrackKey(from: prev)
                    sliderValue = 0; displayedTime = 0; isDragging = false
                }
            }
        }
    }

    // MARK: - Helpers
    private func makeTrackKey(from r: RecordListModel) -> String {
        let u = r.fileURL?.absoluteString ?? UUID().uuidString
        return "\(u)#\(Int(r.duration))#\(r.title.hashValue)"
    }

    private var dragScale: CGFloat {
        let maxOffset: CGFloat = 300
        let scale = 1 - (min(dragOffset, maxOffset) / maxOffset) * 0.1
        return scale
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
