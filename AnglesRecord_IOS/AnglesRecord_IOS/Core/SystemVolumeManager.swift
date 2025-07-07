//
//  SystemVolumeManager.swift
//  AnglesRecord_IOS
//
//  Created by 성현 on 7/7/25.
//

import MediaPlayer

class SystemVolumeManager {
    private let volumeView = MPVolumeView(frame: .zero)
    private var volumeSlider: UISlider?

    init() {
        if let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider {
            self.volumeSlider = slider
        }
    }

    func setSystemVolume(_ value: Float) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { // 잠깐 delay 필요
            self.volumeSlider?.value = value
        }
    }
}
