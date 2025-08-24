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

// MARK: - 중복 업서트/토픽 구독 방지 유틸
final class PushRegistrationManager {
    static let shared = PushRegistrationManager()

    private let lastTokenKey = "lastRegisteredFcmToken"
    private let lastTimeKey  = "lastRegisteredAt"
    private var pendingWork: DispatchWorkItem?

    /// 같은 토큰은 24h 내 재업서트 스킵 (시간 변경 가능)
    func shouldRegister(for token: String, within hours: Double = 24) -> Bool {
        let u = UserDefaults.standard
        let lastToken = u.string(forKey: lastTokenKey)
        let lastTime  = u.object(forKey: lastTimeKey) as? Date

        if lastToken != token { return true }
        if let last = lastTime, Date().timeIntervalSince(last) < hours * 3600 { return false }
        return true
    }

    func markRegistered(token: String) {
        let u = UserDefaults.standard
        u.set(token, forKey: lastTokenKey)
        u.set(Date(), forKey: lastTimeKey)
    }

    /// 짧은 시간 다중 호출 합치기
    func debounce(_ delay: TimeInterval = 0.5, _ action: @escaping () -> Void) {
        pendingWork?.cancel()
        let work = DispatchWorkItem(block: action)
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    var backgroundCompletionHandler: (() -> Void)? = nil

    // 🔔 화면단에서 구독하는 새로고침 트리거
    @AppStorage("shouldFetchNewEpisodes") var shouldFetchNewEpisodes: Bool = false

    // 🧠 권한 팝업/설정 알럿 겹침 방지용
    @AppStorage("hasAskedPushPermission") var hasAskedPushPermission: Bool = false
    fileprivate var isRequestingPushAuth = false
    fileprivate var lastDeniedAlertShownAt: Date?

    // 🔄 토픽 중복 구독 방지
    private var didSubscribeAllTopic = false
    private var subscribedChannelIds = Set<String>()

    // 🕒 로그 키
    fileprivate let lastPushAtKey   = "lastPushReceivedAt"     // 마지막 푸시 수신 시각
    fileprivate let lastRefreshAtKey = "lastEpisodesRefreshAt" // ViewModel에서 저장 완료 시 기록

    // MARK: - App Lifecycle

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

        // ✅ Firebase
        FirebaseApp.configure()

        // ✅ 오디오 세션
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("❌ AVAudioSession 설정 실패:", error.localizedDescription)
        }

        // ✅ 리모트 제어 이벤트
        UIApplication.shared.beginReceivingRemoteControlEvents()

        // ✅ 델리게이트
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self

        // 🔹 알림 탭으로 “런치된” 경우도 즉시 플래그 ON
        if let _ = launchOptions?[.remoteNotification] {
            print("👉 알림으로 앱이 런치됨 → 다운로드 플래그 ON")
            shouldFetchNewEpisodes = true
            UserDefaults.standard.set(Date(), forKey: lastPushAtKey)
        }

        // ✅ 포그라운드 복귀 시 상태 점검 + 놓친 알림 보정
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if self.isRequestingPushAuth { return }

            // 🔁 잠금화면 탭 없이 아이콘으로 들어온 시나리오 보강
            self.reconcileNotificationsOnForeground()

            // 🕒 마지막 푸시 후 미갱신이면 플래그 ON
            let lastPush = UserDefaults.standard.object(forKey: self.lastPushAtKey) as? Date
            let lastRefresh = UserDefaults.standard.object(forKey: self.lastRefreshAtKey) as? Date
            if let p = lastPush {
                if lastRefresh == nil || p > lastRefresh! {
                    print("🔁 포그라운드 복귀: 푸시 이후 미갱신 → 플래그 ON")
                    self.shouldFetchNewEpisodes = true
                }
            }

            // 권한/등록 플로우 재확인
            self.checkAndSetupPushFlow()
        }

        // ✅ 최초 진입 시 권한/등록 플로우
        checkAndSetupPushFlow()

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
        // FCM 토큰 콜백 유도(선택)
        Messaging.messaging().token { _, _ in }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ 원격 알림 등록 실패:", error.localizedDescription)
    }
}

