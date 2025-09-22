import AVFoundation
import Combine
import Foundation
import MediaPlayer
import UIKit

enum PlaybackUIState: Equatable { case idle, loading, playing, paused }

final class AudioPlayerManager: NSObject,ObservableObject {
    // MARK: - Private
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var didSetupRemoteCommands = false
    private var statusObservation: AnyCancellable?

    // 배속은 NowPlaying rate에도 반영됨
    private var playbackRate: Float = 1.0

    // MARK: - Published
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 1 // 0 division 방지용 기본값
    @Published var volume: Float = 1.0
    
    @Published private(set) var uiState: PlaybackUIState = .idle
    private var timeControlCancellable: AnyCancellable?

    // MARK: - State
    var currentRecord: RecordListModel?
    
    var onNextTrack: (() -> Void)?
    var onPrevTrack: (() -> Void)?
    var onPlaybackStateChanged: ((Bool, TimeInterval) -> Void)?


    override init() {
        super.init()
        // ✅ 다른 앱이 재생 시작하면(.began) 우리 쪽으로 인터럽션 통지 받기
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        removeTimeObserverIfNeeded()
    }
    
    private func observeTimeControlStatus(of player: AVPlayer) {
        timeControlCancellable = player.publisher(for: \.timeControlStatus)
            .map { status -> PlaybackUIState in
                switch status {
                case .playing: return .playing
                case .paused: return .paused
                case .waitingToPlayAtSpecifiedRate: return .loading
                @unknown default: return .paused
                }
            }
            .removeDuplicates()
            .debounce(for: .milliseconds(120), scheduler: RunLoop.main) // ✨ 깜빡임 방지
            .receive(on: RunLoop.main)
            .sink { [weak self] st in
                guard let self = self else { return }
                self.uiState = st
                // ⬇️ 팀원이 추가했던 콜백을 최신 흐름에 맞게 호출
                self.onPlaybackStateChanged?(st == .playing, self.currentTime)
            }
    }

    // MARK: - Public API

    /// 새로운 아이템 재생 시작
    func play(_ record: RecordListModel) {
        let session = AVAudioSession.sharedInstance()
        do {
            // duckOthers/mixWithOthers 쓰지 않는 걸 권장 (외부 미디어 인수인계 방해 가능)
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true) // 이때 우리가 오디오를 잡음
        } catch {
            print("AudioSession activate error: \(error)")
        }
        
        // 1) 기존 옵저버 제거
        removeTimeObserverIfNeeded()

        // 2) 기존 플레이어 정리
        player?.pause()
        player = nil
        isPlaying = false

        // 3) 초기 시간 리셋
        currentTime = 0

        // 4) 플레이어/아이템 준비
        currentRecord = record
        let item = AVPlayerItem(url: record.fileURL!)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.volume = volume
        player = newPlayer
        
        observeTimeControlStatus(of: newPlayer)

        // 5) duration 설정 (레코드가 주는 duration 우선)
        let dur = (record.duration > 0) ? record.duration : safeSeconds(item.asset.duration)
        duration = max(0, dur)

        // 6) 타임 옵저버 + 리모트 커맨드 + Now Playing
        addPeriodicTimeObserver()
        setupRemoteCommandCenterIfNeeded()
        setupNowPlaying(record: record, full: true)

