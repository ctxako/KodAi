import Foundation
import KodaiKernel

struct ToolRouterDispatch: ToolRouter {
    let confirm: (AssistantToolCall) async -> ConfirmDecision
    let presentFilePicker: (FilePickerRequest) async -> FilePickerResult
    var onActivity: ((String) -> Void)?

    func execute(_ call: AssistantToolCall) async -> ToolResult {
        switch call {
        // Calendar & Reminders
        case .calendarCreateEvent, .calendarListEvents, .calendarDeleteEvent,
             .remindersCreate, .remindersList, .remindersComplete:
            return await eventKitRouter.execute(call)

        // Contacts
        case .contactsSearch, .contactsCreate:
            return await contactsRouter.execute(call)

        // Files
        case .filesList, .filesRead, .filesCreate, .filesCreateFolder, .filesDelete:
            return await fileRouter.execute(call)

        // Clipboard
        case .clipboardRead, .clipboardWrite:
            return await clipboardRouter.execute(call)

        // Notifications
        case .notificationSchedule, .notificationCancel:
            return await notificationRouter.execute(call)

        // System
        case .webFetch, .openUrl:
            return await systemRouter.execute(call)
        }
    }

    private var eventKitRouter: EventKitToolRouter {
        EventKitToolRouter(confirm: confirm, onActivity: onActivity)
    }

    private var contactsRouter: ContactsToolRouter {
        ContactsToolRouter(confirm: confirm)
    }

    private var fileRouter: FileToolRouter {
        FileToolRouter(presentPicker: presentFilePicker, confirm: confirm)
    }

    private var clipboardRouter: ClipboardToolRouter {
        ClipboardToolRouter(confirm: confirm)
    }

    private var notificationRouter: NotificationToolRouter {
        NotificationToolRouter(confirm: confirm)
    }

    private var systemRouter: SystemToolRouter {
        SystemToolRouter(confirm: confirm)
    }
}
