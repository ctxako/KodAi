//
//  WatchdogAgentModel.swift
//  kodai-consumer
//
//  Wraps an AgentModel with a per-turn timeout so a stuck generation can't
//  hang a chain: the underlying inference is torn down and the loop receives
//  a thrown error the controller maps to "that took too long".
//
//  Also the thermal guard: sustained inference is the hottest thing this app
//  does, so the check lives where turns start. `.serious` gets a brief
//  cool-down pause between turns; `.critical` refuses the turn entirely
//  rather than pushing a throttling phone harder.
//

import Foundation

struct AgentTurnTimeout: Error {}
struct AgentThermalCritical: Error {}

struct WatchdogAgentModel: AgentModel {
    let base: RuntimeAgentModel
    /// Seconds allowed per model turn before the turn is torn down.
    var timeout: UInt64 = 45

    func complete(systemPrompt: String, messages: [AgentMessage]) async throws -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .critical:
            throw AgentThermalCritical()
        case .serious:
            try await Task.sleep(nanoseconds: 3_000_000_000)
        default:
            break
        }

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
