//// VerifyAccessCodeService.swift
//import Foundation
//import FirebaseAuth
//import FirebaseFunctions
//import FirebaseMessaging
//
///// 이 파일 안에서만 functions 인스턴스를 유지 (전역 유틸 없이 지역 지정)
//private let functions = Functions.functions(region: "asia-northeast3")
//
///// Firestore accessCodes 문서 ID
//private let ACCESS_CODE_ID = "SessionA" // 필요 시 변경
//
///// 서버 onCall(verifyAccessCode)을 호출해 인증 수행.
///// 성공 시 channelId를 completion으로 전달, 실패 시 nil.
//func verifyAccessCode(
//    _ input: String,
//    completion: @escaping (String?) -> Void
//) {
//    // 버튼이 실제 눌렸는지 확인용 로그
//    print("👉 [Auth] verifyCode tapped:", input)
//
//    // 1) 익명 로그인 보장 (onCall 권장)
//    let continueCall: () -> Void = {
//        let deviceId = DeviceIdManager.getOrCreate()
//        let token = Messaging.messaging().fcmToken
//
//        // 2) 서버 스펙에 맞게 페이로드 구성
//        let data: [String: Any?] = [
//            "codeId": ACCESS_CODE_ID,
//            "code": input.trimmingCharacters(in: .whitespacesAndNewlines),
//            "deviceId": deviceId,
//            "fcmToken": token,
//            "platform": "iOS",
//            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
//        ]
//        print("📤 [Auth] onCall payload:", data)
//
//        // 3) onCall 호출
//        functions.httpsCallable("verifyAccessCode").call(data) { result, error in
//            if let error = error as NSError? {
//                // FirebaseFunctions는 HttpsError를 NSError로 전달
//                // userInfo에 details, underlying data가 들어올 수 있음
//                print("❌ [Auth] onCall error:", error.domain, error.code, error.userInfo)
//                DispatchQueue.main.async { completion(nil) }
//                return
//            }
//
//            guard let dict = result?.data as? [String: Any] else {
//                print("⚠️ [Auth] onCall response not a dict:", String(describing: result?.data))
//                DispatchQueue.main.async { completion(nil) }
//                return
//            }
//            print("✅ [Auth] onCall response:", dict)
//
//            // 서버는 { ok: Bool, channelId?: String } 형태로 응답
//            let ok = (dict["ok"] as? Bool) ?? false
//            let channelId = dict["channelId"] as? String
//
//            DispatchQueue.main.async {
//                completion(ok ? channelId : nil)
//            }
//        }
//    }
//
//    if Auth.auth().currentUser == nil {
//        Auth.auth().signInAnonymously { _, err in
//            if let err = err {
//                print("❌ [Auth] anonymous signIn:", err.localizedDescription)
//            } else {
//                print("✅ [Auth] anonymous signIn success")
//            }
//            continueCall()
//        }
//    } else {
//        continueCall()
//    }
//}
