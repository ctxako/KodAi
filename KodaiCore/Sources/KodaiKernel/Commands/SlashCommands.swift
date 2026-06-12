//
//  SlashCommands.swift
//  KodaiKernel
//
//  Shared slash command vocabulary, parsing, and help metadata.
//  The kernel parses commands into typed intents; the apps execute them.
//

import Foundation

/// The typed intent a slash command resolves to.
public enum KodaiSlashCommandKind: String, CaseIterable, Sendable {
    case project
    case task
    case done
    case proposeTask
    case summary
    case export
    case stats
    case tools
    case help
    case commands
    case unknown
}

/// Display metadata for one slash command, used by command pickers and /help.
public struct KodaiSlashCommandMetadata: Identifiable, Equatable, Sendable {
    public let kind: KodaiSlashCommandKind
    public let name: String
    public let description: String
    public let acceptsArgument: Bool

    public var id: String { name }

    public init(kind: KodaiSlashCommandKind, name: String, description: String, acceptsArgument: Bool = false) {
        self.kind = kind
        self.name = name
        self.description = description
        self.acceptsArgument = acceptsArgument
    }

    public static let all: [KodaiSlashCommandMetadata] = [
        KodaiSlashCommandMetadata(kind: .project, name: "/project", description: "Create a new project", acceptsArgument: true),
        KodaiSlashCommandMetadata(kind: .task, name: "/task", description: "Create a task in current project", acceptsArgument: true),
        KodaiSlashCommandMetadata(kind: .done, name: "/done", description: "Complete a task by name", acceptsArgument: true),
        KodaiSlashCommandMetadata(kind: .proposeTask, name: "/propose", description: "Propose a task for confirmation", acceptsArgument: true),
        KodaiSlashCommandMetadata(kind: .help, name: "/help", description: "Show available commands"),
        KodaiSlashCommandMetadata(kind: .commands, name: "/commands", description: "Show available commands"),
        KodaiSlashCommandMetadata(kind: .export, name: "/export", description: "Export current chat as Markdown"),
        KodaiSlashCommandMetadata(kind: .summary, name: "/summary", description: "Summarize current chat"),
        KodaiSlashCommandMetadata(kind: .stats, name: "/stats", description: "Show chat/session stats"),
        KodaiSlashCommandMetadata(kind: .tools, name: "/tools", description: "Show local tool status")
    ]
}

/// The parsed result of one slash command input.
public struct KodaiParsedSlashCommand: Equatable, Sendable {
    public let kind: KodaiSlashCommandKind
    public let rawInput: String
    public let rawArgument: String?
    /// Title with any recognized trailing `due:` token removed.
    /// Nil when the command takes no argument or the argument is missing/invalid
    /// (for `/propose`, nil when the `task` subcommand is absent).
    public let title: String?
    public let dueDate: Date?
    /// The original `due:` token when one was recognized, e.g. "due:today".
    public let dueToken: String?
    public let normalizedCommandName: String

    public init(
        kind: KodaiSlashCommandKind,
        rawInput: String,
        rawArgument: String? = nil,
        title: String? = nil,
        dueDate: Date? = nil,
        dueToken: String? = nil,
        normalizedCommandName: String
    ) {
        self.kind = kind
        self.rawInput = rawInput
        self.rawArgument = rawArgument
        self.title = title
        self.dueDate = dueDate
        self.dueToken = dueToken
        self.normalizedCommandName = normalizedCommandName
    }
}

