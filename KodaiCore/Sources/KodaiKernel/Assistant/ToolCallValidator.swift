//
//  ToolCallValidator.swift
//  KodaiKernel
//
//  Turns a parsed `RawToolCall` into a typed, checked `AssistantToolCall`,
//  or an error the caller can use to drive a single silent retry. Offloads
//  the model's weak spot (time) to dumb code: dates must parse AND be in the
//  future; calendar end must be after start.
//

import Foundation

public struct ToolCallValidator {
    public var now: () -> Date = Date.init
    public var calendar: Calendar = .current
    public var timeZone: TimeZone = .current

    public var resolveNaturalDate: (_ phrase: String, _ now: Date) -> Date? = { phrase, now in
        if let relative = ToolCallValidator.resolveRelativeTime(in: phrase, now: now) {
            return relative
        }
        return ToolCallValidator.detectDate(in: phrase)
    }

    public init() {}

    public func validate(_ raw: RawToolCall, userInput: String = "") -> Result<AssistantToolCall, ToolValidationError> {
        guard let tool = AssistantToolName(rawValue: raw.name) else {
            return .failure(.unknownTool(raw.name))
        }

        switch tool {
        case .calendarCreateEvent:
            return validateCalendarCreateEvent(raw.arguments, userInput: userInput)
        case .calendarListEvents:
            return validateCalendarListEvents(raw.arguments)
        case .calendarDeleteEvent:
            return validateCalendarDeleteEvent(raw.arguments)
        case .remindersCreate:
            return validateRemindersCreate(raw.arguments, userInput: userInput)
        case .remindersList:
            return validateRemindersList(raw.arguments)
        case .remindersComplete:
            return validateRemindersComplete(raw.arguments)
        case .contactsSearch:
            return validateContactsSearch(raw.arguments)
        case .contactsCreate:
            return validateContactsCreate(raw.arguments)
        case .filesList:
            return validateFilesList(raw.arguments)
        case .filesRead:
            return validateFilesRead(raw.arguments)
        case .filesCreate:
            return validateFilesCreate(raw.arguments)
        case .filesCreateFolder:
            return validateFilesCreateFolder(raw.arguments)
        case .filesDelete:
            return validateFilesDelete(raw.arguments)
        case .clipboardRead:
            return .success(.clipboardRead)
        case .clipboardWrite:
            return validateClipboardWrite(raw.arguments)
        case .notificationSchedule:
            return validateNotificationSchedule(raw.arguments, userInput: userInput)
        case .notificationCancel:
            return validateNotificationCancel(raw.arguments)
        case .webFetch:
            return validateWebFetch(raw.arguments)
        case .openUrl:
            return validateOpenUrl(raw.arguments)
        }
    }

    // MARK: - Calendar

    private func validateCalendarCreateEvent(_ args: [String: String], userInput: String) -> Result<AssistantToolCall, ToolValidationError> {
        guard let title = nonEmpty(args["title"]) else { return .failure(.missingField("title")) }

        let start: Date
        switch resolveDate(iso: args["start_date"], userInput: userInput, field: "start_date") {
        case .failure(let error): return .failure(error)
        case .success(.some(let date)): start = date
        case .success(.none): return .failure(.missingField("start_date"))
        }

        var end: Date?
        if let endRaw = nonEmpty(args["end_date"]) {
            guard let parsedEnd = parseDate(endRaw) else { return .failure(.badDate(field: "end_date", value: endRaw)) }
            guard parsedEnd > start else { return .failure(.endBeforeStart) }
            end = parsedEnd
        }

        let allDay: Bool? = nonEmpty(args["all_day"]).map { $0.lowercased() == "true" }

        return .success(.calendarCreateEvent(
            title: title,
            startDate: start,
            endDate: end,
            location: nonEmpty(args["location"]),
            notes: nonEmpty(args["notes"]),
            calendarName: nonEmpty(args["calendar_name"]),
            allDay: allDay
        ))
    }

