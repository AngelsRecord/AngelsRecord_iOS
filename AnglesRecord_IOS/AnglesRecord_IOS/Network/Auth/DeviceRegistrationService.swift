//
//  DeviceRegistrationService.swift
//  AnglesRecord_IOS
//
//  Created by 성현 on 8/12/25.
//

import Foundation
import FirebaseFunctions
import FirebaseMessaging

private let regFunctions = Functions.functions(region: "asia-northeast3")

/// 서버에 디바이스 문서를 upsert. 토큰이 nil이어도 호출 가능(서버가 pending 처리)
func registerDevice(channelId: String, fcmToken: String?, completion: ((Bool) -> Void)? = nil) {
    let deviceId = DeviceIdManager.getOrCreate()
    let data: [String: Any] = [
        "channelId": channelId,
        "deviceId": deviceId,
        "fcmToken": fcmToken ?? "",
        "platform": "iOS",
        "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
    ]
    print("📤 [Reg] registerDevice:", data)

    regFunctions.httpsCallable("registerDevice").call(data) { result, error in
        if let error = error {
            print("❌ [Reg] registerDevice:", error.localizedDescription)
            completion?(false); return
        }
        print("✅ [Reg] registerDevice result:", result?.data as Any)
        completion?(true)
    }
}
