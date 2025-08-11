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
import SwiftData

struct AuthView: View {
    @State private var code: String = ""
    @State private var isAuthenticated = false
    @State private var errorMessage: String?
    @State private var isLoading = false

    @EnvironmentObject var recordListViewModel: RecordListViewModel
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack {
            Text("인증 코드를\n입력해주세요.")
                .font(.system(size: 25, weight: .bold))
                .bold()
                .padding(.trailing, 218)
                .padding(.top, 74)

            SecureLimitedTextField(text: $code)
                .frame(height: 64)
                .padding(.top, 45)
                .onChange(of: code) { _ in
                    errorMessage = nil
                }

            if isLoading {
                Text("인증중 ...")
                    .foregroundColor(.gray)
                    .font(.system(size: 12))
            } else if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.system(size: 12))
            }

            Spacer()

            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { self.endTextEditing() }
            }

            Button(action: {
                verifyCode(code)
            }) {
                Text("시작하기")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 353, height: 64)
                    .foregroundColor(.buttonText)
                    .background(code.isEmpty ? Color("buttonColor") : Color("mainBlue"))
                    .cornerRadius(8)
            }
            .padding(.bottom, 3)
            .disabled(isLoading)
        }
        .onTapGesture {
            self.endTextEditing()
        }
        .fullScreenCover(isPresented: $isAuthenticated) {
            MainView()
        }
    }

    // MARK: - 인증 코드 검증 및 FCM 저장 + 에피소드 fetch
    func verifyCode(_ input: String) {
        isLoading = true
        errorMessage = nil

        let functions = Functions.functions()

        functions.httpsCallable("verifyAccessCode").call(["code": input]) { result, error in
            guard error == nil,
                  let data = result?.data as? [String: Any],
                  let channelId = data["channelId"] as? String else {
                DispatchQueue.main.async {
                    isLoading = false
                    errorMessage = "유효하지 않은 코드입니다."
                }
                return
            }

            print("✅ 인증 성공: \(channelId)")

            // 🔐 Keychain 저장
            let status = KeychainHelper.save("verifiedAccessCode", value: channelId)
            print("🔐 키체인 저장 결과: \(status == errSecSuccess ? "성공" : "실패(\(status))")")

            // ✅ FCM 토큰 저장
            if let fcmToken = Messaging.messaging().fcmToken {
                saveFcmTokenToFirestore(userId: channelId, token: fcmToken)
            } else {
                print("⚠️ FCM 토큰이 아직 준비되지 않았습니다.")
            }

            // ✅ 에피소드 초기 동기화
            recordListViewModel.fetchAndSyncEpisodes(context: modelContext)

            // ✅ 인증 완료 → MainView로 전환
            DispatchQueue.main.async {
                isLoading = false
                isAuthenticated = true
            }
        }
    }

    // MARK: - Firestore에 fcmToken 배열 저장
    func saveFcmTokenToFirestore(userId: String, token: String) {
        let db = Firestore.firestore()
        db.collection("users").document(userId).setData([
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

#Preview {
    // 1. SwiftData Preview용 ModelContainer 생성
    do {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RecordListModel.self, configurations: config)

        // 2. Preview 전용 ViewModel 생성
        let previewViewModel = RecordListViewModel()

        // 3. AuthView에 환경 객체 주입
        return AuthView()
            .environmentObject(previewViewModel)
            .modelContainer(container)
    } catch {
        // 4. 실패 시 기본 View만 반환
        return AuthView()
    }
}
