//
//  AppIconOption.swift
//  kodAI_chatbot_dev
//
//  The selectable home-screen app icons. "1" is the primary (set via the
//  ASSETCATALOG_COMPILER_APPICON_NAME build setting); "2" is registered as an
//  alternate (ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES) and swapped in at
//  runtime with setAlternateIconName.
//

import UIKit

enum AppIconOption: String, CaseIterable, Identifiable {
    /// The default icon shipped as the primary; cleared by passing nil.
    case one = "1"
    case two = "2"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .one: return "Icon 1"
        case .two: return "Icon 2"
        }
    }

    /// The name passed to `setAlternateIconName`. `nil` restores the primary.
    var alternateIconName: String? {
        switch self {
        case .one: return nil
        case .two: return rawValue
        }
    }

    /// Whichever icon is currently active, derived from the system.
    @MainActor
    static var current: AppIconOption {
        guard let name = UIApplication.shared.alternateIconName else { return .one }
        return AppIconOption(rawValue: name) ?? .one
    }

    /// Switches the home-screen icon. No-op if the device doesn't support
    /// alternates or the requested icon is already active.
    @MainActor
    static func apply(_ option: AppIconOption) {
        let application = UIApplication.shared
        guard application.supportsAlternateIcons else { return }
        guard application.alternateIconName != option.alternateIconName else { return }
        application.setAlternateIconName(option.alternateIconName) { error in
            if let error {
                AppLog(category: "AppIcon").event("icon switch failed: \(error.localizedDescription)")
            }
        }
    }
}
