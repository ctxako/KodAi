import SwiftUI
import UIKit

enum ChatPalette {
    static let mainCanvas = Color(red: 0.055, green: 0.061, blue: 0.071)
    static let canvasGlow = Color(red: 0.104, green: 0.145, blue: 0.188)
    static let elevatedSurface = Color(red: 0.094, green: 0.106, blue: 0.122)
    static let assistantBubble = Color(red: 0.133, green: 0.149, blue: 0.169)
    static let accentBlue = Color(red: 0.184, green: 0.490, blue: 0.965)
    static let userBubble = Color(red: 0.110, green: 0.330, blue: 0.680)
    static let glassStroke = Color.white.opacity(0.16)
    static let statusSurface = Color(red: 0.176, green: 0.196, blue: 0.224)
    static let inputField = Color(red: 0.125, green: 0.141, blue: 0.161)
}

enum MessageListAnchor {
    static let bottom = "message-list-bottom"
}

enum PrefKey {
    static let messageTextSize = "pref.messageTextSize"
    static let reduceMotion = "pref.reduceMotion"
    static let haptics = "pref.haptics"
    static let compactMessageSpacing = "pref.compactMessageSpacing"
    static let surpriseHighlighting = "pref.surpriseHighlighting"
}

enum Haptics {
    private static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: PrefKey.haptics) as? Bool ?? true
    }

    static func lightTap() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

enum MessageTextSize: String, CaseIterable, Identifiable {
    case small
    case regular
    case large
    case extraLarge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small:
            return "Small"
        case .regular:
            return "Default"
        case .large:
            return "Large"
        case .extraLarge:
            return "XL"
        }
    }

    var font: Font {
        switch self {
        case .small:
            return .callout
        case .regular:
            return .body
        case .large:
            return .title3
        case .extraLarge:
            return .title2
        }
    }
}