    private func validateCalendarListEvents(_ args: [String: String]) -> Result<AssistantToolCall, ToolValidationError> {
        guard let startRaw = nonEmpty(args["start_date"]) else { return .failure(.missingField("start_date")) }
        guard let start = parseDate(startRaw) else { return .failure(.badDate(field: "start_date", value: startRaw)) }

        guard let endRaw = nonEmpty(args["end_date"]) else { return .failure(.missingField("end_date")) }
        guard let end = parseDate(endRaw) else { return .failure(.badDate(field: "end_date", value: endRaw)) }

        return .success(.calendarListEvents(
            startDate: start,
            endDate: end,
            calendarName: nonEmpty(args["calendar_name"])
        ))
    }

    private func validateCalendarDeleteEvent(_ args: [String: String]) -> Result<AssistantToolCall, ToolValidationError> {
        guard let eventId = nonEmpty(args["event_id"]) else { return .failure(.missingField("event_id")) }
        return .success(.calendarDeleteEvent(eventId: eventId))
    }

    // MARK: - Reminders

    private func validateRemindersCreate(_ args: [String: String], userInput: String) -> Result<AssistantToolCall, ToolValidationError> {
        // "What's on my groceries list" / "show me my to-do list" magnetize a
        // 1.2B toward reminders_create no matter how the routing rules are
        // worded — the create rule's list_name examples teach exactly that
        // extraction. A pure question must never create; remap deterministically
        // and keep any list filter the model extracted.
        if Self.isTaskQuery(userInput) {
            return .success(.remindersList(
                listName: nonEmpty(args["list_name"]),
                completed: false
            ))
        }

        guard let title = nonEmpty(args["title"]) else { return .failure(.missingField("title")) }

        let due: Date?
        switch resolveDate(iso: args["due_date"], userInput: userInput, field: "due_date") {
        case .failure(.pastDate):
            // The model routinely invents a past "today" due date when the user
            // gave none. A dateless reminder beats a failed one — drop it.
            due = nil
        case .failure(let error): return .failure(error)
        case .success(let date): due = date
        }

        return .success(.remindersCreate(
            title: title,
            dueDate: due,
            notes: nonEmpty(args["notes"]),
            listName: nonEmpty(args["list_name"]),
            priority: nonEmpty(args["priority"])
        ))
    }

    /// A request that only asks about tasks — question phrasing with no
    /// creation verb anywhere. Deliberately conservative: any hint of an
    /// imperative ("add", "remind me", …) keeps the model's create call.
    public static func isTaskQuery(_ userInput: String) -> Bool {
        let text = userInput.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        let creationHints = ["add ", "put ", "throw ", "create", "new ", "remind me to",
                             "remember", "set ", "make ", "buy ", "get ", "don't forget"]
        if creationHints.contains(where: text.contains) { return false }
        let queryStarts = ["what", "show me", "show my", "do i have", "list my",
                           "which ", "any ", "am i", "how many"]
        return queryStarts.contains(where: text.hasPrefix)
    }

    private func validateRemindersList(_ args: [String: String]) -> Result<AssistantToolCall, ToolValidationError> {
        let completed = nonEmpty(args["completed"])?.lowercased() == "true"
        return .success(.remindersList(
            listName: nonEmpty(args["list_name"]),
            completed: completed
        ))
    }

    private func validateRemindersComplete(_ args: [String: String]) -> Result<AssistantToolCall, ToolValidationError> {
        guard let reminderId = nonEmpty(args["reminder_id"]) else { return .failure(.missingField("reminder_id")) }
        return .success(.remindersComplete(reminderId: reminderId))
    }

    // MARK: - Contacts

    private func validateContactsSearch(_ args: [String: String]) -> Result<AssistantToolCall, ToolValidationError> {
        guard let query = nonEmpty(args["query"]) else { return .failure(.missingField("query")) }
        return .success(.contactsSearch(query: query))
    }

    private func validateContactsCreate(_ args: [String: String]) -> Result<AssistantToolCall, ToolValidationError> {
        guard let firstName = nonEmpty(args["first_name"]) else { return .failure(.missingField("first_name")) }
        return .success(.contactsCreate(
            firstName: firstName,
            lastName: nonEmpty(args["last_name"]),
            phone: nonEmpty(args["phone"]),
            email: nonEmpty(args["email"]),
            company: nonEmpty(args["company"]),
            notes: nonEmpty(args["notes"])
        ))
    }

    // MARK: - Files

