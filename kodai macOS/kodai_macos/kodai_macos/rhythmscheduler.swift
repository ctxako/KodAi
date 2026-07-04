//
//  rhythmscheduler.swift
//  kodai_macos
//
//  J1 (jarvis-plan): schedules the daily rhythm notifications (morning brief,
//  evening debrief) via UNUserNotificationCenter and routes notification taps
//  into the app. Scheduled briefs fire at the user's chosen times — quiet
//  hours only constrain event-driven nudges (J3), never the times the user
//  picked themselves.
//

import AppKit
import Foundation
import KodaiCore
import Observation
import UserNotifications

@MainActor
@Observable
final class RhythmScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = RhythmScheduler()

    /// Set when the user taps a briefing notification (or a menu-bar
    /// shortcut); ContentView observes this and routes to the briefing view.
    var pendingBriefingKind: BriefingKind?

    private(set) var authorizationDenied = false

    private static let morningIdentifier = "jarvis.morningBrief"
    private static let eveningIdentifier = "jarvis.eveningDebrief"

    /// Call once at app start: claims the notification delegate and brings
    /// the pending schedule in line with current settings.
    func activate() {
        UNUserNotificationCenter.current().delegate = self
        syncSchedule()
    }

    /// Re-reads settings and reschedules (or clears) the daily notifications.
    /// Call after any Rhythm settings change.
    func syncSchedule() {
        let center = UNUserNotificationCenter.current()
        guard UserDefaults.standard.bool(forKey: AccountabilitySettings.rhythmEnabledKey) else {
            center.removePendingNotificationRequests(
                withIdentifiers: [Self.morningIdentifier, Self.eveningIdentifier]
            )
            return
        }

        Task {
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                authorizationDenied = !granted
                guard granted else { return }
                await scheduleDailyBriefings(center: center)
            } catch {
                authorizationDenied = true
            }
        }
    }

    private func scheduleDailyBriefings(center: UNUserNotificationCenter) async {
        center.removePendingNotificationRequests(
            withIdentifiers: [Self.morningIdentifier, Self.eveningIdentifier]
        )

        let morningMinutes = storedMinutes(
            key: AccountabilitySettings.morningBriefMinutesKey,
            fallback: AccountabilitySettings.defaultMorningBriefMinutes
        )
        let eveningMinutes = storedMinutes(
            key: AccountabilitySettings.eveningDebriefMinutesKey,
            fallback: AccountabilitySettings.defaultEveningDebriefMinutes
        )

        let requests = [
            briefingRequest(
                identifier: Self.morningIdentifier,
                kind: .morning,
                title: "Morning brief",
                body: "Your day, assembled — tasks, commitments, and yesterday's echo.",
                minutesFromMidnight: morningMinutes
            ),
            briefingRequest(
                identifier: Self.eveningIdentifier,
                kind: .evening,
                title: "Evening debrief",
                body: "Close the day: what moved, what slipped, two lines of reflection.",
                minutesFromMidnight: eveningMinutes
            )
        ]
        for request in requests {
            try? await center.add(request)
        }
    }

    private func briefingRequest(
        identifier: String,
        kind: BriefingKind,
        title: String,
        body: String,
        minutesFromMidnight: Int
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["kind": kind.rawValue]

        var components = DateComponents()
        components.hour = minutesFromMidnight / 60
        components.minute = minutesFromMidnight % 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }

    private func storedMinutes(key: String, fallback: Int) -> Int {
        UserDefaults.standard.object(forKey: key) as? Int ?? fallback
    }

    /// The briefing kind the current moment calls for: evening once we're
    /// past the debrief hour (or within 2h before it), morning otherwise.
    func naturalKind(now: Date = .now, calendar: Calendar = .current) -> BriefingKind {
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let eveningMinutes = storedMinutes(
            key: AccountabilitySettings.eveningDebriefMinutesKey,
            fallback: AccountabilitySettings.defaultEveningDebriefMinutes
        )
        return minutes >= eveningMinutes - 120 ? .evening : .morning
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let kindRawValue = response.notification.request.content.userInfo["kind"] as? String
        await MainActor.run {
            self.pendingBriefingKind = kindRawValue.flatMap(BriefingKind.init(rawValue:)) ?? .morning
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
