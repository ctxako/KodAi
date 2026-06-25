//
//  StateAnchor.swift
//  kodai-consumer
//
//  The task-state object re-injected into the prompt every loop so a 1.2B
//  never loses the original goal. Kept compact on purpose.
//

import Foundation

struct StateAnchor: Equatable, Sendable {
    let originalTask: String
    private(set) var stepsCompleted: [String]
    var next: String?

    init(originalTask: String, stepsCompleted: [String] = [], next: String? = nil) {
        self.originalTask = originalTask
        self.stepsCompleted = stepsCompleted
        self.next = next
    }

    mutating func record(_ step: String) {
        stepsCompleted.append(step)
    }

    /// Compact, deterministic JSON injected each turn:
    /// {"original_task":"…","steps_completed":["…"],"next":"…"}
    func asContextJSON() -> String {
        var payload: [String: Any] = [
            "original_task": originalTask,
            "steps_completed": stepsCompleted
        ]
        if let next {
            payload["next"] = next
        }
        let data = (try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