    private func validateFilesList(_ args: [String: String]) -> Result<AssistantToolCall, ToolValidationError> {
        guard let path = nonEmpty(args["path"]) else { return .failure(.missingField("path")) }
        return .success(.filesList(path: Self.normalizedContainedPath(path)))
    }

    private func validateFilesRead(_ args: [String: String]) -> Result<AssistantToolCall, ToolValidationError> {
        guard let path = nonEmpty(args["path"]) else { return .failure(.missingField("path")) }
        return .success(.filesRead(path: path))
    }

    private func validateFilesCreate(_ args: [String: String]) -> Result<AssistantToolCall, ToolValidationError> {
        // The model drifts between key names here — accept the observed aliases
        // rather than failing a correctly-routed call.
        let path = nonEmpty(args["path"]) ?? nonEmpty(args["name"])
            ?? nonEmpty(args["file_name"]) ?? nonEmpty(args["filename"])
        guard let path else { return .failure(.missingField("path")) }
        let content = nonEmpty(args["content"]) ?? nonEmpty(args["text"]) ?? nonEmpty(args["body"])
        guard let content else { return .failure(.missingField("content")) }
        return .success(.filesCreate(path: path, content: content))
    }

    private func validateFilesCreateFolder(_ args: [String: String]) -> Result<AssistantToolCall, ToolValidationError> {
        guard let path = nonEmpty(args["path"]) else { return .failure(.missingField("path")) }
        return .success(.filesCreateFolder(path: Self.normalizedContainedPath(path)))
    }

    private func validateFilesDelete(_ args: [String: String]) -> Result<AssistantToolCall, ToolValidationError> {
        guard let path = nonEmpty(args["path"]) else { return .failure(.missingField("path")) }
        return .success(.filesDelete(path: Self.normalizedContainedPath(path)))
    }

    /// The model drifts on path roots the same way it drifts on key names —
    /// "files/Foo" or a bare "Foo" for what the schema calls icloud/Foo. Coerce
    /// recognizable drift to a valid prefix instead of failing downstream.
    /// files_read / files_create are NOT normalized: an unprefixed path there
    /// intentionally falls back to the document picker.
    public static func normalizedContainedPath(_ raw: String) -> String {
        var path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while path.hasPrefix("/") { path.removeFirst() }
        let lowered = path.lowercased()
        if lowered.hasPrefix("local/") { return "local/" + path.dropFirst("local/".count) }
        if lowered.hasPrefix("icloud/") { return "icloud/" + path.dropFirst("icloud/".count) }
        for alias in ["files/", "file/", "icloud drive/"] where lowered.hasPrefix(alias) {
            return "icloud/" + path.dropFirst(alias.count)
        }
        if lowered.hasPrefix("documents/") {
            return "local/" + path.dropFirst("documents/".count)
        }
        if lowered == "files" || lowered == "icloud" || lowered == "icloud drive" { return "icloud/" }
        if lowered == "local" || lowered == "documents" { return "local/" }
        return "icloud/" + path
    }

    // MARK: - Clipboard

    private func validateClipboardWrite(_ args: [String: String]) -> Result<AssistantToolCall, ToolValidationError> {
        guard let content = nonEmpty(args["content"]) else { return .failure(.missingField("content")) }
        return .success(.clipboardWrite(content: content))
    }

    // MARK: - Notifications

    private func validateNotificationSchedule(_ args: [String: String], userInput: String) -> Result<AssistantToolCall, ToolValidationError> {
        guard let title = nonEmpty(args["title"]) else { return .failure(.missingField("title")) }
        // A title-only notification is fine — don't fail the call over copy.
        let body = nonEmpty(args["body"]) ?? nonEmpty(args["message"]) ?? title

        let triggerDate: Date
        switch resolveDate(iso: args["trigger_date"], userInput: userInput, field: "trigger_date") {
        case .failure(let error): return .failure(error)
        case .success(.some(let date)): triggerDate = date
        case .success(.none): return .failure(.missingField("trigger_date"))
        }

        return .success(.notificationSchedule(
            title: title,
            body: body,
            triggerDate: triggerDate,
            identifier: nonEmpty(args["identifier"])
        ))
    }