        // 7) 재생 시작
        isPlaying = true
        player?.play()
        registerRemoteCommandsIfNeeded(true)
        player?.rate = playbackRate // 배속 유지
        updateNowPlayingTime()
    }
    
    func pause(releaseToOthers: Bool = true) {
        player?.pause()
        isPlaying = false
        if releaseToOthers { surrenderAudioToOthers() }
        onPlaybackStateChanged?(isPlaying, currentTime)
    }

    // ✅ 다른 앱이 재생 시작(인터럽션 .began)했을 때: 즉시 반납
    @objc private func handleInterruption(_ note: Notification) {
        guard
            let info = note.userInfo,
            let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: raw)
        else { return }

        switch type {
        case .began:
            player?.pause()
            isPlaying = false
            surrenderAudioToOthers() // 🔑 포인트
        case .ended:
            // 자동 재개 원하면 here에서 setActive(true)+play()
            break
        @unknown default: break
        }
    }

    // 🔧 세션 반납 + 리모컨 해제
    private func surrenderAudioToOthers() {
        let session = AVAudioSession.sharedInstance()
        // 리모컨이 남아있으면 외부 앱 첫 탭이 우리 쪽으로 먹히는 경우가 있어 제거 권장
        registerRemoteCommandsIfNeeded(false)

        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
            // 이제 외부 앱이 1탭만으로 세션을 즉시 가져갈 수 있음
        } catch {
            print("AudioSession deactivate error: \(error)")
        }
    }
    
    private func registerRemoteCommandsIfNeeded(_ enable: Bool) {
            let cc = MPRemoteCommandCenter.shared()
            if enable {
                // cc.playCommand.addTarget(self, action: #selector(...))
                // cc.pauseCommand.addTarget(self, action: #selector(...))
            } else {
                cc.playCommand.removeTarget(nil)
                cc.pauseCommand.removeTarget(nil)
                cc.togglePlayPauseCommand.removeTarget(nil)
                cc.nextTrackCommand.removeTarget(nil)
                cc.previousTrackCommand.removeTarget(nil)
            }
        }
    
