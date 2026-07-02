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

                Section("Toolflows") {
                    NavigationLink {
                        ToolflowsView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "bolt.fill")
                                .foregroundStyle(.yellow)
                                .frame(width: 24)
                            Text("Saved Toolflows")
                        }
                    }
                    .accessibilityHint("One-tap tasks for the widget and Siri")
                }

                Section("Help") {
                    NavigationLink {
                        HowToView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(.teal)
                                .frame(width: 24)
                            Text("How to Use kodai")
                        }
                    }
                    .accessibilityHint("Tips and example prompts for the kodai agent")
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Self.versionString)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        if let url = Self.feedbackMailURL {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "envelope")
                                .foregroundStyle(.blue)
                                .frame(width: 24)
                            Text("Send Feedback")
                                .foregroundStyle(.primary)
                        }
                    }
                    .accessibilityHint("Opens an email draft to the kodai team")
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

    static var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    /// Pre-filled feedback mail with the context a bug report needs. Plain
    /// mailto keeps the no-dependencies promise (no MessageUI sheet state).
    static var feedbackMailURL: URL? {
        let device = UIDevice.current
        let body = """


        —
        kodai \(versionString)
        \(device.model), iOS \(device.systemVersion)
        """
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "15ctxa@gmail.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "kodai feedback"),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
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
