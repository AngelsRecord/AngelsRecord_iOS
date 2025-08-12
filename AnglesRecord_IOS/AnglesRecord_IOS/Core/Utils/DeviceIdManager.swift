//
//  DeviceIdManager.swift
//  AnglesRecord_IOS
//
//  Created by 성현 on 8/12/25.
//

import Foundation

enum DeviceIdManager {
    private static let key = "deviceId"

    static func getOrCreate() -> String {
        // 🔹 Keychain에서 문자열로 로드
        if let saved = KeychainHelper.load(key), !saved.isEmpty {
            return saved
        }
        // 🔹 새로 생성해서 문자열로 저장
        let newId = UUID().uuidString
        KeychainHelper.save(key, value: newId)   // <-- value: String
        return newId
    }
}
