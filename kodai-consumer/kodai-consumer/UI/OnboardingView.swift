import SwiftUI
import EventKit
import Contacts
import UserNotifications

struct OnboardingView: View {
    @Binding var isComplete: Bool
    @State private var showSplash = true
    @State private var page = 0

    var body: some View {
        if showSplash {
            SplashView {
                withAnimation(.easeInOut(duration: 0.35)) { showSplash = false }
            }
            .transition(.opacity)
            .preferredColorScheme(.dark)
        } else {
            ZStack {
                CanvasBackground()

                TabView(selection: $page) {
                    welcomePage.tag(0)
                    permissionsPage.tag(1)
                    readyPage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .animation(.easeInOut(duration: 0.3), value: page)
            }
            .transition(.opacity)
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Welcome

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "pawprint.fill")
                .font(.system(size: 56))
                .foregroundStyle(.white.opacity(0.85))

            Text("kodai")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)

            Text("Your private AI agent. Everything runs on your phone. Nothing leaves.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            Button {
                withAnimation { page = 1 }
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Permissions

    private var permissionsPage: some View {
        PermissionsPageContent {
            withAnimation { page = 2 }
        }
    }

    // MARK: - Ready

    private var readyPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("You're all set.")
                .font(.title.bold())
                .foregroundStyle(.white)

            Text("kodai works offline, on-device, with zero tracking.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button {
                isComplete = true
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Permissions page (extracted so @State works inside TabView)

private struct PermissionsPageContent: View {
    var onContinue: () -> Void

    @State private var calendarStatus: PermStatus = .notRequested
    @State private var remindersStatus: PermStatus = .notRequested
    @State private var contactsStatus: PermStatus = .notRequested
    @State private var notificationsStatus: PermStatus = .notRequested

    private let eventStore = EKEventStore()
    private let contactStore = CNContactStore()

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("Let kodai help you with…")
                .font(.title2.bold())
                .foregroundStyle(.white)

            VStack(spacing: 12) {
                permissionCard(
                    icon: "calendar",
                    color: .red,
                    name: "Calendar",
                    explanation: "Create events, check your schedule, manage appointments",
                    status: calendarStatus
                ) {
                    await requestCalendar()
                }

                permissionCard(
                    icon: "checklist",
                    color: .blue,
                    name: "Reminders",
                    explanation: "Set reminders, manage to-do lists, mark tasks complete",
                    status: remindersStatus
                ) {
                    await requestReminders()
                }

                permissionCard(
                    icon: "person.crop.circle",
                    color: .green,
                    name: "Contacts",
                    explanation: "Search contacts, add new people",
                    status: contactsStatus
                ) {
                    await requestContacts()
                }

                permissionCard(
                    icon: "bell.badge",
                    color: .yellow,
                    name: "Notifications",
                    explanation: "Send you reminders and alerts at specific times",
                    status: notificationsStatus
                ) {
                    await requestNotifications()
                }
            }
            .padding(.horizontal, 20)

            Spacer()

            Button {
                onContinue()
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)

            Button {
                onContinue()
            } label: {
                Text("Skip for now")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 32)
        }
        .task { await checkExisting() }
    }

    // MARK: - Card

    private func permissionCard(
        icon: String, color: Color, name: String,
        explanation: String, status: PermStatus,
        request: @escaping () async -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline).foregroundStyle(.white)
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            statusIndicator(status, request: request)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(explanation)")
    }

    @ViewBuilder
    private func statusIndicator(_ status: PermStatus, request: @escaping () async -> Void) -> some View {
        switch status {
        case .granted:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)
        case .denied:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red.opacity(0.7))
                .font(.title3)
        case .notRequested:
            Button {
                Task { await request() }
            } label: {
                Text("Allow")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(ConsumerPalette.accentBlue, in: Capsule())
            }
        }
    }

    // MARK: - Requests

    private func requestCalendar() async {
        let granted = (try? await eventStore.requestWriteOnlyAccessToEvents()) ?? false
        calendarStatus = granted ? .granted : .denied
    }

    private func requestReminders() async {
        let granted = (try? await eventStore.requestFullAccessToReminders()) ?? false
        remindersStatus = granted ? .granted : .denied
    }

    private func requestContacts() async {
        do {
            try await contactStore.requestAccess(for: .contacts)
            contactsStatus = .granted
        } catch {
            contactsStatus = .denied
        }
    }

    private func requestNotifications() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        notificationsStatus = granted ? .granted : .denied
    }

    // MARK: - Check existing

    private func checkExisting() async {
        let calAuth = EKEventStore.authorizationStatus(for: .event)
        if calAuth == .fullAccess || calAuth == .writeOnly { calendarStatus = .granted }
        else if calAuth == .denied { calendarStatus = .denied }

        let remAuth = EKEventStore.authorizationStatus(for: .reminder)
        if remAuth == .fullAccess { remindersStatus = .granted }
        else if remAuth == .denied { remindersStatus = .denied }

        let conAuth = CNContactStore.authorizationStatus(for: .contacts)
        if conAuth == .authorized { contactsStatus = .granted }
        else if conAuth == .denied { contactsStatus = .denied }

        let notSettings = await UNUserNotificationCenter.current().notificationSettings()
        if notSettings.authorizationStatus == .authorized { notificationsStatus = .granted }
        else if notSettings.authorizationStatus == .denied { notificationsStatus = .denied }
    }
}

// MARK: - Permission status enum

enum PermStatus {
    case notRequested, granted, denied
}
