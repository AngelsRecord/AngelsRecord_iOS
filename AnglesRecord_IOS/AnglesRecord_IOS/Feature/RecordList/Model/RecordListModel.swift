import Foundation
import SwiftData

@Model
final class RecordListModel {
    var id: UUID
    var title: String
    var artist: String
    var duration: TimeInterval
    var fileURL: URL?
    var addedDate: Date
    var uploadedAt: Date?

    init(title: String, artist: String, duration: TimeInterval, fileURL: URL? = nil, uploadedAt: Date? = nil) {
        self.id = UUID()
        self.title = title
        self.artist = artist
        self.duration = duration
        self.fileURL = fileURL
        self.addedDate = Date()
        self.uploadedAt = uploadedAt
    }

    private var displayDate: Date { uploadedAt ?? addedDate }
    
    private enum DateCache {
        static let displayFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "M월 d일"
            f.locale = Locale(identifier: "ko_KR")
            return f
        }()
    }

    var formattedDate: String {
        DateCache.displayFormatter.string(from: displayDate)
    }

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
