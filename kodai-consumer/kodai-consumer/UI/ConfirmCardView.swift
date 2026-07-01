import SwiftUI
import KodaiKernel

struct ConfirmCardView: View {
    let call: AssistantToolCall
    let confidence: ParseConfidence
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.title3.bold())
                if confidence == .low {
                    Text("Double-check this looks right")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(details.enumerated()), id: \.offset) { _, detail in
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(spacing: 12) {
                Button(role: .cancel, action: onCancel) {
                    Text("Cancel").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Cancel")

                Button(action: onConfirm) {
                    Text("Confirm").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Confirm action")
            }
        }
        .padding(24)
        .preferredColorScheme(.dark)
    }

    private var icon: String {
        switch call {
        case .calendarCreateEvent: return "calendar.badge.plus"
        case .calendarListEvents: return "calendar"
        case .calendarDeleteEvent: return "calendar.badge.minus"
        case .remindersCreate: return "checklist"
        case .remindersList: return "checklist.checked"
        case .remindersComplete: return "checkmark.circle"
        case .contactsSearch: return "person.crop.circle"
        case .contactsCreate: return "person.crop.circle.badge.plus"
        case .filesList: return "folder"
        case .filesRead: return "doc.text.magnifyingglass"
        case .filesCreate: return "doc.text"
        case .filesCreateFolder: return "folder.badge.plus"
        case .filesDelete: return "trash"
        case .clipboardRead: return "doc.on.clipboard"
        case .clipboardWrite: return "doc.on.clipboard.fill"
        case .notificationSchedule: return "bell.badge"
        case .notificationCancel: return "bell.slash"
        case .webFetch: return "globe"
        case .openUrl: return "arrow.up.forward.square"
        }
    }

    private var iconColor: Color {
        switch call {
        case .calendarCreateEvent, .calendarListEvents, .calendarDeleteEvent: return .red
        case .remindersCreate, .remindersList, .remindersComplete: return .blue
        case .contactsSearch, .contactsCreate: return .green
        case .filesCreate, .filesCreateFolder, .filesList: return .purple
        case .filesRead: return .teal
        case .filesDelete: return .orange
        case .clipboardRead, .clipboardWrite: return .indigo
        case .notificationSchedule, .notificationCancel: return .yellow
        case .webFetch, .openUrl: return .cyan
        }
    }

    private var title: String {
        switch call {
        case .calendarCreateEvent: return "New calendar event"
        case .calendarListEvents: return "Check calendar"
        case .calendarDeleteEvent: return "Delete event"
        case .remindersCreate: return "New reminder"
        case .remindersList: return "Check reminders"
        case .remindersComplete: return "Complete reminder"
        case .contactsSearch: return "Search contacts"
        case .contactsCreate: return "New contact"
        case .filesList: return "List files"
        case .filesRead: return "Read file"
        case .filesCreate: return "Save file"
        case .filesCreateFolder: return "Create folder"
        case .filesDelete: return "Delete file"
        case .clipboardRead: return "Read clipboard"
        case .clipboardWrite: return "Copy to clipboard"
        case .notificationSchedule: return "Schedule notification"
        case .notificationCancel: return "Cancel notification"
        case .webFetch: return "Fetch URL"
        case .openUrl: return "Open URL"
        }
    }

    private var details: [String] {
        switch call {
        case let .calendarCreateEvent(t, start, end, location, notes, calendarName, allDay):
            var lines = [t, "Starts \(format(start))"]
            if let end { lines.append("Ends \(format(end))") }
            if let location { lines.append("At \(location)") }
            if let calendarName { lines.append("Calendar: \(calendarName)") }
            if allDay == true { lines.append("All day") }
            if let notes { lines.append(notes) }
            return lines
        case let .calendarListEvents(start, end, calendarName):
            var lines = ["\(format(start)) – \(format(end))"]
            if let calendarName { lines.append("Calendar: \(calendarName)") }
            return lines
        case let .calendarDeleteEvent(eventId):
            return ["Event: \(eventId)"]
        case let .remindersCreate(t, due, notes, list, priority):
            var lines = [t]
            if let due { lines.append("Due \(format(due))") }
            if let list { lines.append("List: \(list)") }
            if let priority { lines.append("Priority: \(priority)") }
            if let notes { lines.append(notes) }
            return lines
        case let .remindersList(list, completed):
            var lines = [completed ? "completed" : "pending"]
            if let list { lines.append("List: \(list)") }
            return lines
        case let .remindersComplete(reminderId):
            return ["Reminder: \(reminderId)"]
        case let .contactsSearch(query):
            return ["Search: \(query)"]
        case let .contactsCreate(firstName, lastName, phone, email, company, notes):
            var lines = [firstName]
            if let lastName { lines.append(lastName) }
            if let phone { lines.append(phone) }
            if let email { lines.append(email) }
            if let company { lines.append(company) }
            if let notes { lines.append(notes) }
            return lines
        case let .filesList(path):
            return [path]
        case let .filesRead(path):
            return [path]
        case let .filesCreate(path, content):
            let preview = content.count > 80 ? String(content.prefix(80)) + "…" : content
            return [path, preview]
        case let .filesCreateFolder(path):
            return [path]
        case let .filesDelete(path):
            return [path]
        case .clipboardRead:
            return ["Reading clipboard contents"]
        case let .clipboardWrite(content):
            let preview = content.count > 80 ? String(content.prefix(80)) + "…" : content
            return [preview]
        case let .notificationSchedule(title, body, triggerDate, _):
            return [title, body, format(triggerDate)]
        case let .notificationCancel(identifier):
            return ["ID: \(identifier)"]
        case let .webFetch(url):
            return [url]
        case let .openUrl(url):
            return [url]
        }
    }

    private func format(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
