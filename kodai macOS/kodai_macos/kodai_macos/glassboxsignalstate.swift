//
//  glassboxsignalstate.swift
//  kodai_macos
//

import Foundation

struct LiveEntitySignalState: Equatable {
    enum Status: String, Equatable {
        case idle = "Idle"
        case thinking = "Thinking"
        case responding = "Responding"
    }

    let status: Status
    let contextPercent: Int
    let tasksDueCount: Int
    let selectedProjectName: String?
    let memoryReady: Bool
    let toolActionReady: Bool

    var isActive: Bool {
        status != .idle
    }

    var modelPulse: Double {
        switch status {
        case .idle:
            return 0.14
        case .thinking:
            return 0.76
        case .responding:
            return 1
        }
    }

    var contextPressure: Double {
        clamped(Double(contextPercent) / 100)
    }

    var responseHeat: Double {
        switch status {
        case .idle:
            return 0.08
        case .thinking:
            return 0.58
        case .responding:
            return 0.88
        }
    }

    var focusLock: Double {
        selectedProjectName == nil ? 0.12 : 0.86
    }

    var taskPressure: Double {
        guard tasksDueCount > 0 else { return 0.08 }
        return clamped(0.24 + Double(tasksDueCount) * 0.13)
    }

    var readiness: Double {
        clamped(0.1 + (memoryReady ? 0.52 : 0) + (toolActionReady ? 0.38 : 0))
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
