//
//  kodaitheme.swift
//  kodai_macos
//

import SwiftUI

enum KodaiTheme: String, CaseIterable, Identifiable {
    static let storageKey = "appTheme"

    case blueGradient
    case sageGlass
    case mutedPurple
    case silverBlack

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blueGradient:
            return "Blue Gradient"
        case .sageGlass:
            return "Sage Glass"
        case .mutedPurple:
            return "Muted Purple"
        case .silverBlack:
            return "Silver Black"
        }
    }

    var palette: ThemePalette {
        switch self {
        case .blueGradient:
            return ThemePalette(
                backgroundBase: Color(red: 28.0 / 255.0, green: 36.0 / 255.0, blue: 42.0 / 255.0),
                backgroundDeep: Color(red: 18.0 / 255.0, green: 35.0 / 255.0, blue: 45.0 / 255.0),
                backgroundRaised: Color(red: 72.0 / 255.0, green: 84.0 / 255.0, blue: 94.0 / 255.0),
                backgroundGlow: Color(red: 118.0 / 255.0, green: 137.0 / 255.0, blue: 145.0 / 255.0),
                primaryAccent: .blue,
                glassSurface: .white.opacity(0.035),
                glassBorder: .white.opacity(0.12),
                primaryText: .white,
                secondaryText: .white.opacity(0.55)
            )
        case .sageGlass:
            return ThemePalette(
                backgroundBase: Color(red: 39.0 / 255.0, green: 48.0 / 255.0, blue: 48.0 / 255.0),
                backgroundDeep: Color(red: 28.0 / 255.0, green: 43.0 / 255.0, blue: 46.0 / 255.0),
                backgroundRaised: Color(red: 83.0 / 255.0, green: 101.0 / 255.0, blue: 96.0 / 255.0),
                backgroundGlow: Color(red: 128.0 / 255.0, green: 151.0 / 255.0, blue: 143.0 / 255.0),
                primaryAccent: Color(red: 139.0 / 255.0, green: 166.0 / 255.0, blue: 158.0 / 255.0),
                glassSurface: Color(red: 184.0 / 255.0, green: 194.0 / 255.0, blue: 192.0 / 255.0).opacity(0.055),
                glassBorder: Color(red: 195.0 / 255.0, green: 205.0 / 255.0, blue: 204.0 / 255.0).opacity(0.20),
                primaryText: Color(red: 235.0 / 255.0, green: 239.0 / 255.0, blue: 238.0 / 255.0),
                secondaryText: Color(red: 188.0 / 255.0, green: 200.0 / 255.0, blue: 197.0 / 255.0)
            )
        case .mutedPurple:
            return ThemePalette(
                backgroundBase: Color(red: 35.0 / 255.0, green: 30.0 / 255.0, blue: 43.0 / 255.0),
                backgroundDeep: Color(red: 24.0 / 255.0, green: 19.0 / 255.0, blue: 34.0 / 255.0),
                backgroundRaised: Color(red: 79.0 / 255.0, green: 67.0 / 255.0, blue: 94.0 / 255.0),
                backgroundGlow: Color(red: 126.0 / 255.0, green: 108.0 / 255.0, blue: 145.0 / 255.0),
                primaryAccent: Color(red: 151.0 / 255.0, green: 130.0 / 255.0, blue: 174.0 / 255.0),
                glassSurface: Color(red: 177.0 / 255.0, green: 164.0 / 255.0, blue: 191.0 / 255.0).opacity(0.045),
                glassBorder: Color(red: 193.0 / 255.0, green: 181.0 / 255.0, blue: 207.0 / 255.0).opacity(0.16),
                primaryText: Color(red: 239.0 / 255.0, green: 235.0 / 255.0, blue: 242.0 / 255.0),
                secondaryText: Color(red: 197.0 / 255.0, green: 187.0 / 255.0, blue: 205.0 / 255.0)
            )
        case .silverBlack:
            return ThemePalette(
                backgroundBase: Color(red: 24.0 / 255.0, green: 25.0 / 255.0, blue: 27.0 / 255.0),
                backgroundDeep: Color(red: 7.0 / 255.0, green: 8.0 / 255.0, blue: 10.0 / 255.0),
                backgroundRaised: Color(red: 76.0 / 255.0, green: 79.0 / 255.0, blue: 84.0 / 255.0),
                backgroundGlow: Color(red: 155.0 / 255.0, green: 159.0 / 255.0, blue: 166.0 / 255.0),
                primaryAccent: Color(red: 183.0 / 255.0, green: 188.0 / 255.0, blue: 195.0 / 255.0),
                glassSurface: Color(red: 197.0 / 255.0, green: 201.0 / 255.0, blue: 207.0 / 255.0).opacity(0.045),
                glassBorder: Color(red: 210.0 / 255.0, green: 214.0 / 255.0, blue: 220.0 / 255.0).opacity(0.18),
                primaryText: Color(red: 240.0 / 255.0, green: 241.0 / 255.0, blue: 243.0 / 255.0),
                secondaryText: Color(red: 185.0 / 255.0, green: 188.0 / 255.0, blue: 194.0 / 255.0)
            )
        }
    }
}

struct ThemePalette {
    let backgroundBase: Color
    let backgroundDeep: Color
    let backgroundRaised: Color
    let backgroundGlow: Color
    let primaryAccent: Color
    let glassSurface: Color
    let glassBorder: Color
    let primaryText: Color
    let secondaryText: Color
}

private struct KodaiThemeKey: EnvironmentKey {
    static let defaultValue = KodaiTheme.blueGradient.palette
}

extension EnvironmentValues {
    var kodaiTheme: ThemePalette {
        get { self[KodaiThemeKey.self] }
        set { self[KodaiThemeKey.self] = newValue }
    }
}