// MARK: - 포그라운드 복귀 시 알림/배지 보정
extension AppDelegate {
    /// 앱이 살아있는 상태에서 알림이 오고, 사용자가 아이콘으로 진입한 경우를 보정
    fileprivate func reconcileNotificationsOnForeground() {
        // ① 배지 기반 빠른 경로
        let badge = UIApplication.shared.applicationIconBadgeNumber
        if badge > 0 {
            print("🔁 배지(\(badge)) 감지 → 새로고침 플래그 ON")
            shouldFetchNewEpisodes = true
            UIApplication.shared.applicationIconBadgeNumber = 0
            UserDefaults.standard.set(Date(), forKey: lastPushAtKey)
            return
        }

        // ② Notification Center에 남아있는 전달된 알림 확인
        UNUserNotificationCenter.current().getDeliveredNotifications { [weak self] delivered in
            guard let self = self else { return }
            if !delivered.isEmpty {
                print("🔁 전달된 알림 \(delivered.count)건 감지 → 새로고침 플래그 ON")
                self.shouldFetchNewEpisodes = true
                // 원하면 유지 가능. 여기선 정리
                UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                UIApplication.shared.applicationIconBadgeNumber = 0
                UserDefaults.standard.set(Date(), forKey: self.lastPushAtKey)
            }
        }
    }
}

// MARK: - Push Flow Helpers
extension AppDelegate {

