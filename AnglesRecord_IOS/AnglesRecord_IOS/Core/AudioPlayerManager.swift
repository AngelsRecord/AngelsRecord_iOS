import Foundation
import AVFoundation
import Combine

@MainActor
class AudioPlayerManager: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var currentRecord: RecordListModel?
    
    private var player: AVAudioPlayer?
    private var timer: Timer?
    
    init() {
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    func play(_ record: RecordListModel) {
        guard let fileURL = record.fileURL else { return }
        
        do {
            player = try AVAudioPlayer(contentsOf: fileURL)
            player?.prepareToPlay()
            player?.play()
            
            currentRecord = record
            isPlaying = true
            duration = player?.duration ?? 0
            
            startTimer()
        } catch {
            print("Failed to play audio: \(error)")
        }
    }
    
    func togglePlayPause() {
        guard let player = player else { return }
        
        if player.isPlaying {
            player.pause()
            isPlaying = false
            stopTimer()
        } else {
            player.play()
            isPlaying = true
            startTimer()
        }
    }
    
    func skip(seconds: TimeInterval) {
        guard let player = player else { return }
        
        let newTime = player.currentTime + seconds
        if newTime >= 0 && newTime <= player.duration {
            player.currentTime = newTime
            currentTime = newTime
        }
    }
    
    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        currentRecord = nil
        stopTimer()
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                self.currentTime = self.player?.currentTime ?? 0
                
                if let player = self.player, !player.isPlaying && self.currentTime >= self.duration - 0.1 {
                    self.stop()
                }
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
} 
