import Foundation

public nonisolated struct KodaiLog: Sendable {
    public let category: String

    public nonisolated init(category: String) {
        self.category = category
    }

    public nonisolated func event(_ message: String, since startDate: Date? = nil) {
        let elapsed = startDate.map { String(format: "+%.3fs", Date().timeIntervalSince($0)) } ?? "+-.---s"
        print("[\(category)] \(elapsed) \(message)")
    }
}
