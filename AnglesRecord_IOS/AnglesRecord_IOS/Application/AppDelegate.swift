//
//  AppDelegate.swift
//  AnglesRecord
//
//  Created by 성현 on 6/20/25.
//

import Firebase
import UIKit
import AVFoundation

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()

        // ✅ 오디오 세션 설정
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("❌ AVAudioSession 설정 실패: \(error.localizedDescription)")
        }

        // ✅ 리모트 제어 이벤트 수신 시작
        UIApplication.shared.beginReceivingRemoteControlEvents()

        return true
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .portrait
    }
}
