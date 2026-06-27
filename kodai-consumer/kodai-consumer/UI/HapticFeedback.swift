import UIKit

enum HapticFeedback {
    private static let impact = UIImpactFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()

    static func cardAppear() {
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred()
    }

    static func confirm() {
        notification.notificationOccurred(.success)
    }

    static func cancel() {
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()
    }

    static func success() {
        notification.notificationOccurred(.success)
    }

    static func error() {
        notification.notificationOccurred(.error)
    }

    static func send() {
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()
    }

    /// A soft tick as the timeline crosses from Up Next into the archive.
    static func boundary() {
        let gen = UIImpactFeedbackGenerator(style: .soft)
        gen.impactOccurred(intensity: 0.7)
    }
}