    /// 권한 상태 확인 후 적절한 액션 수행
    fileprivate func checkAndSetupPushFlow(after delay: TimeInterval = 0) {
        let work = {
            UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
                print("ℹ️ 알림 권한 상태 확인: \(settings.authorizationStatus.rawValue)")  // 로그 추가: 권한 상태 (0: notDetermined, 1: denied, 2: authorized)
                guard let self = self else { return }
                switch settings.authorizationStatus {
                case .notDetermined:
                    self.requestNotificationAuthorization()
                case .denied:
                    // 최소 한 번 직접 요청해본 뒤에만 설정 알럿 유도
                    guard self.hasAskedPushPermission else { return }
                    if let last = self.lastDeniedAlertShownAt,
                       Date().timeIntervalSince(last) < 3 { return } // 3초 쿨다운
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.presentPushDeniedAlert()
                        self.lastDeniedAlertShownAt = Date()
                    }
                case .authorized, .provisional, .ephemeral:
                    DispatchQueue.main.async {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                    // 업서트는 MessagingDelegate에서만 수행
                    Messaging.messaging().token { _, _ in }
                @unknown default:
                    DispatchQueue.main.async {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                    Messaging.messaging().token { _, _ in }
                }
            }
        }
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        } else {
            work()
        }
    }

    /// 실제 권한 요청 (겹침 방지 플래그/딜레이 포함)
    fileprivate func requestNotificationAuthorization() {
        guard !isRequestingPushAuth else { return }
        isRequestingPushAuth = true

        let options: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(options: options) { [weak self] granted, error in
            guard let self = self else { return }
            self.hasAskedPushPermission = true
            self.isRequestingPushAuth = false

            if let error = error {
                print("❌ 알림 권한 요청 실패:", error.localizedDescription)
            }

            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                // 시스템 팝업 직후 상태 안정화 후 재체크
                self.checkAndSetupPushFlow(after: 0.8)
            } else {
                self.checkAndSetupPushFlow(after: 1.0)
            }
        }
    }

    /// 거부 상태에서 설정 이동 유도
    fileprivate func presentPushDeniedAlert() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else { return }

        let alert = UIAlertController(
            title: "알림이 비활성화되어 있습니다",
            message: "새 에피소드 알림을 받으려면 설정에서 알림을 허용해주세요.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "나중에", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "설정으로 이동", style: .default, handler: { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }))
        root.present(alert, animated: true, completion: nil)
    }

    /// 채널 인증된 상태면 registerDevice(onCall) 업서트 + 토픽 구독(중복 방지)
    fileprivate func registerDeviceIfAuthenticated(with fcmToken: String) {
        guard let channelId = KeychainHelper.load("verifiedAccessCode"),
              !channelId.isEmpty else {
            print("ℹ️ 미인증 상태 — 인증 후 업서트 예정")
            return
        }

        let functions = Functions.functions(region: "asia-northeast3")
        let deviceId = DeviceIdManager.getOrCreate()
        let data: [String: Any] = [
            "channelId": channelId,
            "deviceId": deviceId,
            "fcmToken": fcmToken,
            "platform": "iOS",
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
        ]
        print("📤 registerDevice 호출:", data)

        functions.httpsCallable("registerDevice").call(data) { [weak self] result, error in
            guard let self = self else { return }
            if let error = error {
                print("❌ registerDevice 실패:", error.localizedDescription)
                return
            }
            print("✅ registerDevice 완료:", result?.data as Any)

            // ✅ 업서트 성공 기록
            PushRegistrationManager.shared.markRegistered(token: fcmToken)

            // ✅ 토픽 구독(중복 방지)
            if !self.didSubscribeAllTopic {
                self.didSubscribeAllTopic = true
                Messaging.messaging().subscribe(toTopic: "all") { error in
                    if let error = error { print("❌ 'all' 토픽 구독 실패:", error.localizedDescription) }
                    else { print("✅ 'all' 토픽 구독 완료") }
                }
            }
            if !self.subscribedChannelIds.contains(channelId) {
                self.subscribedChannelIds.insert(channelId)
                Messaging.messaging().subscribe(toTopic: channelId) { error in
                    if let error = error { print("❌ '\(channelId)' 토픽 구독 실패:", error.localizedDescription) }
                    else { print("✅ '\(channelId)' 토픽 구독 완료") }
                }
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension AppDelegate: UNUserNotificationCenterDelegate {
    // 포그라운드 수신 시 배너/사운드/뱃지 표시 + 플래그
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // 다운로드 관련 알림인지 체크 (categoryIdentifier로 구분)
        if notification.request.content.categoryIdentifier != "download" {
            shouldFetchNewEpisodes = true
            UserDefaults.standard.set(Date(), forKey: lastPushAtKey)
            print("🔔 Foreground 알림 수신 → 다운로드 플래그 ON")
        } else {
            print("🔔 Foreground 다운로드 알림 수신 → 플래그 스킵")
        }
        completionHandler([.banner, .sound, .badge])
    }

    // 알림 탭 시 플래그
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.content.categoryIdentifier != "download" {
            shouldFetchNewEpisodes = true
            UserDefaults.standard.set(Date(), forKey: lastPushAtKey)
            print("👉 알림 클릭됨 → 다운로드 플래그 ON")
        } else {
            print("👉 다운로드 알림 클릭됨 → 플래그 스킵")
        }
        completionHandler()
    }
}

// MARK: - MessagingDelegate (업서트 단일 진입점)
extension AppDelegate: MessagingDelegate {
    /// FCM 토큰 최초 발급/갱신 시 호출(여기서만 업서트)
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken, !token.isEmpty else { return }
        print("✅ FCM 토큰 수신:", token)

        // 동일 토큰 24h 내 재업서트 스킵
        if !PushRegistrationManager.shared.shouldRegister(for: token, within: 24) {
            print("↪️ 동일 토큰(24h 내) — 업서트 스킵")
            return
        }

        // 짧은 시간 다중 콜 디바운스
        PushRegistrationManager.shared.debounce(0.5) { [weak self] in
            self?.registerDeviceIfAuthenticated(with: token)
        }
    }
}

// MARK: - UIWindowScene 헬퍼
private extension UIWindowScene {
    var keyWindow: UIWindow? {
        return self.windows.first(where: { $0.isKeyWindow })
    }
}

// MARK: - Local Notification Helpers
extension AppDelegate {
    func scheduleLocalNotification(title: String, body: String, delay: TimeInterval = 0, category: String = "") {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default
        content.categoryIdentifier = category  // 카테고리 설정
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(delay, 1), repeats: false)  // 최소 1초 딜레이
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ 로컬 알림 스케줄 실패: \(error.localizedDescription)")
            } else {
                print("✅ 로컬 알림 스케줄 완료: \(title) - \(body)")
            }
        }
    }
}

// MARK: - Background Download Handler
extension AppDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        print("ℹ️ 백그라운드 URLSession 이벤트 처리: \(identifier)")
        if identifier == "com.anglesrecord.backgrounddownload" {
            backgroundCompletionHandler = completionHandler
        }
    }
}
