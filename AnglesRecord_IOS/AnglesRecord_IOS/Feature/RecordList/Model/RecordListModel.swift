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

    init(title: String, artist: String, duration: TimeInterval, fileURL: URL? = nil) {
        self.id = UUID()
        self.title = title
        self.artist = artist
        self.duration = duration
        self.fileURL = fileURL
        self.addedDate = Date()
    }

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.M.d"
        return formatter.string(from: addedDate)
    }
}
