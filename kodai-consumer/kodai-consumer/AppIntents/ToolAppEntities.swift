//
//  ToolAppEntities.swift
//  kodai-consumer
//
//  AppEntity types returned by the write intents so Siri/Shortcuts can display
//  the created object and pass it to the next action. kodAI keeps no local
//  database for these (the writes go straight to EventKit / Contacts / etc.),
//  so these are transient result objects: the queries return nothing because
//  there is nothing to look up later. The `@Property` fields expose values as
//  Shortcuts output variables.
//

import Foundation
import AppIntents

// MARK: - Reminder

struct ReminderEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Reminder" }
    static var defaultQuery = ReminderEntityQuery()

    let id: String

    @Property(title: "Title")
    var title: String

    @Property(title: "Due Date")
    var dueDate: Date?

    @Property(title: "List")
    var listName: String?

    @Property(title: "Priority")
    var priority: String?

    init(id: String = UUID().uuidString, title: String, dueDate: Date?, listName: String?, priority: String? = nil) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.listName = listName
        self.priority = priority
    }

    var displayRepresentation: DisplayRepresentation {
        var subtitle: LocalizedStringResource?
        if let dueDate {
            subtitle = "Due \(dueDate.formatted(date: .abbreviated, time: .shortened))"
        } else if let listName {
            subtitle = "List: \(listName)"
        }
        return DisplayRepresentation(
            title: "\(title)",
            subtitle: subtitle,
            image: .init(systemName: "checklist")
        )
    }
}

struct ReminderEntityQuery: EntityQuery {
    func entities(for identifiers: [ReminderEntity.ID]) async throws -> [ReminderEntity] { [] }
    func suggestedEntities() async throws -> [ReminderEntity] { [] }
}

// MARK: - Calendar Event

struct CalendarEventEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Calendar Event" }
    static var defaultQuery = CalendarEventEntityQuery()

    let id: String

    @Property(title: "Title")
    var title: String

    @Property(title: "Start Date")
    var startDate: Date

    @Property(title: "Location")
    var location: String?

    init(id: String = UUID().uuidString, title: String, startDate: Date, location: String?) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.location = location
    }

    var displayRepresentation: DisplayRepresentation {
        let when = startDate.formatted(date: .abbreviated, time: .shortened)
        var subtitle: LocalizedStringResource = "\(when)"
        if let location { subtitle = "\(location) · \(when)" }
        return DisplayRepresentation(
            title: "\(title)",
            subtitle: subtitle,
            image: .init(systemName: "calendar")
        )
    }
}

struct CalendarEventEntityQuery: EntityQuery {
    func entities(for identifiers: [CalendarEventEntity.ID]) async throws -> [CalendarEventEntity] { [] }
    func suggestedEntities() async throws -> [CalendarEventEntity] { [] }
}

// MARK: - Contact

struct ContactEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Contact" }
    static var defaultQuery = ContactEntityQuery()

    let id: String

    @Property(title: "Name")
    var name: String

    @Property(title: "Phone")
    var phone: String?

    @Property(title: "Email")
    var email: String?

    @Property(title: "Company")
    var company: String?

    init(id: String = UUID().uuidString, name: String, phone: String?, email: String?, company: String?) {
        self.id = id
        self.name = name
        self.phone = phone
        self.email = email
        self.company = company
    }

    var displayRepresentation: DisplayRepresentation {
        var subtitle: LocalizedStringResource?
        if let phone { subtitle = "\(phone)" }
        else if let email { subtitle = "\(email)" }
        else if let company { subtitle = "\(company)" }
        return DisplayRepresentation(
            title: "\(name)",
            subtitle: subtitle,
            image: .init(systemName: "person.crop.circle")
        )
    }
}

struct ContactEntityQuery: EntityQuery {
    func entities(for identifiers: [ContactEntity.ID]) async throws -> [ContactEntity] { [] }
    func suggestedEntities() async throws -> [ContactEntity] { [] }
}

// MARK: - Notification

struct NotificationEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Notification" }
    static var defaultQuery = NotificationEntityQuery()

    let id: String

    @Property(title: "Title")
    var title: String

    @Property(title: "Body")
    var body: String

    @Property(title: "Trigger Date")
    var triggerDate: Date

    @Property(title: "Identifier")
    var identifier: String

    init(id: String = UUID().uuidString, title: String, body: String, triggerDate: Date, identifier: String) {
        self.id = id
        self.title = title
        self.body = body
        self.triggerDate = triggerDate
        self.identifier = identifier
    }

    var displayRepresentation: DisplayRepresentation {
        let when = triggerDate.formatted(date: .abbreviated, time: .shortened)
        return DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(when)",
            image: .init(systemName: "bell")
        )
    }
}

struct NotificationEntityQuery: EntityQuery {
    func entities(for identifiers: [NotificationEntity.ID]) async throws -> [NotificationEntity] { [] }
    func suggestedEntities() async throws -> [NotificationEntity] { [] }
}

// MARK: - File

struct FileEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "File" }
    static var defaultQuery = FileEntityQuery()

    let id: String

    @Property(title: "Name")
    var name: String

    @Property(title: "Path")
    var path: String

    @Property(title: "Size")
    var size: String?

    init(id: String = UUID().uuidString, name: String, path: String, size: String? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.size = size
    }

    var displayRepresentation: DisplayRepresentation {
        var subtitle: LocalizedStringResource?
        if let size { subtitle = "\(size)" }
        return DisplayRepresentation(
            title: "\(name)",
            subtitle: subtitle,
            image: .init(systemName: "doc")
        )
    }
}

struct FileEntityQuery: EntityQuery {
    func entities(for identifiers: [FileEntity.ID]) async throws -> [FileEntity] { [] }
    func suggestedEntities() async throws -> [FileEntity] { [] }
}
