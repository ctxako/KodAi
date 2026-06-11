//
//  InferenceService.swift
//  kodAI_chatbot_dev
//
//  Created by Charles Thomas Xavier Austin III on 6/6/26.
//

import Foundation

actor InferenceService {
    private let runtime = LocalModelRuntime()
    private let ambientContextProvider = AmbientContextProvider()

    func generate(
        messages: [ChatMessage],
        promptStack: ModelPromptStack,
        contextPressurePercent: Int
    ) async -> AsyncThrowingStream<InferenceEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                continuation.yield(.phase(.checkingRuntimeState))
                var constraintSnapshot = ChatViewModel.makeRuntimeConstraintSnapshot(
                    ambientContext: nil,
                    contextPressurePercent: contextPressurePercent
                )

                let userPrompt = messages.last(where: { $0.role == .user })?.text ?? ""
                let ambientResult = await ambientContextProvider.snapshot(for: userPrompt) { phase in
                    continuation.yield(.phase(phase))
                }
                ambientResult.diagnostics.forEach { continuation.yield(.diagnostic($0)) }

                constraintSnapshot = ChatViewModel.makeRuntimeConstraintSnapshot(
                    ambientContext: ambientResult.context,
                    contextPressurePercent: contextPressurePercent
                )
                constraintSnapshot.activeDiagnostics.forEach { continuation.yield(.diagnostic($0)) }

                let constrainedPromptStack = ModelPromptStack(
                    settings: promptStack.settings,
                    runtimeConstraintPromptBlock: makeRuntimeConstraintPromptBlock(constraintSnapshot),
                    ambientContext: promptStack.ambientContext
                )

                let stream = await runtime.generate(
                    messages: messages,
                    promptStack: constrainedPromptStack.withAmbientContext(ambientResult.context)
                )

                do {
                    for try await event in stream {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func prewarm(onStatus: @Sendable (WarmupStatus) -> Void) async {
        await runtime.prewarm(onStatus: onStatus)
    }

    func cancel() async {
        await runtime.cancel()
    }
}
