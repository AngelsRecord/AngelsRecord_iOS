import AVFoundation
import Combine
import Foundation

class AudioPlayerManager: ObservableObject {
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var playbackRate: Float = 1.0

    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 1 // 기본 1로 해서 divide-by-zero 방지

    var currentRecord: RecordListModel?

    // MARK: - Playback

    func play(_ record: RecordListModel) {
        currentRecord = record
        currentTime = 0
        let playerItem = AVPlayerItem(url: record.fileURL!)
        player = AVPlayer(playerItem: playerItem)
        addPeriodicTimeObserver()
        player?.play()
        isPlaying = true

        // duration 설정
        if record.duration > 0 {
            duration = record.duration
        } else {
            duration = CMTimeGetSeconds(playerItem.asset.duration)
        }
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

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self = self else { return }
            self.currentTime = CMTimeGetSeconds(time)
        }
    }

    deinit {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
    }
}
