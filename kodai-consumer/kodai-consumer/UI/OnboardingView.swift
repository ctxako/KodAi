import SwiftUI
import EventKit

struct OnboardingView: View {
    @Binding var isComplete: Bool
    @State private var showSplash = true
    @State private var page = 0
    @State private var calendarGranted = false
    @State private var remindersGranted = false
    @State private var requesting = false

    private let store = EKEventStore()

    var body: some View {
        if showSplash {
            SplashView {
                withAnimation(.easeInOut(duration: 0.35)) { showSplash = false }
            }
            .transition(.opacity)
            .preferredColorScheme(.dark)
        } else {
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    permissionsPage.tag(0)
                    readyPage.tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .animation(.easeInOut(duration: 0.3), value: page)
            }
            .background(Color(.systemBackground))
            .transition(.opacity)
        }
    }

    // MARK: - Pages

    private var permissionsPage: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Permissions")
                .font(.title.bold())
            Text("kodAI creates calendar events and reminders on your behalf. Grant access so it can act for you.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(spacing: 16) {
                permissionRow(
                    icon: "calendar",
                    title: "Calendar",
                    subtitle: "Create events",
                    granted: calendarGranted
                )
                permissionRow(
                    icon: "checklist",
                    title: "Reminders",
                    subtitle: "Create reminders and lists",
                    granted: remindersGranted
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            Button {
                Task { await requestPermissions() }
            } label: {
                Text(anyGranted ? "Continue" : "Allow access")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(requesting)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .task { await checkExistingPermissions() }
    }

    private var readyPage: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("You're all set")
                .font(.title.bold())
            Text("Ask kodAI to set reminders, add calendar events, save files, or manage lists.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button {
                isComplete = true
            } label: {
                Text("Start using kodAI")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Components

    private func permissionRow(icon: String, title: String, subtitle: String, granted: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 36)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Permissions

    private var anyGranted: Bool { calendarGranted || remindersGranted }

    private func checkExistingPermissions() async {
        calendarGranted = EKEventStore.authorizationStatus(for: .event) == .fullAccess
            || EKEventStore.authorizationStatus(for: .event) == .writeOnly
        remindersGranted = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    private func requestPermissions() async {
        requesting = true
        defer { requesting = false }

        if !calendarGranted {
            calendarGranted = (try? await store.requestWriteOnlyAccessToEvents()) ?? false
        }
        if !remindersGranted {
            remindersGranted = (try? await store.requestFullAccessToReminders()) ?? false
        }

        page = 1
    }
}
