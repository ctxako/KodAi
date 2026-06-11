//
//  outputmode.swift
//  kodai_macos
//

import Foundation

enum OutputMode: String, CaseIterable {
    case chat = "Chat"
    case organize = "Organize"
    case summarize = "Summarize"
    case checklist = "Checklist"
    case debug = "Debug"

    var systemPrompt: String {
        switch self {
        case .chat:
            return """
            Talk with the user like a normal practical assistant.
            Be direct, useful, and conversational.
            Help the user think through app development, project organization, debugging, planning, and next steps.
            Do not force a rigid format unless the user asks for one.
            Keep responses short by default.
            """

        case .organize:
            return """
            Turn the user's messy note into a clean helper-task format.

            Return:
            1. Short summary
            2. Task list
            3. Priority order
            4. Best next action
            """

        case .summarize:
            return """
            Summarize the user's text clearly.

            Return:
            1. Main idea
            2. Key points
            3. What matters most
            """

        case .checklist:
            return """
            Turn the user's input into a practical checklist.

            Return clear checkbox-style action items.
            """

        case .debug:
            return """
            Help debug the user's issue.

            Return:
            1. Likely problem
            2. Possible causes
            3. Step-by-step fix
            4. What to try first
            """
        }
    }
}
