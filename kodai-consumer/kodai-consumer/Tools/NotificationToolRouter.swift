import Foundation
import UserNotifications
import KodaiKernel

struct NotificationToolRouter: ToolRouter {
    let confirm: (AssistantToolCall) async -> ConfirmDecision

    func execute(_ call: AssistantToolCall) async -> ToolResult {
        switch call {
        case let .notificationSchedule(title, body, triggerDate, identifier):
            let decision = await confirm(call)
            guard case .accept = decision else {
                return .failure(tool: "notification_schedule", error: "cancelled_by_user")
            }
            return await scheduleNotification(title: title, body: body, triggerDate: triggerDate, identifier: identifier)

        case let .notificationCancel(identifier):
            let decision = await confirm(call)
            guard case .accept = decision else {
                return .failure(tool: "notification_cancel", error: "cancelled_by_user")
            }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
            return .ok(tool: "notification_cancel", result: ["identifier": identifier, "cancelled": "true"])

        default:
            return .failure(tool: call.toolName, error: "not_implemented")
        }
    }

    private func scheduleNotification(title: String, body: String, triggerDate: Date, identifier: String?) async -> ToolResult {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            guard granted else {
                return .failure(tool: "notification_schedule", error: "notifications_access_denied")
            }
        } catch {
            return .failure(tool: "notification_schedule", error: "notifications_access_denied")
        }

        guard triggerDate > Date() else {
            return .failure(tool: "notification_schedule", error: "trigger_date_in_past")
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let id = identifier ?? UUID().uuidString

        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        do {
            try await center.add(request)
            return .ok(tool: "notification_schedule", result: ["identifier": id, "title": title])
        } catch {
            return .failure(tool: "notification_schedule", error: error.localizedDescription)
        }
    }
}
