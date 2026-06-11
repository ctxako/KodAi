//
//  kodaimodel.swift
//  kodai_macos
//
//  Created by Charles Thomas Xavier Austin III on 6/9/26.
//
//
//  KodaiModel.swift
//  kodai_macos
//

import Foundation
import Combine
import FoundationModels

@MainActor
final class KodaiModel: ObservableObject {
    private let model = SystemLanguageModel.default
    private var session: LanguageModelSession?
    private var currentInstructions = ""

    func configure(instructions: String) {
        currentInstructions = instructions
        session = LanguageModelSession(instructions: instructions)
    }

    func streamResponse(
        to input: String,
        onPartial: @escaping @MainActor (String) -> Void
    ) async -> String {

        switch model.availability {
        case .available:
            break

        case .unavailable(let reason):
            let message = """
            Apple Intelligence model unavailable.

            Reason:
            \(reason)
            """
            onPartial(message)
            return message

        @unknown default:
            let message = "Apple Intelligence model unavailable."
            onPartial(message)
            return message
        }

        if session == nil {
            session = LanguageModelSession(instructions: currentInstructions)
        }

        do {
            let stream = session!.streamResponse(to: input)

            var finalText = ""
            var lastUIUpdate = Date.distantPast

            for try await partial in stream {
                try Task.checkCancellation()

                let text = partial.content.trimmingCharacters(in: .whitespacesAndNewlines)
                finalText = text

                // Avoid redrawing SwiftUI for every tiny chunk.
                let now = Date()
                if now.timeIntervalSince(lastUIUpdate) >= 0.035 {
                    onPartial(text)
                    lastUIUpdate = now
                }
            }

            onPartial(finalText)
            return finalText

        } catch is CancellationError {
            return ""

        } catch {
            let message = "Kodai model error: \(error.localizedDescription)"
            onPartial(message)
            return message
        }
    }

    func reset() {
        session = nil
    }
}
