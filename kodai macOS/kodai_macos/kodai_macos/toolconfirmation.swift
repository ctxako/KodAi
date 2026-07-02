//
//  toolconfirmation.swift
//  kodai_macos
//
//  Async user-confirmation gate for mutating tool calls. A tool call awaits
//  `ConfirmBroker.request(_:)`, which suspends it on a continuation while the
//  transcript shows an inline confirmation card; approving or canceling the
//  card resumes the tool with the decision, so the model always receives the
//  true outcome of the action.
//

import Foundation
import Observation

struct ToolConfirmationRequest: Equatable {
    struct Detail: Equatable {
        let icon: String
        let text: String
    }

    let heading: String
    let subject: String
    let details: [Detail]
    let confirmLabel: String
}

@MainActor
@Observable
final class ConfirmBroker {
    struct PendingConfirmation: Identifiable, Equatable {
        let id: UUID
        let request: ToolConfirmationRequest
    }

    private(set) var pending: PendingConfirmation?
    @ObservationIgnored private var continuation: CheckedContinuation<Bool, Never>?

    /// Suspends the calling tool until the user approves (true) or cancels
    /// (false). Only one confirmation can be live; a stale one is declined.
    func request(_ request: ToolConfirmationRequest) async -> Bool {
        cancelPending()
        return await withCheckedContinuation { cont in
            continuation = cont
            pending = PendingConfirmation(id: UUID(), request: request)
        }
    }

    func resolve(approved: Bool) {
        pending = nil
        let cont = continuation
        continuation = nil
        cont?.resume(returning: approved)
    }

    /// Declines and clears any in-flight confirmation. Called on stop, chat
    /// switch, and at turn end so a suspended tool call can never leak.
    func cancelPending() {
        guard continuation != nil || pending != nil else { return }
        resolve(approved: false)
    }
}
