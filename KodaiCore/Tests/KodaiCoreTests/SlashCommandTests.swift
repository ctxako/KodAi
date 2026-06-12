import Foundation
import Testing
@testable import KodaiKernel

@Suite("Slash command parsing")
struct SlashCommandParserTests {
    // Fixed reference date so due: parsing is deterministic.
    private let now: Date
    private let calendar = Calendar.current

    init() {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 12
        now = Calendar.current.date(from: components)!
    }

    private func parse(_ input: String) -> KodaiParsedSlashCommand? {
        KodaiSlashCommandParser.parse(input, now: now)
    }

    @Test func projectCommand() {
        let parsed = parse("/project Build app")
        #expect(parsed?.kind == .project)
        #expect(parsed?.title == "Build app")
        #expect(parsed?.normalizedCommandName == "/project")
    }

    @Test func taskCommand() {
        let parsed = parse("/task Fix bug")
        #expect(parsed?.kind == .task)
        #expect(parsed?.title == "Fix bug")
        #expect(parsed?.dueDate == nil)
        #expect(parsed?.dueToken == nil)
    }

    @Test func taskDueToday() {
        let parsed = parse("/task Fix bug due:today")
        #expect(parsed?.title == "Fix bug")
        #expect(parsed?.dueToken == "due:today")
        #expect(parsed?.dueDate == calendar.startOfDay(for: now))
    }

    @Test func taskDueTomorrow() {
        let parsed = parse("/task Fix bug due:tomorrow")
        #expect(parsed?.title == "Fix bug")
        let expected = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        #expect(parsed?.dueDate == expected)
    }

    private var june20: Date? {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 20))
    }

    @Test func taskDueMonthNameShort() {
        let parsed = parse("/task Fix bug due:Jun20")
        #expect(parsed?.title == "Fix bug")
        #expect(parsed?.dueDate == june20)
    }

    @Test func taskDueMonthNameFull() {
        let parsed = parse("/task Fix bug due:June20")
        #expect(parsed?.title == "Fix bug")
        #expect(parsed?.dueDate == june20)
    }

    @Test func taskDueNumericSlash() {
        let parsed = parse("/task Fix bug due:6/20")
        #expect(parsed?.title == "Fix bug")
        #expect(parsed?.dueDate == june20)
    }

    @Test func taskDueNumericDash() {
        let parsed = parse("/task Fix bug due:6-20")
        #expect(parsed?.title == "Fix bug")
        #expect(parsed?.dueDate == june20)
    }

    @Test func taskUnparseableDueStaysInTitle() {
        let parsed = parse("/task Fix bug due:notadate")
        #expect(parsed?.kind == .task)
        #expect(parsed?.title == "Fix bug due:notadate")
        #expect(parsed?.dueDate == nil)
        #expect(parsed?.dueToken == nil)
    }

    @Test func doneCommand() {
        let parsed = parse("/done Fix bug")
        #expect(parsed?.kind == .done)
        #expect(parsed?.title == "Fix bug")
    }

    @Test func proposeTaskCommand() {
        let parsed = parse("/propose task Fix bug")
        #expect(parsed?.kind == .proposeTask)
        #expect(parsed?.title == "Fix bug")
        #expect(parsed?.rawArgument == "task Fix bug")
    }

    @Test func proposeWithoutTaskSubcommandHasNoTitle() {
        let parsed = parse("/propose Fix bug")
        #expect(parsed?.kind == .proposeTask)
        #expect(parsed?.title == nil)
        #expect(parsed?.rawArgument == "Fix bug")
    }

    @Test func helpCommand() {
        let parsed = parse("/help")
        #expect(parsed?.kind == .help)
    }

    @Test func commandsCommand() {
        let parsed = parse("/commands")
        #expect(parsed?.kind == .commands)
    }

    @Test func unknownCommand() {
        let parsed = parse("/frobnicate now")
        #expect(parsed?.kind == .unknown)
        #expect(parsed?.normalizedCommandName == "/frobnicate")
    }

    @Test func nonSlashInputIsNotACommand() {
        #expect(parse("hello world") == nil)
    }

    @Test func bareTaskHasNoTitle() {
        let parsed = parse("/task")
        #expect(parsed?.kind == .task)
        #expect(parsed?.title == nil)
    }

    @Test func metadataIncludesAllSharedCommands() {
        let names = Set(KodaiSlashCommandMetadata.all.map(\.name))
        for expected in ["/summary", "/export", "/stats", "/tools", "/project", "/task", "/done", "/propose", "/help", "/commands"] {
            #expect(names.contains(expected), "missing \(expected)")
        }
        let proposeKind = KodaiSlashCommandMetadata.all.first { $0.name == "/propose" }?.kind
        #expect(proposeKind == .proposeTask)
    }
}
