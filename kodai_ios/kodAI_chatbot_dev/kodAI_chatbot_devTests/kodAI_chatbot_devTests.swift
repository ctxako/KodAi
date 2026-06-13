//
//  kodAI_chatbot_devTests.swift
//  kodAI_chatbot_devTests
//
//  Created by Charles Thomas Xavier Austin III on 6/6/26.
//

import KodaiKernel
import Testing
@testable import KodAi

struct kodAI_chatbot_devTests {

    @Test func example() async throws {
    }

    @Test func generationDiagnostics() async throws {
        let runtime = LocalModelRuntime()
        let prompts = [
            "Hi",
            "Write one sentence about dogs",
            "What is 2+2",
            "What's 6x8"
        ]

        let promptStack = ModelPromptStack(settings: .default)
        for prompt in prompts {
            var assistantText = ""
            print("[PromptTest] prompt=\(prompt.debugDescription)")
            let stream = await runtime.generate(
                messages: [ChatMessage(role: .user, text: prompt)],
                promptStack: promptStack
            )
            for try await event in stream {
                switch event {
                case .token(let chunk, generatedTokenCount: let generatedTokenCount):
                    _ = generatedTokenCount
                    assistantText += chunk
                default:
                    break
                }
            }
            print("[PromptTest] final prompt=\(prompt.debugDescription) length=\(assistantText.count) text=\(assistantText.debugDescription)")
        }
    }

}
