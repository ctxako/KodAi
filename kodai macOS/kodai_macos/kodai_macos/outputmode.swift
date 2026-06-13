//
//  outputmode.swift
//  kodai_macos
//

import Foundation
import KodaiCore

enum OutputMode: String, CaseIterable {
    case chat = "Chat"
    case organize = "Organize"
    case summarize = "Summarize"
    case checklist = "Checklist"
    case debug = "Debug"

    var outputFormat: OutputFormat {
        switch self {
        case .chat:
            return .chat
        case .organize:
            return .organize
        case .summarize:
            return .summarize
        case .checklist:
            return .checklist
        case .debug:
            return .debug
        }
    }
}
