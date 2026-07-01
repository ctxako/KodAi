//
//  WatchdogAgentModel.swift
//  kodai-consumer
//
//  Wraps an AgentModel with a per-turn timeout so a stuck generation can't
//  hang a chain: the underlying inference is torn down and the loop receives
//  a thrown error the controller maps to "that took too long".
//

import Foundation

struct AgentTurnTimeout: Error {}

struct WatchdogAgentModel: AgentModel {
    let base: RuntimeAgentModel
    /// Seconds allowed per model turn before the turn is torn down.
    var timeout: UInt64 = 45

    func complete(systemPrompt: String, messages: [AgentMessage]) async throws -> String {
        let outcome = await withTaskGroup(of: String?.self) { group in
            group.addTask {
                (try? await base.complete(systemPrompt: systemPrompt, messages: messages)) ?? ""
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeout * 1_000_000_000)
                return nil
            }
            defer { group.cancelAll() }
            return await group.next() ?? nil
        }
        guard let output = outcome else {
            await base.cancel()
            throw AgentTurnTimeout()
        }
        try Task.checkCancellation()
        return output
    }
}
