//
//  LiveEntitySignalState.swift
//  KodaiKernel
//
//  Foundation-only signal model shared across macOS and iOS targets.

import Foundation

public struct LiveEntitySignalState: Equatable {
    public enum Status: String, Equatable {
        case idle = "Idle"
        case thinking = "Thinking"
        case responding = "Responding"
    }

    public let status: Status
    public let contextPercent: Int
    public let tasksDueCount: Int
    public let selectedProjectName: String?
    public let memoryReady: Bool
    public let toolActionReady: Bool

    public init(
        status: Status,
        contextPercent: Int,
        tasksDueCount: Int,
        selectedProjectName: String?,
        memoryReady: Bool,
        toolActionReady: Bool
    ) {
        self.status = status
        self.contextPercent = contextPercent
        self.tasksDueCount = tasksDueCount
        self.selectedProjectName = selectedProjectName
        self.memoryReady = memoryReady
        self.toolActionReady = toolActionReady
    }

    public var isActive: Bool {
        status != .idle
    }

    public var modelPulse: Double {
        switch status {
        case .idle:
            return 0.14
        case .thinking:
            return 0.76
        case .responding:
            return 1
        }
    }

    public var contextPressure: Double {
        clamped(Double(contextPercent) / 100)
    }

    public var responseHeat: Double {
        switch status {
        case .idle:
            return 0.08
        case .thinking:
            return 0.58
        case .responding:
            return 0.88
        }
    }

    public var focusLock: Double {
        selectedProjectName == nil ? 0.12 : 0.86
    }

    public var taskPressure: Double {
        guard tasksDueCount > 0 else { return 0.08 }
        return clamped(0.24 + Double(tasksDueCount) * 0.13)
    }

    public var readiness: Double {
        clamped(0.1 + (memoryReady ? 0.52 : 0) + (toolActionReady ? 0.38 : 0))
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
