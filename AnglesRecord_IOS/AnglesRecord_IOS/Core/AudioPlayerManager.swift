import AVFoundation
import Combine
import Foundation
import MediaPlayer


class AudioPlayerManager: ObservableObject {
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var playbackRate: Float = 1.0

    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 1 // 기본 1로 해서 divide-by-zero 방지

    var currentRecord: RecordListModel?
    
    private func setupNowPlaying(record: RecordListModel) {
        var nowPlayingInfo = [String: Any]()

        nowPlayingInfo[MPMediaItemPropertyTitle] = record.title
        nowPlayingInfo[MPMediaItemPropertyArtist] = "엔젤스"
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        // ✅ 앨범 커버 이미지 추가 (mainimage_yet 사용)
        if let image = UIImage(named: "mainimage_yet") {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    private func updateNowPlayingTime() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
    }

    
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.togglePlayIfNeeded(forcePlay: true)
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.togglePlayIfNeeded(forcePlay: false)
            return .success
        }

        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            self?.skip(seconds: -15)
            return .success
        }

        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [30]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            self?.skip(seconds: 30)
            return .success
        }

        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self.seek(to: positionEvent.positionTime)
            return .success
        }
    }


    private func togglePlayIfNeeded(forcePlay: Bool) {
        if forcePlay {
            if !isPlaying { togglePlayPause() }
        } else {
            if isPlaying { togglePlayPause() }
        }
    }

    // MARK: - Playback

    func play(_ record: RecordListModel) {
        // 1. 기존 옵저버 제거
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }

        // 2. 기존 플레이어 중지
        player?.pause()
        player = nil
        isPlaying = false

        // 3. 시간 초기화 (즉시 반영되도록)
        DispatchQueue.main.async {
            self.currentTime = 0
        }

        // 4. 새로운 플레이어 설정
        currentRecord = record
        let playerItem = AVPlayerItem(url: record.fileURL!)
        player = AVPlayer(playerItem: playerItem)

        // 5. duration 설정
        if record.duration > 0 {
            duration = record.duration
        } else {
            duration = CMTimeGetSeconds(playerItem.asset.duration)
        }

        // 6. 옵저버 + NowPlaying + Remote
        addPeriodicTimeObserver()
        setupNowPlaying(record: record)
        setupRemoteCommandCenter()

        // 7. 재생 시작
        player?.play()
        isPlaying = true
    }


    func togglePlayPause() {
        guard let player = player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
            player.rate = playbackRate
        }
        isPlaying.toggle()
    }

    func stop() {
        player?.pause()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 1
    }

    func skip(seconds: Double) {
        let newTime = currentTime + seconds
        seek(to: newTime)
    }

    func seek(to time: TimeInterval) {
        guard let player = player else { return }
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)

        // 정밀하게 seek + 완료 핸들러로 현재 시간 설정
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            self?.currentTime = time
        }
    }

    func setRate(_ rate: Float) {
        playbackRate = rate
        if let player = player {
            player.rate = rate
            if isPlaying == false {
                player.play()
                isPlaying = true
            }
        }
    }

    // MARK: - Time Observer

    private func addPeriodicTimeObserver() {
        guard let player = player else { return }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self = self else { return }
            self.currentTime = CMTimeGetSeconds(time)
            self.updateNowPlayingTime()
        }
    }

    deinit {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
    }
}
