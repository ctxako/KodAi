//
//  ConstraintSnapshot.swift
//  kodAI_chatbot_dev
//
//  Created by OpenAI Codex on 6/8/26.
//

import Foundation

struct ConstraintSnapshot: Equatable, Sendable {
    var isOffline: Bool?
    var internetAccessEnabled: Bool?
    var weatherAvailable: Bool?
    var weatherUnavailableReason: String?

    var lowMemoryWarningActive: Bool?
    var thermalState: ProcessInfo.ThermalState?
    var lowPowerModeEnabled: Bool?

    var contextWasCompressed: Bool?
    var contextPressurePercent: Int?

    var modelName: String?
}

func makeRuntimeConstraintPromptBlock(_ snapshot: ConstraintSnapshot) -> String? {
    var lines: [String] = []

    if snapshot.internetAccessEnabled == false {
        lines.append("- Internet access: disabled")
    }

    if snapshot.isOffline == true {
        lines.append("- Network: offline")
    }

    if snapshot.weatherAvailable == false {
        if let reason = snapshot.weatherUnavailableReason, !reason.isEmpty {
            lines.append("- Weather access: unavailable (\(reason))")
        } else {
            lines.append("- Weather access: unavailable")
        }
    }

    if snapshot.lowPowerModeEnabled == true {
        lines.append("- Device: low power mode")
    }

    if snapshot.lowMemoryWarningActive == true {
        lines.append("- Device: low memory pressure")
    }

    if snapshot.thermalState == .serious || snapshot.thermalState == .critical {
        lines.append("- Device: thermal pressure")
    }

    if snapshot.contextWasCompressed == true {
        lines.append("- Context: compressed")
    }

    if let pressure = snapshot.contextPressurePercent, pressure >= 75 {
        lines.append("- Context pressure: \(pressure)%")
    }

    guard !lines.isEmpty else { return nil }

    return """
    Runtime constraints:
    \(lines.joined(separator: "\n"))

    Assistant behavior:
    - Be honest about unavailable capabilities.
    - Do not claim live web, weather, or current external data unless it was actually provided.
    - If context was compressed, mention uncertainty only when it affects the answer.
    - Under low memory, high context pressure, thermal pressure, or low power mode, prefer slightly more concise answers.
    - If a requested capability is unavailable, say so briefly and continue with the best local answer.
    - Do not over-mention constraints in normal replies.
    - Do not repeatedly apologize for limitations.
    """
}

extension ConstraintSnapshot {
    var activeDiagnostics: [String] {
        var diagnostics: [String] = []

        if contextWasCompressed == true {
            diagnostics.append("Using compressed context.")
        }

        if internetAccessEnabled == false {
            diagnostics.append("Internet disabled.")
        }

        if weatherAvailable == false {
            diagnostics.append("Weather unavailable.")
        }

        if lowPowerModeEnabled == true {
            diagnostics.append("Low power mode.")
        }

        if thermalState == .serious || thermalState == .critical {
            diagnostics.append("Thermal pressure.")
        }

        if let contextPressurePercent, contextPressurePercent >= 75 {
            diagnostics.append("High context pressure.")
        }

        return diagnostics
    }
}
