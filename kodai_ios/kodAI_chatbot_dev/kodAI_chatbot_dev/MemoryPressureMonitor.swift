//
//  MemoryPressureMonitor.swift
//  kodAI_chatbot_dev
//
//  Observes UIKit memory-warning notifications so the runtime constraint
//  snapshot can report real memory pressure (the `lowMemoryWarningActive` slot
//  that previously had no source) and so generation pacing can back off before
//  the OS jetsams a ~700 MB on-device model mid-stream.
//

import UIKit

final class MemoryPressureMonitor: @unchecked Sendable {
    static let shared = MemoryPressureMonitor()

    /// How long after a warning we still treat the device as under pressure.
    private static let cooldown: TimeInterval = 30

    private let lock = NSLock()
    private var lastWarning: Date?

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    /// Touch at launch so the observer registers before the first generation.
    func start() {}

    @objc private func handleWarning() {
        lock.lock()
        lastWarning = Date()
        lock.unlock()
    }

    /// True if a memory warning fired within the cooldown window.
    var isUnderPressure: Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let lastWarning else { return false }
        return Date().timeIntervalSince(lastWarning) < Self.cooldown
    }
}
