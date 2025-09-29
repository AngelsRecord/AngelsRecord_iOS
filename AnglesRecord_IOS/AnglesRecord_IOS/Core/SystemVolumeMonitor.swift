//
//  SystemVolumeMonitor.swift
//  A'Cast
//
//  Created by 성현 on 9/23/25.
//

import AVFoundation
import MediaPlayer
import Combine
import UIKit

final class SystemVolumeMonitor {
    static let shared = SystemVolumeMonitor()

    private var cancellable: AnyCancellable?
    private let session = AVAudioSession.sharedInstance()
    private let mpView = MPVolumeView(frame: .zero) // 화면에 안 보이게 붙일 용도

    // 외부 구독용 Subject
    let subject = CurrentValueSubject<Float, Never>(AVAudioSession.sharedInstance().outputVolume)

    private init() {}

    func start() {
        // 이미 시작했으면 다시 붙이지 않음
        if cancellable != nil { return }

        // MPVolumeView를 뷰 계층에 한 번 붙여 KVO 안정화
        DispatchQueue.main.async {
            // keyWindow가 없을 수도 있으니 가장 앞의 UIWindow에 붙임
            if let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow }) {
                self.mpView.isHidden = true
                self.mpView.alpha = 0.01
                if self.mpView.superview == nil {
                    window.addSubview(self.mpView)
                }
            }
        }

        // KVO 퍼블리셔를 강하게 보관
        cancellable = session.publisher(for: \.outputVolume)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in
                self?.subject.send(v)
            }
    }

    func stop() {
        cancellable?.cancel()
        cancellable = nil
    }
}
