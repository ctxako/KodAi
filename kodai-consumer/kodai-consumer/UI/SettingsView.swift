import SwiftUI
import EventKit
import Contacts
import UserNotifications

struct SettingsView: View {
    @State private var calendarStatus = ""
    @State private var remindersStatus = ""
    @State private var contactsStatus = ""
    @State private var notificationsStatus = ""

    @State private var defaultCalendar = "—"
    @State private var defaultReminderList = "—"
    private let timezone = TimeZone.current.identifier

    var body: some View {
        NavigationStack {
            List {
                Section("Permissions") {
                    permissionRow(icon: "calendar", color: .red, name: "Calendar", status: calendarStatus)
                    permissionRow(icon: "checklist", color: .blue, name: "Reminders", status: remindersStatus)
                    permissionRow(icon: "person.crop.circle", color: .green, name: "Contacts", status: contactsStatus)
                    permissionRow(icon: "bell.badge", color: .yellow, name: "Notifications", status: notificationsStatus)
                }

                Section("Agent Context") {
                    contextRow(label: "Default Calendar", value: defaultCalendar)
                    contextRow(label: "Default Reminder List", value: defaultReminderList)
                    contextRow(label: "Timezone", value: timezone)
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                            .foregroundStyle(.secondary)
                    }
                    Text("All on-device. No tracking.")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .task { await refresh() }
        }
        .preferredColorScheme(.dark)
    }

    private func permissionRow(icon: String, color: Color, name: String, status: String) -> some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 24)
                Text(name)
                    .foregroundStyle(.primary)
                Spacer()
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(statusColor(status))
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func contextRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "Granted": return .green
        case "Denied": return .red
        default: return .secondary
        }
    }

    private func refresh() async {
        let calAuth = EKEventStore.authorizationStatus(for: .event)
        calendarStatus = (calAuth == .fullAccess || calAuth == .writeOnly) ? "Granted" : calAuth == .denied ? "Denied" : "Not Requested"

        let remAuth = EKEventStore.authorizationStatus(for: .reminder)
        remindersStatus = remAuth == .fullAccess ? "Granted" : remAuth == .denied ? "Denied" : "Not Requested"

        let conAuth = CNContactStore.authorizationStatus(for: .contacts)
        contactsStatus = conAuth == .authorized ? "Granted" : conAuth == .denied ? "Denied" : "Not Requested"

        let notSettings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsStatus = notSettings.authorizationStatus == .authorized ? "Granted" : notSettings.authorizationStatus == .denied ? "Denied" : "Not Requested"

        let store = EKEventStore()
        defaultCalendar = store.defaultCalendarForNewEvents?.title ?? "—"
        if let remCal = store.defaultCalendarForNewReminders() {
            defaultReminderList = remCal.title
        }
    }
}
