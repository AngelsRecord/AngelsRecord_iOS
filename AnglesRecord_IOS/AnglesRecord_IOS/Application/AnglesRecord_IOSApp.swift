//
//  AnglesRecord_IOSApp.swift
//  AnglesRecord_IOS
//
//  Created by 성현 on 6/22/25.
//

import SwiftUI
import SwiftData

enum AuthStatus {
    case loading
    case authenticated
    case unauthenticated
}

@main
struct AnglesRecord_IOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var authStatus: AuthStatus = .loading

    /// ✅ EpisodeModel, RecordListModel을 모두 포함한 공유 컨테이너
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            RecordListModel.self,
            EpisodeModel.self  // ✅ 반드시 포함되어야 SwiftData에 저장됨
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    var body: some Scene {
        WindowGroup {
            Group {
                switch authStatus {
                case .loading:
                    SplashView()
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                if let _ = KeychainHelper.load("verifiedAccessCode") {
                                    authStatus = .authenticated
                                } else {
                                    authStatus = .unauthenticated
                                }

                                if isDeviceJailbroken() {
                                    print("🚨 탈옥 감지됨")
                                }
                            }
                        }

                case .authenticated:
                    MainView()

                case .unauthenticated:
                    AuthView()
                }
            }
        }
        .modelContainer(sharedModelContainer)  // ✅ 단일 컨테이너로 앱 전체 연결
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
