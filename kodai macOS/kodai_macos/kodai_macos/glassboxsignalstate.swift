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

    var activityLevel: Double {
        switch status {
        case .idle:
            return 0.08
        case .thinking:
            return 0.52
        case .responding:
            return 0.82
        }
    }
}
