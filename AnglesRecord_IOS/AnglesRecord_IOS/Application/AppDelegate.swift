//
//  AppDelegate.swift
//  AnglesRecord
//
//  Created by 성현 on 6/20/25.
//


import UIKit
import SwiftUI
import AVFoundation
import UserNotifications

import Firebase
import FirebaseFirestore
import FirebaseFunctions
import FirebaseMessaging

final class AppDelegate: NSObject, UIApplicationDelegate {

    // 🔔 앱 포그라운드/탭 시 에피소드 새로고침 트리거
    @AppStorage("shouldFetchNewEpisodes") var shouldFetchNewEpisodes: Bool = false

    // MARK: - App Lifecycle

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

        // ✅ Firebase 초기화
        FirebaseApp.configure()
        
        KeychainHelper.delete("verifiedAccessCode")
        print("🧹 테스트용 Keychain 삭제 완료")

        // ✅ 오디오 세션
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("❌ AVAudioSession 설정 실패:", error.localizedDescription)
        }

        // ✅ 리모트 제어 이벤트
        UIApplication.shared.beginReceivingRemoteControlEvents()

        // ✅ 푸시 권한
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                print("❌ 알림 권한 요청 실패:", error.localizedDescription)
            }
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            } else {
                print("ℹ️ 알림 권한 거부됨")
            }
        }

        // ✅ FCM delegate
        Messaging.messaging().delegate = self

        return true
    }

    // 세로 고정
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .portrait
    }

    // ✅ APNs 토큰 수신 → FCM과 연결
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        print("📲 APNs 토큰 등록 완료")
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ 원격 알림 등록 실패:", error.localizedDescription)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    // 포그라운드 수신 시 배너/사운드/뱃지 표시 + 플래그
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        shouldFetchNewEpisodes = true
        print("🔔 Foreground 알림 수신 → 다운로드 플래그 ON")
        completionHandler([.banner, .sound, .badge])
    }

    // 알림 탭 시 플래그
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        shouldFetchNewEpisodes = true
        print("👉 알림 클릭됨 → 다운로드 플래그 ON")
        completionHandler()
    }
}

// MARK: - MessagingDelegate

extension AppDelegate: MessagingDelegate {

    /// FCM 토큰이 최초 발급/갱신될 때마다 호출됩니다.
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken, !token.isEmpty else { return }
        print("✅ FCM 토큰 수신:", token)

        // 인증된 채널이 있어야 서버에 등록 및 토픽 구독을 진행
        guard let channelId = KeychainHelper.load("verifiedAccessCode"),
              !channelId.isEmpty else {
            print("ℹ️ 미인증 상태 — 토큰 보관만, 나중에 인증되면 등록/구독")
            return
        }

        // 1) 서버에 디바이스 업서트 (registerDevice onCall)
        let functions = Functions.functions(region: "asia-northeast3")
        let deviceId = DeviceIdManager.getOrCreate()
        let data: [String: Any] = [
            "channelId": channelId,
            "deviceId": deviceId,
            "fcmToken": token,
            "platform": "iOS",
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
        ]
        print("📤 registerDevice 호출:", data)

        functions.httpsCallable("registerDevice").call(data) { result, error in
            if let error = error {
                print("❌ registerDevice 실패:", error.localizedDescription)
            } else {
                print("✅ registerDevice 완료:", result?.data as Any)
            }
        }

        // 2) 토픽 구독 (전체 + 채널)
        Messaging.messaging().subscribe(toTopic: "all") { error in
            if let error = error {
                print("❌ 'all' 토픽 구독 실패:", error.localizedDescription)
            } else {
                print("✅ 'all' 토픽 구독 완료")
            }
        }
        Messaging.messaging().subscribe(toTopic: channelId) { error in
            if let error = error {
                print("❌ '\(channelId)' 토픽 구독 실패:", error.localizedDescription)
            } else {
                print("✅ '\(channelId)' 토픽 구독 완료")
            }
        }
    }
}
