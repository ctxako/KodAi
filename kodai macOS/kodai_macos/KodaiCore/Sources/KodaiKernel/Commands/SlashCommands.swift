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
    /// Title with task flags removed.
    /// Nil when the command takes no argument or the argument is missing/invalid
    /// (for `/propose`, nil when the `task` subcommand is absent).
    public let title: String?
    /// Parsed task priority. Nil means the app should use its default priority.
    public let taskPriority: KodaiTaskPriority?
    public let dueDate: Date?
    /// The original `due:` token when present, e.g. "due:today".
    /// A non-nil token with a nil date explicitly represents an invalid date.
    public let dueToken: String?
    public let normalizedCommandName: String

    public init(
        kind: KodaiSlashCommandKind,
        rawInput: String,
        rawArgument: String? = nil,
        title: String? = nil,
        taskPriority: KodaiTaskPriority? = nil,
        dueDate: Date? = nil,
        dueToken: String? = nil,
        normalizedCommandName: String
    ) {
        self.kind = kind
        self.rawInput = rawInput
        self.rawArgument = rawArgument
        self.title = title
        self.taskPriority = taskPriority
        self.dueDate = dueDate
        self.dueToken = dueToken
        self.normalizedCommandName = normalizedCommandName
    }
}

/// Deterministic parser for the shared slash command vocabulary.
public enum KodaiSlashCommandParser {
    /// Parses one line of input. Returns nil when the input is not a slash
    /// command at all; returns `.unknown` for an unrecognized command name.
    public static func parse(
        _ input: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> KodaiParsedSlashCommand? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }

        guard let match = match(for: trimmed) else {
            let commandName = trimmed
                .split(whereSeparator: \.isWhitespace)
                .first
                .map { String($0).lowercased() } ?? trimmed.lowercased()
            return KodaiParsedSlashCommand(
                kind: .unknown,
                rawInput: input,
                normalizedCommandName: commandName
            )
        }

