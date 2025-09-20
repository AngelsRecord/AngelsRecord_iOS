//
//  AuthView.swift
//  AnglesRecord_IOS
//
//  Created by 성현 on 6/22/25.
//

import SwiftUI
import UIKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import FirebaseMessaging
import SwiftData
import UserNotifications

enum LoadingPhase {
    case none
    case authenticating
    case downloading
}

struct AuthView: View {
    @State private var code: String = ""
    @State private var isAuthenticated = false
    @State private var errorMessage: String?
    @State private var loadingPhase: LoadingPhase = .none
    @State private var showDownloadPrompt = false

    // ✅ 추가: 용량 표시용 상태
    @State private var estimatedDownloadMB: Double?
    @State private var isEstimatingSize = false

    @EnvironmentObject var recordListViewModel: RecordListViewModel
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack {
            Text("인증 코드를\n입력해주세요.")
                .font(.system(size: 24, weight: .bold))
                .bold()
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 24)
                .padding(.top, 74)

            VStack {
                SecureLimitedTextField(text: $code, isDisabled: .constant(loadingPhase != .none))
                    .frame(height: {
                        let screenWidth = UIScreen.main.bounds.width
                        let baselineWidth: CGFloat = 393 // iPhone 15 Pro logical width
                        let scale = max(0.85, min(1.2, screenWidth / baselineWidth))
                        return 64 * scale
                    }())
                    .padding(.top, 45)
                    .onChange(of: code) { _ in errorMessage = nil }

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
                } else if let _ = errorMessage {
                    ToastMessage()
                }
            }
            .padding(.horizontal, 24)

            Button(action: { verifyCode(code) }) {
                // iPhone 15 Pro logical width baseline: 393pt
                // Original button size: 353 x 64
                let screenWidth = UIScreen.main.bounds.width
                let baselineWidth: CGFloat = 393
                let scale = max(0.85, min(1.2, screenWidth / baselineWidth)) // clamp to avoid extremes
                let buttonWidth = 353 * scale
                let buttonHeight = 64 * scale

                if loadingPhase != .none {
                    HStack(spacing: 8 * scale) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text(loadingPhase == .authenticating ? "인증중..." : "에피소드 다운로드 중...")
                            .font(.system(size: 16 * scale, weight: .bold))
                            .foregroundColor(.buttonText)
                    }
                    .frame(width: buttonWidth, height: buttonHeight)
                    .background(Color("buttonColor"))
                    .cornerRadius(8 * scale)
                } else {
                    Text("시작하기")
                        .font(.system(size: 16 * scale, weight: .bold))
                        .frame(width: buttonWidth, height: buttonHeight)
                        .foregroundColor(.buttonText)
                        .background(code.isEmpty ? Color("buttonColor") : Color("mainBlue"))
                        .cornerRadius(8 * scale)
                }
            }
            .padding(.bottom, 3)
            .disabled(loadingPhase != .none || code.isEmpty)
        }
        .onTapGesture { self.endTextEditing() }
        .fullScreenCover(isPresented: $isAuthenticated) { MainView() }
        .alert("전체 에피소드를 다운로드할까요?", isPresented: $showDownloadPrompt) {
            Button("지금 다운로드") {
                beginDownloadAndProceed()
            }
            Button("나중에", role: .cancel) {
                syncMetadataOnlyAndProceed()
            }
        } message: {
            Text(
                """
                와이파이 환경을 권장해요. 나중에도 개별 혹은 전체로 다운로드할 수 있어요.
                
                \(sizeMessageLine())
                """
            )
        }
    }

    // MARK: - 인증 흐름
    func verifyCode(_ input: String) {
        loadingPhase = .authenticating
        errorMessage = nil
        print("👉 [Auth] verify tapped:", input)

        let proceed: () -> Void = {
            let functions = Functions.functions(region: "asia-northeast3")
            let payload: [String: Any] = ["code": input.trimmingCharacters(in: .whitespacesAndNewlines)]
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

                let status = KeychainHelper.save("verifiedAccessCode", value: channelId)
                print("🔐 [Auth] keychain save:", status == errSecSuccess ? "success" : "fail(\(status))")

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

                // ✅ 인증 성공 → 로딩 해제, 용량 계산 시작, 알림 표시
                DispatchQueue.main.async {
                    self.loadingPhase = .none
                    self.prepareDownloadEstimate(andThen: {
                        self.showDownloadPrompt = true
                    })
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

    // MARK: - 다운로드 용량 계산/표시
    // 기존: prepareDownloadEstimate()  → 아래처럼 교체
    private func prepareDownloadEstimate(andThen onReady: @escaping () -> Void) {
        // 이 플래그는 메시지에 안 쓰이게 되었지만, 재진입 방지용으로 그대로 둬도 됨
        isEstimatingSize = true
        estimatedDownloadMB = nil

        recordListViewModel.estimateTotalDownloadBytes(context: modelContext) { totalBytes in
            DispatchQueue.main.async {
                if totalBytes < 0 {
                    self.estimatedDownloadMB = nil   // 계산 불가 → 안내 문구만 표시
                } else {
                    self.estimatedDownloadMB = bytesToMB(totalBytes)
                }
                self.isEstimatingSize = false
                onReady()
            }
        }
    }

    private func sizeMessageLine() -> String {
        if isEstimatingSize { return "예상 다운로드 용량 계산 중…" }
        if let mb = estimatedDownloadMB {
            return "예상 다운로드 용량: \(formatMB(mb)) MB"
        }
        return "예상 다운로드 용량: 계산 불가"
    }

    private func bytesToMB(_ bytes: Int64) -> Double {
        Double(bytes) / 1_048_576.0 // 1024 * 1024
    }

    private func formatMB(_ mb: Double) -> String {
        if mb >= 1024 {
            // 1GB 이상이면 GB로 표기
            let gb = mb / 1024.0
            return String(format: "%.2f (%.2f GB)", mb, gb)
        } else {
            return String(format: "%.1f", mb)
        }
    }

    // MARK: - “지금 다운로드” → 기존 흐름 유지
    private func beginDownloadAndProceed() {
        DispatchQueue.main.async {
            self.loadingPhase = .downloading

            let content = UNMutableNotificationContent()
            content.title = "A'Cast"
            content.body = "에피소드가 백그라운드에서 다운로드 중입니다."
            content.sound = UNNotificationSound.default
            content.categoryIdentifier = "download"

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)

            self.recordListViewModel.fetchAndSyncEpisodes(context: self.modelContext) { _ in
                let completionContent = UNMutableNotificationContent()
                completionContent.title = "A'Cast"
                completionContent.body = "에피소드 다운로드가 끝났습니다."
                completionContent.sound = UNNotificationSound.default
                completionContent.categoryIdentifier = "download"

                let completionTrigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                let completionRequest = UNNotificationRequest(identifier: UUID().uuidString,
                                                              content: completionContent,
                                                              trigger: completionTrigger)
                UNUserNotificationCenter.current().add(completionRequest)

                self.loadingPhase = .none
                self.isAuthenticated = true
            }
        }
    }

    // MARK: - “나중에” → 메타데이터만 동기화 후 메인으로
    private func syncMetadataOnlyAndProceed() {
        recordListViewModel.syncEpisodesMetadataOnly(context: modelContext) { _ in
            DispatchQueue.main.async {
                self.isAuthenticated = true
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

