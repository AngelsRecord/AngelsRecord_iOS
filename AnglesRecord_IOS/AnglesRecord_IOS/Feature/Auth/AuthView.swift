//
//  AuthView.swift
//  AnglesRecord_IOS
//
//  Created by 성현 on 6/22/25.
//

import SwiftUI
import FirebaseFirestore
import FirebaseFunctions
import FirebaseMessaging

struct AuthView: View {
    @State private var code: String = ""
    @State private var isAuthenticated = false
    @State private var errorMessage: String?

    var body: some View {
        VStack {
            Text("인증 코드를\n입력해주세요.")
                .font(.title)
                .bold()
                .padding(.trailing, 220)
                .padding(.top, 73)

            SecureLimitedTextField(text: $code)
                .frame(height: 64)
                .padding(.top, 54)

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
            }

            Spacer()
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { self.endTextEditing() }
            }

            Button("시작하기") {
                verifyCode(code)
            }
            .frame(width: 353, height: 64)
            .background((code.isEmpty ? Color("subText") : Color("mainBlue")))
            .foregroundColor(.buttonText)
            .cornerRadius(8)
            .padding(.bottom, 20)
        }
        .onTapGesture {
            self.endTextEditing()
        }
        .fullScreenCover(isPresented: $isAuthenticated) {
            MainView()
        }
    }

    // MARK: - 인증 코드 검증
    func verifyCode(_ input: String) {
        let functions = Functions.functions()

        functions.httpsCallable("verifyAccessCode").call(["code": input]) { result, error in
            if let error = error {
                print("❌ 인증 실패: \(error.localizedDescription)")
                errorMessage = "잘못된 코드입니다."
            } else if let data = result?.data as? [String: Any],
                      let channelId = data["channelId"] as? String {
                print("✅ 인증 성공: \(channelId)")
                isAuthenticated = true

                // 🔐 Keychain 저장
                let status = KeychainHelper.save("verifiedAccessCode", value: channelId)
                print("🔐 키체인 저장 결과: \(status == errSecSuccess ? "성공" : "실패(\(status))")")

                // 🔁 FCM 토큰 저장
                if let fcmToken = Messaging.messaging().fcmToken {
                    saveFcmTokenToFirestore(userId: channelId, token: fcmToken)
                } else {
                    // 아직 토큰이 nil인 경우, 토큰 갱신을 기다렸다가 NotificationCenter 등으로 처리 가능
                    print("⚠️ FCM 토큰이 아직 준비되지 않았습니다.")
                }

            } else {
                errorMessage = "응답 형식 오류"
            }
        }
    }

    func saveFcmTokenToFirestore(userId: String, token: String) {
        let db = Firestore.firestore()
        db.collection("users").document("channelA").setData([
            "fcmTokens": FieldValue.arrayUnion([token])
        ], merge: true) { error in
            if let error = error {
                print("❌ Firestore 저장 실패: \(error.localizedDescription)")
            } else {
                print("✅ FCM 토큰 Firestore 저장 완료")
            }
        }
    }
}

// MARK: - 키보드 내리기 유틸

extension View {
    func endTextEditing() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}
