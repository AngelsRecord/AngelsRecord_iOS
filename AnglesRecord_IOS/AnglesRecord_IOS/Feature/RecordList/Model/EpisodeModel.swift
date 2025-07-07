import Foundation
import SwiftData

@Model
final class EpisodeModel: Identifiable {
    @Attribute(.unique) var id: String
    var title: String
    var desc: String
    var uploadedAt: Date
    var fileName: String

    init(id: String, title: String, desc: String, uploadedAt: Date, fileName: String) {
        self.id = id
        self.title = title
        self.desc = desc
        self.uploadedAt = uploadedAt
        self.fileName = fileName
    }
}
