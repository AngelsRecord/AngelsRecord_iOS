//
//  UpdateGate.swift
//  A'Cast
//
//  Created by 성현 on 9/14/25.
//

import Foundation
import Combine
import FirebaseRemoteConfig

final class UpdateGate: ObservableObject {
    @Published var forceUpdateRequired = false
    // (옵션) 디버깅용으로 내려받은 최소버전 확인하고 싶으면 활용
    @Published var minSupportedVersion: String?

    private var lastCheckedAt: Date?
    private let rc = RemoteConfig.remoteConfig()

    // 🔢 App Store numeric app ID (Bundle ID 안 씀)
    private let appStoreID = "6748930317"

    init() {
        // 개발 중엔 즉시 반영, 운영은 기본(12h 캐시) 사용
        #if DEBUG
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 0
        rc.configSettings = settings
        #endif

        // 네트워크 실패 대비 기본값
        rc.setDefaults([
            "min_supported_version": "1.0.0" as NSObject
        ])
    }

    /// 원격 최소 버전 확인 → 현재 버전과 비교 → 필요 시 강제 업데이트 플래그 ON
    func check() async {
        // 30분 이내 재호출 방지 (쓰로틀)
        if let last = lastCheckedAt, Date().timeIntervalSince(last) < 30 * 60 { return }
        lastCheckedAt = Date()

        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

        // await를 ?? 에서 못 쓰므로 순차 분기
        var minRequired: String? = await fetchMinSupportedVersion()
        if minRequired == nil {
            minRequired = await fetchAppStoreLatest() // iTunes Lookup fallback
        }

        if let min = minRequired {
            await MainActor.run {
                self.minSupportedVersion = min
                if self.isVersion(current, olderThan: min) {
                    self.forceUpdateRequired = true
                }
            }
        }
    }

    // MARK: - Data Sources

    /// Firebase Remote Config: key = "min_supported_version"
    private func fetchMinSupportedVersion() async -> String? {
        do {
            try await rc.fetch(withExpirationDuration: 0)
            _ = try await rc.activate()
            let v = rc.configValue(forKey: "min_supported_version").stringValue ?? ""
            return v.isEmpty ? nil : v
        } catch {
            return nil
        }
    }

    /// iTunes Lookup (앱스토어 공개 상태여야 동작 안정적)
    private func fetchAppStoreLatest() async -> String? {
        guard let url = URL(string: "https://itunes.apple.com/lookup?id=\(appStoreID)&country=kr") else {
            return nil
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let results = json["results"] as? [[String: Any]],
                let first = results.first,
                let version = first["version"] as? String
            else { return nil }
            return version
        } catch {
            return nil
        }
    }

    // MARK: - Semver compare (1.2.10 < 1.3 correctly)
    private func isVersion(_ v1: String, olderThan v2: String) -> Bool {
        func parts(_ v: String) -> [Int] { v.split(separator: ".").map { Int($0) ?? 0 } }
        let a = parts(v1), b = parts(v2)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x < y }
        }
        return false
    }
}
