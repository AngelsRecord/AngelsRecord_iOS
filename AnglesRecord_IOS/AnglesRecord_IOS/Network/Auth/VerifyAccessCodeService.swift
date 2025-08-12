//
//  VerifyAccessCodeService.swift
//  AnglesRecord_IOS
//
//  Created by 성현 on 8/12/25.
//

import Foundation
import FirebaseAuth
import FirebaseFunctions

// 이 파일 안에서만 리전 지정
private let functions = Functions.functions(region: "asia-northeast3")

/// accessCodes 검사 → 성공 시 channelId 반환
func verifyAccessCode(_ input: String, completion: @escaping (String?) -> Void) {
    print("👉 [Auth] verify tapped:", input)

    let go: () -> Void = {
        let data: [String: Any] = [
            "code": input.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        functions.httpsCallable("verifyAccessCode").call(data) { result, error in
            if let error = error as NSError? {
                print("❌ [Auth] onCall error:", error.domain, error.code, error.userInfo)
                completion(nil); return
            }
            guard let dict = result?.data as? [String: Any],
                  (dict["ok"] as? Bool) == true,
                  let channelId = dict["channelId"] as? String else {
                print("⚠️ [Auth] invalid response:", String(describing: result?.data))
                completion(nil); return
            }
            print("✅ [Auth] ok, channelId:", channelId)
            completion(channelId)
        }
    }

    if Auth.auth().currentUser == nil {
        Auth.auth().signInAnonymously { _, _ in go() }
    } else { go() }
}
