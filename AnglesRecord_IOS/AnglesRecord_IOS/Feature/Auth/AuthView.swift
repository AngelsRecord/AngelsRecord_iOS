//
//  AuthView.swift
//  AnglesRecord_IOS
//
//  Created by 성현 on 6/22/25.
//

import SwiftUI
import UIKit  // UIApplication.shared.delegate 사용을 위해 추가 (필요 없어짐, 하지만 유지)
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import FirebaseMessaging
import SwiftData

// 로딩 단계를 위한 enum 추가
enum LoadingPhase {
    case none
    case authenticating
    case downloading
}

struct AuthView: View {
    @State private var code: String = ""
    @State private var isAuthenticated = false
    @State private var errorMessage: String?
    @State private var loadingPhase: LoadingPhase = .none  // 로딩 단계 상태 변수 추가 (기존 isLoading 대신 사용)

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
                
                if loadingPhase != .none {
                    Text(" ")
                        .foregroundColor(.gray)
                        .font(.system(size: 12))
                } else if let errorMessage = errorMessage {
                    ToastMessage()
                }
            }
            // 수정된 버튼 부분: 로딩 단계에 따라 내용 동적으로 변경
            Button(action: {
                verifyCode(code)
            }) {
                if loadingPhase != .none {
                    HStack(spacing: 8) {  // 로딩 인디케이터와 텍스트를 가로로 배치
                        ProgressView()  // 동그란 로딩 스피너
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))  // 색상 맞춤 (흰색으로)
                        Text(loadingPhase == .authenticating ? "인증중..." : "음원 다운로드 중...")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.buttonText)
                    }
                    .frame(width: 353, height: 64)
                    .background(Color("buttonColor"))  // 로딩 중 비활성화 상태이므로 회색으로
                    .cornerRadius(8)
                } else {
                    Text("시작하기")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 353, height: 64)
                        .foregroundColor(.buttonText)
                        .background(code.isEmpty ? Color("buttonColor") : Color("mainBlue"))
                        .cornerRadius(8)
                }
            }
            .padding(.bottom, 3)
            .disabled(loadingPhase != .none || code.isEmpty)  // 로딩 중이거나 코드 비어 있으면 비활성화
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
        // UI 상태: 인증 단계 시작
        loadingPhase = .authenticating
        errorMessage = nil

        print("👉 [Auth] verify tapped:", input)

        // onCall은 인증 컨텍스트가 있으면 더 안정적이므로 익명 로그인 보장
        let proceed: () -> Void = {
            // 리전은 이 함수 안에서만 명시
            let functions = Functions.functions(region: "asia-northeast3")
            print("ℹ️ [Auth] Functions 초기화 완료: region=asia-northeast3")  // 로그 추가: Functions 초기화

            // 1) 인증만 수행 (code만 전송)
            let payload: [String: Any] = [
                "code": input.trimmingCharacters(in: .whitespacesAndNewlines)
            ]
            print("📤 [Auth] calling verifyAccessCode:", payload)

            functions.httpsCallable("verifyAccessCode").call(payload) { result, error in
                if let error = error as NSError? {
                    print("❌ [Auth] verifyAccessCode error:", error.domain, error.code, error.userInfo)
                    DispatchQueue.main.async {
                        self.loadingPhase = .none
                        self.errorMessage = "유효하지 않은 코드입니다."
                    }
                    return
                }

                guard let dict = result?.data as? [String: Any],
                      (dict["ok"] as? Bool) == true,
                      let channelId = dict["channelId"] as? String else {
                    print("⚠️ [Auth] invalid verify response:", String(describing: result?.data))
                    DispatchQueue.main.async {
                        self.loadingPhase = .none
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

                // 4) 에피소드 초기 동기화 & 화면 전환: 다운로드 단계로 전환
                DispatchQueue.main.async {
                    self.loadingPhase = .downloading  // 인증 성공 후 다운로드 단계로 변경
                    
                    // 직접 로컬 알림 스케줄 (AppDelegate 없이 UNUserNotificationCenter 사용)
                    let content = UNMutableNotificationContent()
                    content.title = "다운로드 진행 중"
                    content.body = "음원이 다운로드 중입니다."
                    content.sound = UNNotificationSound.default
                    content.categoryIdentifier = "download"  // 플래그 스킵을 위한 카테고리
                    
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)  // 1초 딜레이
                    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
                    
                    UNUserNotificationCenter.current().add(request) { error in
                        if let error = error {
                            print("❌ 로컬 알림 스케줄 실패: \(error.localizedDescription)")
                        } else {
                            print("✅ 로컬 알림 스케줄 완료: 다운로드 진행 중")
                        }
                    }
                    
                    self.recordListViewModel.fetchAndSyncEpisodes(context: self.modelContext) { ok in
                        self.loadingPhase = .none
                        self.isAuthenticated = true
                    }
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
