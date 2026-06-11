//
//  kodAI_chatbot_devTests.swift
//  kodAI_chatbot_devTests
//
//  Created by Charles Thomas Xavier Austin III on 6/6/26.
//

import Testing
@testable import kodAI_chatbot_dev

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

        for prompt in prompts {
            var assistantText = ""
            print("[PromptTest] prompt=\(prompt.debugDescription)")
            let stream = await runtime.generate(prompt: prompt)
            for try await event in stream {
                if case .token(let chunk) = event {
                    assistantText += chunk
                }
            }
            print("[PromptTest] final prompt=\(prompt.debugDescription) length=\(assistantText.count) text=\(assistantText.debugDescription)")
        }
    }

}