    private func validateNotificationCancel(_ args: [String: String]) -> Result<AssistantToolCall, ToolValidationError> {
        guard let identifier = nonEmpty(args["identifier"]) else { return .failure(.missingField("identifier")) }
        return .success(.notificationCancel(identifier: identifier))
    }

    // MARK: - System

    private func validateWebFetch(_ args: [String: String]) -> Result<AssistantToolCall, ToolValidationError> {
        guard let url = nonEmpty(args["url"]) else { return .failure(.missingField("url")) }
        return .success(.webFetch(url: url))
    }

    private func validateOpenUrl(_ args: [String: String]) -> Result<AssistantToolCall, ToolValidationError> {
        guard let url = nonEmpty(args["url"]) else { return .failure(.missingField("url")) }
        return .success(.openUrl(url: url))
    }

    // MARK: - Helpers

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// Resolves a date argument model-first, falling back to the natural-language
    /// parser on the original phrase. Returns `.success(nil)` only when no date was
    /// given at all (valid for optional fields); a present-but-unusable value with
    /// no future fallback fails as `badDate`/`pastDate`.
    private func resolveDate(iso: String?, userInput: String, field: String) -> Result<Date?, ToolValidationError> {
        let raw = nonEmpty(iso)
        if let raw, let parsed = parseDate(raw) {
            if parsed > now() { return .success(parsed) }
            if let nl = naturalFutureDate(from: userInput) { return .success(nl) }
            return .failure(.pastDate(field: field, value: raw))
        }
        if let nl = naturalFutureDate(from: userInput) { return .success(nl) }
        if let raw { return .failure(.badDate(field: field, value: raw)) }
        return .success(nil)
    }

    private func naturalFutureDate(from phrase: String) -> Date? {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let date = resolveNaturalDate(trimmed, now()) else { return nil }
        if date > now() { return date }
        // "at 8pm" said after 8pm means the NEXT 8pm: NSDataDetector anchors
        // bare times to today, so roll a just-past time forward one day.
        if date > now().addingTimeInterval(-86_400) {
            return calendar.date(byAdding: .day, value: 1, to: date)
        }
        return nil
    }

    public static func resolveRelativeTime(in text: String, now: Date) -> Date? {
        let lower = text.lowercased()

        let wordMap: [String: Int] = [
            "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
            "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
            "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
            "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20,
            "twenty-five": 25, "thirty": 30, "forty-five": 45, "forty": 40, "fifty": 50, "sixty": 60, "ninety": 90,
        ]

        let patterns = [
            #"in\s+(\w+(?:-\w+)?)\s+(minute|hour|day|week)s?"#,
            #"(\w+(?:-\w+)?)\s+(minute|hour|day|week)s?\s+from\s+now"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(lower.startIndex..., in: lower)
            guard let match = regex.firstMatch(in: lower, range: range),
                  let numRange = Range(match.range(at: 1), in: lower),
                  let unitRange = Range(match.range(at: 2), in: lower) else { continue }

            let numString = String(lower[numRange])
            let unit = String(lower[unitRange])

            guard let amount = Int(numString) ?? wordMap[numString] else { continue }

            let seconds: TimeInterval
            switch unit {
            case "minute": seconds = TimeInterval(amount) * 60
            case "hour": seconds = TimeInterval(amount) * 3600
            case "day": seconds = TimeInterval(amount) * 86400
            case "week": seconds = TimeInterval(amount) * 604800
            default: continue
            }

            return now.addingTimeInterval(seconds)
        }

        if lower.contains("half an hour") || lower.contains("half hour") {
            return now.addingTimeInterval(1800)
        }
        if lower.range(of: #"\bin an hour\b"#, options: .regularExpression) != nil {
            return now.addingTimeInterval(3600)
        }

        return nil
    }

    public static func detectDate(in text: String) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        return detector.firstMatch(in: text, options: [], range: range)?.date
    }

    private func parseDate(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let formats = [
            "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm", "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'h:mm a", "yyyy-MM-dd h:mm a",
            "yyyy-MM-dd"
        ]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.calendar = calendar
        df.timeZone = timeZone
        for format in formats {
            df.dateFormat = format
            if let date = df.date(from: trimmed) { return date }
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: trimmed) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: trimmed) { return date }
        return nil
    }
}
