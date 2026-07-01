//
//  DeviceTier.swift
//  kodai-consumer
//
//  The floor device defines the budget. iPhone 12/13 (4 GB RAM) get shorter
//  chains and a longer per-turn watchdog than iPhone 14+ (6 GB): longer
//  context = bigger KV cache on the tier that can least afford it, and the
//  A14/A15-without-headroom generates slower under memory pressure.
//
//  Numbers here are starting points pending real-device profiling
//  (PRODUCTION_PLAN.md Milestone 3) — adjust from Instruments data, not vibes.
//

import Foundation

enum DeviceTier {
    /// ≤4 GB RAM — iPhone 12/13 class. The device the budgets are proven on.
    case floor
    /// 6 GB+ RAM — iPhone 14 and newer.
    case standard

    static let current: DeviceTier =
        ProcessInfo.processInfo.physicalMemory < 5_000_000_000 ? .floor : .standard

    /// Chain-depth budget for one task.
    var maxAgentSteps: Int {
        switch self {
        case .floor: return 4
        case .standard: return 6
        }
    }

    /// Seconds allowed per model turn before the watchdog tears it down.
    var turnTimeoutSeconds: UInt64 {
        switch self {
        case .floor: return 60
        case .standard: return 45
        }
    }
}
