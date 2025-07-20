//
//  AppDelegate.swift
//  AnglesRecord
//
//  Created by 성현 on 6/20/25.
//

import UIKit
import Firebase
import AVFoundation
import UserNotifications
import FirebaseMessaging

class AppDelegate: NSObject, UIApplicationDelegate {
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Firebase 초기화
        FirebaseApp.configure()
        
        KeychainHelper.delete("verifiedAccessCode")
        print("🧹 테스트용 Keychain 삭제 완료")
        
        // ✅ 오디오 세션 설정
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("❌ AVAudioSession 설정 실패: \(error.localizedDescription)")
        }

        // ✅ 리모트 제어 이벤트 수신 시작
        UIApplication.shared.beginReceivingRemoteControlEvents()
        
        // ✅ Push Notification 권한 요청
        UNUserNotificationCenter.current().delegate = self
        
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(options: authOptions) { granted, error in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }

        // ✅ FCM delegate 설정
        Messaging.messaging().delegate = self

        return true
    }
    
    // ✅ 회전 방향 설정 (세로 고정)
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .portrait
    }

    // ✅ APNs 토큰을 FCM에 등록
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        print("📲 APNs 토큰 등록 완료")
    }

    // ✅ 알림 등록 실패 처리
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ 원격 알림 등록 실패: \(error.localizedDescription)")
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    // ✅ 앱이 foreground일 때도 알림 배너 표시
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
}

// MARK: - MessagingDelegate

extension AppDelegate: MessagingDelegate {
    // ✅ FCM 토큰 수신 (초기 및 갱신 시 호출됨)
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken = fcmToken else { return }
        print("✅ FCM 토큰 수신: \(fcmToken)")

        // 이 시점에서 Firestore 저장 또는 서버 전송 가능
        // 예: NotificationCenter.post로 ViewModel에게 전달해도 됨
    }
}
