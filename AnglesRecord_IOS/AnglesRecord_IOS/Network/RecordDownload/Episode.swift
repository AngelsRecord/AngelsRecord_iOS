//
//  Episode.swift
//  AnglesRecord_IOS
//
//  Created by 성현 on 6/24/25.
//

import Foundation
import FirebaseFirestore

struct Episode: Identifiable, Codable {
    var id: String { _id ?? UUID().uuidString }
    @DocumentID private var _id: String?

    let title: String
    let description: String
    let uploadedAt: Date
    let fileName: String  // 실제 Firestore 필드는 "audioFilename"

    enum CodingKeys: String, CodingKey {
        case _id = "id"
        case title
        case description
        case uploadedAt
        case fileName = "audioFilename"  // 🔥 여기 수정
    }

    var uploadDate: Date {
        uploadedAt
    }
}