/// Deterministic parser for the shared slash command vocabulary.
public enum KodaiSlashCommandParser {
    /// Parses one line of input. Returns nil when the input is not a slash
    /// command at all; returns `.unknown` for an unrecognized command name.
    public static func parse(_ input: String, now: Date = Date()) -> KodaiParsedSlashCommand? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }

        guard let match = match(for: trimmed) else {
            return KodaiParsedSlashCommand(kind: .unknown, rawInput: input, normalizedCommandName: trimmed.split(separator: " ").first.map(String.init) ?? trimmed)
        }

        let (command, argument) = match
        switch command.kind {
        case .task:
            guard let argument else {
                return KodaiParsedSlashCommand(kind: .task, rawInput: input, normalizedCommandName: command.name)
            }
            let split = splitDueArgument(argument, now: now)
            return KodaiParsedSlashCommand(
                kind: .task,
                rawInput: input,
                rawArgument: argument,
                title: split.title,
                dueDate: split.dueDate,
                dueToken: split.dueToken,
                normalizedCommandName: command.name
            )
        case .proposeTask:
            guard let argument else {
                return KodaiParsedSlashCommand(kind: .proposeTask, rawInput: input, normalizedCommandName: command.name)
            }
            let parts = argument.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.first?.lowercased() == "task", parts.count == 2 else {
                return KodaiParsedSlashCommand(kind: .proposeTask, rawInput: input, rawArgument: argument, normalizedCommandName: command.name)
            }
            let split = splitDueArgument(parts[1], now: now)
            return KodaiParsedSlashCommand(
                kind: .proposeTask,
                rawInput: input,
                rawArgument: argument,
                title: split.title,
                dueDate: split.dueDate,
                dueToken: split.dueToken,
                normalizedCommandName: command.name
            )
        default:
            return KodaiParsedSlashCommand(
                kind: command.kind,
                rawInput: input,
                rawArgument: argument,
                title: argument,
                normalizedCommandName: command.name
            )
        }
    }

    private static func match(for trimmed: String) -> (command: KodaiSlashCommandMetadata, argument: String?)? {
        for command in KodaiSlashCommandMetadata.all {
            if command.acceptsArgument {
                let prefix = command.name + " "
                if trimmed.hasPrefix(prefix) {
                    let arg = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    return (command, arg.isEmpty ? nil : arg)
                }
                if trimmed == command.name {
                    return (command, nil)
                }
            } else if trimmed == command.name {
                return (command, nil)
            }
        }
        return nil
    }

    /// Splits a trailing `due:` token off a task argument. Supports only
    /// `due:today`, `due:tomorrow`, `due:Jun20`/`due:June20`, and
    /// `due:6/20`/`due:6-20`; anything else stays in the title unchanged.
    public static func splitDueArgument(_ argument: String, now: Date = Date()) -> (title: String, dueDate: Date?, dueToken: String?) {
        var tokens = argument.split(separator: " ").map(String.init)
        guard let index = tokens.lastIndex(where: { $0.lowercased().hasPrefix("due:") }) else {
            return (argument, nil, nil)
        }
        let token = tokens[index]
        guard let dueDate = parseDueValue(String(token.dropFirst(4)), now: now) else {
            return (argument, nil, nil)
        }
        tokens.remove(at: index)
        let title = tokens.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return (title.isEmpty ? argument : title, dueDate, token)
    }

    public static func parseDueValue(_ raw: String, now: Date = Date()) -> Date? {
        let calendar = Calendar.current
        let value = raw.lowercased()

        switch value {
        case "today":
            return calendar.startOfDay(for: now)
        case "tomorrow":
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        default:
            break
        }

        let year = calendar.component(.year, from: now)

        // Numeric form: 6/20 or 6-20
        let numericParts = value.split(whereSeparator: { $0 == "/" || $0 == "-" })
        if numericParts.count == 2,
           let month = Int(numericParts[0]),
           let day = Int(numericParts[1]) {
            let components = DateComponents(year: year, month: month, day: day)
            guard calendar.date(from: components) != nil, (1...12).contains(month), (1...31).contains(day) else { return nil }
            return calendar.date(from: components)
        }

        // Month-name form: Jun20 or June20
        let letters = String(value.prefix(while: { $0.isLetter }))
        guard letters.count >= 3,
              let day = Int(value.dropFirst(letters.count)),
              (1...31).contains(day) else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let fullNames = formatter.monthSymbols.map { $0.lowercased() }
        guard let monthIndex = fullNames.firstIndex(where: { $0.hasPrefix(letters) }) else { return nil }
        return calendar.date(from: DateComponents(year: year, month: monthIndex + 1, day: day))
    }
}