        let (command, argument) = match
        switch command.kind {
        case .task:
            guard let argument else {
                return KodaiParsedSlashCommand(kind: .task, rawInput: input, normalizedCommandName: command.name)
            }
            let flags = parseTaskArguments(argument, now: now, calendar: calendar)
            return KodaiParsedSlashCommand(
                kind: .task,
                rawInput: input,
                rawArgument: argument,
                title: flags.title,
                taskPriority: flags.priority,
                dueDate: flags.dueDate,
                dueToken: flags.dueToken,
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
            let flags = parseTaskArguments(parts[1], now: now, calendar: calendar)
            return KodaiParsedSlashCommand(
                kind: .proposeTask,
                rawInput: input,
                rawArgument: argument,
                title: flags.title,
                taskPriority: flags.priority,
                dueDate: flags.dueDate,
                dueToken: flags.dueToken,
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
        let lowercased = trimmed.lowercased()
        for command in KodaiSlashCommandMetadata.all {
            if command.acceptsArgument {
                let prefix = command.name + " "
                if lowercased.hasPrefix(prefix) {
                    let arg = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    return (command, arg.isEmpty ? nil : arg)
                }
                if lowercased == command.name {
                    return (command, nil)
                }
            } else if lowercased == command.name {
                return (command, nil)
            }
        }
        return nil
    }

    /// Removes recognized task flags from an argument. Invalid `due:` values
    /// are removed from the title but retained in `dueToken` with a nil date.
    public static func parseTaskArguments(
        _ argument: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (title: String, priority: KodaiTaskPriority?, dueDate: Date?, dueToken: String?) {
        var tokens = argument.split(separator: " ").map(String.init)

        var priority: KodaiTaskPriority?
        if let index = tokens.firstIndex(where: { $0.lowercased().hasPrefix("priority:") }) {
            let token = tokens[index]
            let rawPriority = String(token.dropFirst("priority:".count)).lowercased()
            switch rawPriority {
            case "low":
                priority = .low
                tokens.remove(at: index)
            case "normal", "medium":
                priority = .normal
                tokens.remove(at: index)
            case "high":
                priority = .high
                tokens.remove(at: index)
            default:
                break
            }
        }

        var dueDate: Date?
        var dueToken: String?
        if let index = tokens.firstIndex(where: { $0.lowercased().hasPrefix("due:") }) {
            dueToken = tokens.remove(at: index)
            dueDate = parseDueValue(String(dueToken!.dropFirst(4)), now: now, calendar: calendar)
        }

        // Fallback: scan remaining title tokens for natural date phrases
        // when no explicit due: token was found.
        if dueDate == nil, dueToken == nil {
            if let match = parseFallbackDueDateFromTokens(tokens, now: now, calendar: calendar) {
                dueDate = match.date
                for index in match.indicesToRemove.sorted(by: >) {
                    tokens.remove(at: index)
                }
            }
        }

        let title = tokens.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return (title, priority, dueDate, dueToken)
    }

    // Scans the end of the token array for: [prep] [month] [day], [prep] [date],
    // [month] [day], or a bare today/tomorrow. Returns matched indices and parsed date.
    private static func parseFallbackDueDateFromTokens(
        _ tokens: [String],
        now: Date,
        calendar: Calendar
    ) -> (indicesToRemove: [Int], date: Date)? {
        let count = tokens.count
        guard count > 0 else { return nil }

        let prepositions: Set<String> = ["on", "due", "by"]

        // [prep] [month] [day] — three tokens from end
        if count >= 3 {
            let i0 = count - 3, i1 = count - 2, i2 = count - 1
            if prepositions.contains(tokens[i0].lowercased()) {
                let combined = tokens[i1].lowercased() + stripOrdinalSuffix(tokens[i2].lowercased())
                if let date = parseDueValue(combined, now: now, calendar: calendar) {
                    return ([i0, i1, i2], date)
                }
            }
        }

        // Two tokens from end
        if count >= 2 {
            let i0 = count - 2, i1 = count - 1
            let tok0 = tokens[i0].lowercased()
            let tok1 = tokens[i1].lowercased()

            // [prep] [date-word] — e.g. "due today", "on tomorrow"
            if prepositions.contains(tok0) {
                if let date = parseDueValue(stripOrdinalSuffix(tok1), now: now, calendar: calendar) {
                    return ([i0, i1], date)
                }
            }

            // [month] [day] with no preposition — e.g. "june 13"
            let combined = tok0 + stripOrdinalSuffix(tok1)
            if let date = parseDueValue(combined, now: now, calendar: calendar) {
                return ([i0, i1], date)
            }
        }

        // Single bare token — today, tomorrow
        let last = tokens[count - 1].lowercased()
        if let date = parseDueValue(stripOrdinalSuffix(last), now: now, calendar: calendar) {
            return ([count - 1], date)
        }

        return nil
    }

    private static func stripOrdinalSuffix(_ s: String) -> String {
        for suffix in ["th", "st", "nd", "rd"] where s.hasSuffix(suffix) {
            let stripped = String(s.dropLast(suffix.count))
            if Int(stripped) != nil { return stripped }
        }
        return s
    }

    public static func splitDueArgument(
        _ argument: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (title: String, dueDate: Date?, dueToken: String?) {
        let parsed = parseTaskArguments(argument, now: now, calendar: calendar)
        return (parsed.title, parsed.dueDate, parsed.dueToken)
    }

    public static func parseDueValue(
        _ raw: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
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

        // Full numeric forms: 2026-06-20 or 6/20/2026.
        let isoParts = value.split(separator: "-", omittingEmptySubsequences: false)
        if isoParts.count == 3,
           let explicitYear = Int(isoParts[0]),
           let month = Int(isoParts[1]),
           let day = Int(isoParts[2]) {
            return exactDate(year: explicitYear, month: month, day: day, calendar: calendar)
        }

        let slashParts = value.split(separator: "/", omittingEmptySubsequences: false)
        if slashParts.count == 3,
           let month = Int(slashParts[0]),
           let day = Int(slashParts[1]),
           let explicitYear = Int(slashParts[2]) {
            return exactDate(year: explicitYear, month: month, day: day, calendar: calendar)
        }

        // Year-relative numeric form: 6/20 or 6-20.
        let numericParts = value.split(whereSeparator: { $0 == "/" || $0 == "-" })
        if numericParts.count == 2,
           let month = Int(numericParts[0]),
           let day = Int(numericParts[1]) {
            return exactDate(year: year, month: month, day: day, calendar: calendar)
        }

        // Month-name form: Jun20 or June20
        let letters = String(value.prefix(while: { $0.isLetter }))
        guard letters.count >= 3,
              let day = Int(value.dropFirst(letters.count)),
              (1...31).contains(day) else { return nil }

        let fullNames = [
            "january", "february", "march", "april", "may", "june",
            "july", "august", "september", "october", "november", "december"
        ]
        guard let monthIndex = fullNames.firstIndex(where: { $0.hasPrefix(letters) }) else { return nil }
        return exactDate(year: year, month: monthIndex + 1, day: day, calendar: calendar)
    }

    private static func exactDate(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            return nil
        }
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard components.year == year, components.month == month, components.day == day else {
            return nil
        }
        return calendar.startOfDay(for: date)
    }
}
