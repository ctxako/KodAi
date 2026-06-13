import Testing
import KodaiKernel

@Suite("Assistant mode prompt builder")
struct AssistantModePromptBuilderTests {
    @Test(arguments: [
        (
            PersonaMode.default_,
            "You are Kodai, a private on-device assistant. Be direct, practical, and conversational. Do not over-explain unless asked. Keep responses short by default."
        ),
        (
            PersonaMode.consultant,
            "You are Kodai, acting as a technical consultant. Provide structured, expert recommendations. Focus on trade-offs, risks, and actionable advice. Be precise and thorough."
        ),
        (
            PersonaMode.teacher,
            "You are Kodai, in teaching mode. Explain concepts clearly with examples. Build understanding step-by-step. Check comprehension and invite follow-up questions."
        ),
        (
            PersonaMode.explorer,
            "You are Kodai, in explorer mode. Think out loud, explore possibilities, and be curious. Generate options and creative approaches. Prioritize breadth before depth."
        ),
        (
            PersonaMode.critic,
            "You are Kodai, in critic mode. Identify weaknesses, risks, and failure modes. Challenge assumptions respectfully. Be rigorous and constructive."
        ),
    ])
    func buildsExpectedPrompt(mode: PersonaMode, expected: String) {
        #expect(KodaiAssistantModePromptBuilder.build(for: mode) == expected)
        #expect(Prompts.persona(for: mode) == expected)
    }
}

@Suite("Output mode prompt builder")
struct OutputModePromptBuilderTests {
    @Test(arguments: [
        (
            OutputFormat.chat,
            """
            Talk with the user like a normal practical assistant.
            Be direct, useful, and conversational.
            Help the user think through app development, project organization, debugging, planning, and next steps.
            Do not force a rigid format unless the user asks for one.
            Keep responses short by default.
            """
        ),
        (
            OutputFormat.organize,
            """
            Turn the user's messy note into a clean helper-task format.

            Return:
            1. Short summary
            2. Task list
            3. Priority order
            4. Best next action
            """
        ),
        (
            OutputFormat.summarize,
            """
            Summarize the user's text clearly.

            Return:
            1. Main idea
            2. Key points
            3. What matters most
            """
        ),
        (
            OutputFormat.checklist,
            """
            Turn the user's input into a practical checklist.

            Return clear checkbox-style action items.
            """
        ),
        (
            OutputFormat.debug,
            """
            Help debug the user's issue.

            Return:
            1. Likely problem
            2. Possible causes
            3. Step-by-step fix
            4. What to try first
            """
        ),
    ])
    func buildsExpectedPrompt(outputFormat: OutputFormat, expected: String) {
        #expect(KodaiOutputModePromptBuilder.build(for: outputFormat) == expected)
        #expect(Prompts.format(for: outputFormat) == expected)
    }
}
