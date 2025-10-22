//
//  AnglesRecord_IOSApp.swift
//  AnglesRecord_IOS
//
//  Created by 성현 on 6/22/25.
//

import SwiftUI
import SwiftData
import UIKit

enum AuthStatus {
    case loading
    case authenticated
    case unauthenticated
}

@main
struct AnglesRecord_IOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var authStatus: AuthStatus = .loading
    @StateObject private var playQueue = PlayQueueManager()
    @StateObject private var recordListViewModel = RecordListViewModel()

    // ⬇️ 추가: 업데이트 게이트 + 얼럿 표시용 플래그
    @StateObject private var updateGate = UpdateGate()
    @State private var showForceUpdateAlert = false
    @Environment(\.scenePhase) private var scenePhase

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([ RecordListModel.self, EpisodeModel.self
                            ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [config])
    }()
    
    init() {
        CarPlayCatalog.shared.start()
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                switch authStatus {
                case .loading:         SplashView()
                case .authenticated:   MainView()
                case .unauthenticated: AuthView()
                }
            }
            .environmentObject(recordListViewModel)
            .environmentObject(playQueue)

            // 시작 시 1회 점검
            .task { await updateGate.check() }

            // 포그라운드 복귀 시 재점검
            .onChange(of: scenePhase) { phase in
                if phase == .active {
                    Task { await updateGate.check() }
                }
            }

            // UpdateGate 신호 → 얼럿 표시
            .onReceive(updateGate.$forceUpdateRequired) { need in
                if need { showForceUpdateAlert = true }
            }

            // 🔔 강제 업데이트 얼럿 (취소 버튼 없음)
            .alert("업데이트가 필요합니다",
                   isPresented: $showForceUpdateAlert) {
                Button("앱스토어 열기") {
                    if let url = URL(string: "itms-apps://itunes.apple.com/app/id/6748930317") {
                        UIApplication.shared.open(url)
                    }
                    // 앱으로 복귀하면 scenePhase == .active에서 다시 check되어
                    // 최신 버전이 아니면 얼럿이 재등장 → 사실상 강제
                }
            } message: {
                Text("안정적인 사용을 위해 최신 버전으로 업데이트 해주세요.")
            }

            .onAppear {
                // (기존 인증 분기 로직)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    authStatus = (KeychainHelper.load("verifiedAccessCode") != nil) ? .authenticated : .unauthenticated
                }
            }
        }
        .modelContainer(sharedModelContainer)
    }


    // MARK: - 유틸

    func checkAuthenticationStatus() -> Bool {
        return KeychainHelper.load("verifiedAccessCode") != nil
    }

    func isDeviceJailbroken() -> Bool {
        let suspiciousPaths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt/"
        ]

        for path in suspiciousPaths {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
        }

        return canOpen(path: "/Applications/Cydia.app")
    }

    func canOpen(path: String) -> Bool {
        let file = fopen(path, "r")
        if file != nil {
            fclose(file)
            return true
        }
        return false
    }
}

