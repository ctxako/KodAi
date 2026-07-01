import Foundation
import SwiftData

@Model
final class SessionGroup {
    var id: UUID
    var prompt: String
    var startedAt: Date
    var endedAt: Date?

    init(prompt: String) {
        self.id = UUID()
        self.prompt = prompt
        self.startedAt = Date()
    }
}