//    private func observeTimeControlStatus(of player: AVPlayer) {
//        // 기존 구독 해제
//        statusObservation?.cancel()
//
//        statusObservation = player.publisher(for: \.timeControlStatus, options: [.initial, .new])
//            .receive(on: DispatchQueue.main)
//            .sink { [weak self] status in
//                guard let self else { return }
//                // 시스템이 멈췄어도 버튼이 맞게 보이도록 동기화
//                self.isPlaying = (status == .playing)
//                self.updateNowPlayingTime()
//                self.onPlaybackStateChanged?(self.isPlaying, self.currentTime)
//            }
//    }
  
    /// 일시정지/재생 토글
    func togglePlayPause() {
        guard let player = player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            isPlaying = true
            player.play()
            player.rate = playbackRate
        }
        updateNowPlayingTime()
        onPlaybackStateChanged?(isPlaying, currentTime)
    }

    /// 정지
    func stop() {
        removeTimeObserverIfNeeded()
        player?.pause()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 1
        updateNowPlayingTime()
    }

    /// +/- 초 스킵
    func skip(seconds: Double) {
        seek(to: currentTime + seconds)
    }

    /// 특정 위치로 이동 (클램프)
    func seek(to time: TimeInterval) {
        guard let player = player else { return }
        let clamped = clamp(time, lower: 0, upper: duration)
        let cmTime = CMTime(seconds: clamped, preferredTimescale: 600)

        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let self else { return }
            self.currentTime = clamped
            self.updateNowPlayingTime()
            self.onPlaybackStateChanged?(self.isPlaying, self.currentTime)
        }
    }

    /// 배속 변경
    func setRate(_ rate: Float) {
        playbackRate = rate
        guard let player = player else { return }
        if rate > 0 {
            if !isPlaying {
                isPlaying = true
                player.play()
            }
            player.rate = rate
        } else {
            player.pause()
            isPlaying = false
        }
        updateNowPlayingTime()
    }

    /// 외부 URL 준비만 (재생 X)
    func prepareToPlay(url: URL) {
        removeTimeObserverIfNeeded()
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        addPeriodicTimeObserver()
        isPlaying = false
        currentTime = 0
        duration = safeSeconds(item.asset.duration)
        setupNowPlaying(record: currentRecord ?? RecordListModel(title: "", artist: "", duration: duration, fileURL: url), full: true)
        updateNowPlayingTime()
    }

    // MARK: - Volume

    func setVolume(_ newVolume: Float) {
        volume = clamp(newVolume, lower: 0, upper: 1)
        player?.volume = volume
    }

    // MARK: - Time Observer
    
    private let finishedSubject = PassthroughSubject<Void, Never>()
    var finishedPublisher: AnyPublisher<Void, Never> {
        finishedSubject.eraseToAnyPublisher()
    }

    private func addPeriodicTimeObserver() {
       guard let player = player else { return }
       removeTimeObserverIfNeeded()

       timeObserver = player.addPeriodicTimeObserver(
           forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
           queue: .main
       ) { [weak self] time in
           guard let self else { return }
           let seconds = self.safeSeconds(time)
           self.currentTime = min(max(0, seconds), self.duration)
           self.updateNowPlayingTime()
       }

       NotificationCenter.default.addObserver(
           forName: .AVPlayerItemDidPlayToEndTime,
           object: player.currentItem,
           queue: .main
       ) { [weak self] _ in
           guard let self else { return }
           self.isPlaying = false
           self.currentTime = self.duration
           self.updateNowPlayingTime()
           self.finishedSubject.send()
       }
   }

    private func removeTimeObserverIfNeeded() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
    }

    // MARK: - Now Playing

    /// 처음 세팅 또는 트랙 바뀔 때 전체 메타데이터 구성
    private func setupNowPlaying(record: RecordListModel, full: Bool) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]

        // 기본 메타데이터
        info[MPMediaItemPropertyTitle] = record.title
        info[MPMediaItemPropertyArtist] = "엔젤스"

        // 총 길이/경과
        info[MPMediaItemPropertyPlaybackDuration] = sanitize(duration)
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = sanitize(currentTime)

        // 재생/일시정지/배속
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackRate : 0.0

        // 앨범 아트
        if let image = UIImage(named: "mainimage_yet") {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// 주기적인 시간/상태 업데이트용 (경량)
    private func updateNowPlayingTime() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        let d = sanitize(duration)
        let t = clamp(sanitize(currentTime), lower: 0, upper: d)

        info[MPMediaItemPropertyPlaybackDuration] = d
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = t
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackRate : 0.0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Remote Commands

    private func setupRemoteCommandCenterIfNeeded() {
        guard !didSetupRemoteCommands else { return }
        didSetupRemoteCommands = true

        let cc = MPRemoteCommandCenter.shared()

        // ▶︎/⏸: 토글 기반 (play(record:)나 pause() 호출 X)
        cc.playCommand.isEnabled = true
        cc.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if !self.isPlaying { self.togglePlayPause() }
            return .success
        }

        cc.pauseCommand.isEnabled = true
        cc.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if self.isPlaying { self.togglePlayPause() }
            return .success
        }

        // ⏮︎/⏭︎: 큐로 연결 (없으면 무시/정지)
        cc.previousTrackCommand.isEnabled = true
        cc.previousTrackCommand.addTarget { [weak self] _ in
            self?.onPrevTrack?()
            return .success
        }

        cc.nextTrackCommand.isEnabled = true
        cc.nextTrackCommand.addTarget { [weak self] _ in
            self?.onNextTrack?()
            return .success
        }

        // ⏪ 15s / ⏩ 30s
        cc.skipBackwardCommand.isEnabled = true
        cc.skipBackwardCommand.preferredIntervals = [15]
        cc.skipBackwardCommand.addTarget { [weak self] _ in
            self?.skip(seconds: -15); return .success
        }

        cc.skipForwardCommand.isEnabled = true
        cc.skipForwardCommand.preferredIntervals = [30]
        cc.skipForwardCommand.addTarget { [weak self] _ in
            self?.skip(seconds: 30); return .success
        }

        // 시크(타임슬라이더)
        cc.changePlaybackPositionCommand.isEnabled = true
        cc.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self,
                  let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self.seek(to: e.positionTime)
            return .success
        }
    }

    // MARK: - Helpers

    private func clamp<T: Comparable>(_ x: T, lower: T, upper: T) -> T {
        min(max(x, lower), upper)
    }

    private func sanitize(_ t: TimeInterval) -> TimeInterval {
        guard t.isFinite, !t.isNaN else { return 0 }
        return max(0, t)
    }

    private func safeSeconds(_ time: CMTime) -> TimeInterval {
        guard time.isNumeric, time.isValid else { return 0 }
        let s = CMTimeGetSeconds(time)
        return s.isFinite && !s.isNaN ? s : 0
    }
}
