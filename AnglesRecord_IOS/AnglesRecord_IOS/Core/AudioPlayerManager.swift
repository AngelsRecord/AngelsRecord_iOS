import AVFoundation
import Combine
import Foundation
import MediaPlayer
import UIKit // ✅ 앨범 아트 UIImage 사용

final class AudioPlayerManager: NSObject,ObservableObject {
    // MARK: - Private
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var didSetupRemoteCommands = false

    // 배속은 NowPlaying rate에도 반영됨
    private var playbackRate: Float = 1.0

    // MARK: - Published
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 1 // 0 division 방지용 기본값
    @Published var volume: Float = 1.0

    // MARK: - State
    var currentRecord: RecordListModel?
    
    var onNextTrack: (() -> Void)?
    var onPrevTrack: (() -> Void)?


    // MARK: - Public API

    /// 새로운 아이템 재생 시작
    func play(_ record: RecordListModel) {
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
        player?.rate = playbackRate // 배속 유지
        updateNowPlayingTime()
    }

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

    deinit {
        removeTimeObserverIfNeeded()
    }
}
