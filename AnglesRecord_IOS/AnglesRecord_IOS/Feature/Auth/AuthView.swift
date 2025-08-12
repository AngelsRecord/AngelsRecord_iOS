//
//  AuthView.swift
//  AnglesRecord_IOS
//
//  Created by 성현 on 6/22/25.
//

import SwiftUI
import FirebaseAuth
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
            
            VStack {
                SecureLimitedTextField(text: $code)
                    .frame(height: 64)
                    .padding(.top, 45)
                    .onChange(of: code) { _ in
                        errorMessage = nil
                    }
                
                
                
                Spacer()
                
                ZStack {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { self.endTextEditing() }
                }
                
                if isLoading {
                    Text(" ")
                        .foregroundColor(.gray)
                        .font(.system(size: 12))
                } else if let errorMessage = errorMessage {
                    ToastMessage()
                }
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

    /// AuthView 내부에서 호출되는 버튼 액션 함수
    func verifyCode(_ input: String) {
        // UI 상태
        isLoading = true
        errorMessage = nil

        print("👉 [Auth] verify tapped:", input)

        // onCall은 인증 컨텍스트가 있으면 더 안정적이므로 익명 로그인 보장
        let proceed: () -> Void = {
            // 리전은 이 함수 안에서만 명시
            let functions = Functions.functions(region: "asia-northeast3")

            // 1) 인증만 수행 (code만 전송)
            let payload: [String: Any] = [
                "code": input.trimmingCharacters(in: .whitespacesAndNewlines)
            ]
            print("📤 [Auth] calling verifyAccessCode:", payload)

            functions.httpsCallable("verifyAccessCode").call(payload) { result, error in
                if let error = error as NSError? {
                    print("❌ [Auth] verifyAccessCode error:", error.domain, error.code, error.userInfo)
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.errorMessage = "유효하지 않은 코드입니다."
                    }
                    return
                }

                guard let dict = result?.data as? [String: Any],
                      (dict["ok"] as? Bool) == true,
                      let channelId = dict["channelId"] as? String else {
                    print("⚠️ [Auth] invalid verify response:", String(describing: result?.data))
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.errorMessage = "유효하지 않은 코드입니다."
                    }
                    return
                }

                print("✅ [Auth] verify OK, channelId:", channelId)

                // 2) 채널ID 키체인 저장
                let status = KeychainHelper.save("verifiedAccessCode", value: channelId)
                print("🔐 [Auth] keychain save:", status == errSecSuccess ? "success" : "fail(\(status))")

                // 3) 가능한 경우 즉시 디바이스 등록 (토큰이 이미 있다면)
                Messaging.messaging().token { token, _ in
                    if let token = token, !token.isEmpty {
                        let deviceId = DeviceIdManager.getOrCreate()
                        let regData: [String: Any] = [
                            "channelId": channelId,
                            "deviceId": deviceId,
                            "fcmToken": token,
                            "platform": "iOS",
                            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                        ]
                        print("📤 [Auth] calling registerDevice:", regData)

                        functions.httpsCallable("registerDevice").call(regData) { regResult, regError in
                            if let regError = regError {
                                print("❌ [Auth] registerDevice error:", regError.localizedDescription)
                            } else {
                                print("✅ [Auth] registerDevice OK:", regResult?.data as Any)
                            }
                        }
                    } else {
                        print("ℹ️ [Auth] FCM token not ready yet — will register on delegate callback")
                    }
                }

                // 4) 에피소드 초기 동기화 & 화면 전환
                DispatchQueue.main.async {
                    self.recordListViewModel.fetchAndSyncEpisodes(context: self.modelContext)
                    self.isLoading = false
                    self.isAuthenticated = true
                }
            }
        }

        if Auth.auth().currentUser == nil {
            Auth.auth().signInAnonymously { _, err in
                if let err = err {
                    print("❌ [Auth] anonymous signIn:", err.localizedDescription)
                } else {
                    print("✅ [Auth] anonymous signIn success")
                }
                proceed()
            }
        } else {
            proceed()
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
