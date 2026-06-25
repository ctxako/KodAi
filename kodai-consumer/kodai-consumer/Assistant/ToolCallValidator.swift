//
//  ToolCallValidator.swift
//  kodai-consumer
//
//  Turns a parsed `RawToolCall` into a typed, checked `AssistantToolCall`,
//  or an error the caller can use to drive a single silent retry. Offloads
//  the model's weak spot (time) to dumb code: dates must parse AND be in the
//  future; calendar end must be after start.
//

import Foundation

enum ToolValidationError: Error, Equatable {
    case unknownTool(String)
    case missingField(String)
    case badDate(field: String, value: String)
    case pastDate(field: String, value: String)
    case endBeforeStart
}

struct ToolCallValidator {
    var now: () -> Date = Date.init
    var calendar: Calendar = .current
    var timeZone: TimeZone = .current

    func validate(_ raw: RawToolCall) -> Result<AssistantToolCall, ToolValidationError> {
        guard let tool = AssistantToolName(rawValue: raw.name) else {
            return .failure(.unknownTool(raw.name))
        }

        switch tool {
        case .createReminder:
            return validateCreateReminder(raw.arguments)
        case .createCalendarEvent:
            return validateCreateCalendarEvent(raw.arguments)
        case .addToList:
            return validateAddToList(raw.arguments)
        case .saveFile:
            return validateSaveFile(raw.arguments)
        case .readFile:
            return validateReadFile(raw.arguments)
        }
    }

    // MARK: - Per-tool

    private func validateCreateReminder(_ args: [String: String]) -> Result<AssistantToolCall, ToolValidationError> {
        guard let title = nonEmpty(args["title"]) else { return .failure(.missingField("title")) }

        let due: Date?
        switch optionalFutureDate(args["due_iso"], field: "due_iso") {
        case .failure(let error): return .failure(error)
        case .success(let date): due = date
        }

        return .success(.createReminder(
            title: title,
            due: due,
            list: nonEmpty(args["list"]),
            notes: nonEmpty(args["notes"])
        ))
    }

    private func validateCreateCalendarEvent(_ args: [String: String]) -> Result<AssistantToolCall, ToolValidationError> {
        guard let title = nonEmpty(args["title"]) else { return .failure(.missingField("title")) }
        guard let startRaw = nonEmpty(args["start_iso"]) else { return .failure(.missingField("start_iso")) }
        guard let start = parseDate(startRaw) else { return .failure(.badDate(field: "start_iso", value: startRaw)) }
        guard start > now() else { return .failure(.pastDate(field: "start_iso", value: startRaw)) }

        var end: Date?
        if let endRaw = nonEmpty(args["end_iso"]) {
            guard let parsedEnd = parseDate(endRaw) else { return .failure(.badDate(field: "end_iso", value: endRaw)) }
            guard parsedEnd > start else { return .failure(.endBeforeStart) }
            end = parsedEnd
        }

        return .success(.createCalendarEvent(
            title: title,
            start: start,
            end: end,
            location: nonEmpty(args["location"]),
            notes: nonEmpty(args["notes"])
        ))
    }

    private func validateAddToList(_ args: [String: String]) -> Result<AssistantToolCall, ToolValidationError> {
        guard let list = nonEmpty(args["list"]) else { return .failure(.missingField("list")) }
        guard let item = nonEmpty(args["item"]) else { return .failure(.missingField("item")) }
        return .success(.addToList(list: list, item: item))
    }

    private func validateSaveFile(_ args: [String: String]) -> Result<AssistantToolCall, ToolValidationError> {
        guard let name = nonEmpty(args["name"]) else { return .failure(.missingField("name")) }
        guard let content = nonEmpty(args["content"]) else { return .failure(.missingField("content")) }
        return .success(.saveFile(name: name, content: content))
    }

    private func validateReadFile(_ args: [String: String]) -> Result<AssistantToolCall, ToolValidationError> {
        guard let purpose = nonEmpty(args["purpose"]) else { return .failure(.missingField("purpose")) }
        return .success(.readFile(purpose: purpose))
    }

    // MARK: - Helpers

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// nil → ok (absent). present-but-unparseable → badDate. past → pastDate.
    private func optionalFutureDate(_ value: String?, field: String) -> Result<Date?, ToolValidationError> {
        guard let raw = nonEmpty(value) else { return .success(nil) }
        guard let date = parseDate(raw) else { return .failure(.badDate(field: field, value: raw)) }
        guard date > now() else { return .failure(.pastDate(field: field, value: raw)) }
        return .success(date)
    }

    private func parseDate(_ string: String) -> Date? {
        let formats = ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.calendar = calendar
        df.timeZone = timeZone
        for format in formats {
            df.dateFormat = format
            if let date = df.date(from: string) { return date }
        }
        return nil
    }
}
