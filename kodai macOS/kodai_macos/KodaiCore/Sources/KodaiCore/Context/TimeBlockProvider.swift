import Foundation

public struct TimeBlockProvider: ContextBlockProvider, Sendable {
    public init() {}

    public func provide(for chat: KodaiChatSession, query: String) -> ContextBlock? {
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a"
        let dateString = formatter.string(from: now)
        let content = "Date/time: \(dateString) (\(timeOfDayBucket(for: now)))"
        return ContextBlock(
            kind: "time",
            content: content,
            tokenEstimate: TokenEstimator.estimate(content),
            priority: 1
        )
    }

    private func timeOfDayBucket(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<12: return "morning"
        case 12..<17: return "afternoon"
        case 17..<21: return "evening"
        default: return "night"
        }
    }
}
