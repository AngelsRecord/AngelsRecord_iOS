//
//  CarPlayCatalog.swift
//  A'Cast
//
//  Created by 성현 on 9/29/25.
//

import Foundation
import MediaPlayer

final class CarPlayCatalog: NSObject, MPPlayableContentDataSource, MPPlayableContentDelegate {
    static let shared = CarPlayCatalog()

    func start() {
        let mgr = MPPlayableContentManager.shared()
        mgr.dataSource = self
        mgr.delegate = self
    }

    // MARK: - DataSource (최소 구현)
    func numberOfChildItems(at indexPath: IndexPath) -> Int { return 1 }

    func contentItem(at indexPath: IndexPath) -> MPContentItem? {
        let item = MPContentItem(identifier: "demo.item")
        item.title = "Hello CarPlay"
        item.isPlayable = true
        return item
    }

    // MARK: - Delegate (탭 시 재생 트리거)
    func playableContentManager(_ contentManager: MPPlayableContentManager, initiatePlaybackOf contentItem: MPContentItem, completionHandler: @escaping (Error?) -> Void) {
        // 너희 AudioPlayerManager로 재생 시작
        // AudioPlayerManager.shared.play(url: ...)
        completionHandler(nil)
    }
    
    func updateNowPlaying(title: String) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0,
            MPMediaItemPropertyPlaybackDuration: 180,
            MPNowPlayingInfoPropertyPlaybackRate: 0
        ]
    }
}
