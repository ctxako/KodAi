//
//  accountabilitysettings.swift
//  kodai_macos
//
//  J0 (jarvis-plan): settings for the daily rhythm (morning brief / evening
//  debrief) and the nudge policy. Storage-key namespace + the Rhythm tab UI.
//  The BriefingEngine and slip scheduler (J1/J3) read these values.
//

import ServiceManagement
import SwiftUI

// MARK: - Nudge policy

/// How proactive Kodai may be outside the scheduled daily touchpoints.
/// Locked direction: scheduled briefings plus slipping-commitment nudges only.
enum NudgePolicy: String, CaseIterable, Identifiable {
    case off = "off"
    case scheduledOnly = "scheduledOnly"
    case scheduledAndSlipping = "scheduledAndSlipping"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .scheduledOnly: return "Scheduled only"
        case .scheduledAndSlipping: return "Scheduled + slipping"
        }
    }
}

// MARK: - Storage keys & defaults

enum AccountabilitySettings {
    static let rhythmEnabledKey = "jarvis.rhythmEnabled"
    static let morningBriefMinutesKey = "jarvis.morningBriefMinutes"
    static let eveningDebriefMinutesKey = "jarvis.eveningDebriefMinutes"
    static let nudgePolicyKey = "jarvis.nudgePolicy"
    static let maxNudgesPerDayKey = "jarvis.maxNudgesPerDay"
    static let quietHoursStartMinutesKey = "jarvis.quietHoursStartMinutes"
    static let quietHoursEndMinutesKey = "jarvis.quietHoursEndMinutes"

    /// Times are stored as minutes from midnight, local time.
    static let defaultMorningBriefMinutes = 8 * 60          // 08:00
    static let defaultEveningDebriefMinutes = 21 * 60 + 30  // 21:30
    static let defaultNudgePolicy = NudgePolicy.scheduledAndSlipping
    static let defaultMaxNudgesPerDay = 3
    static let defaultQuietHoursStartMinutes = 22 * 60      // 22:00
    static let defaultQuietHoursEndMinutes = 8 * 60         // 08:00

    /// True when `minutes` (from midnight) falls inside the quiet-hours
    /// window; the window may wrap past midnight (e.g. 22:00 → 08:00).
    nonisolated static func isQuietTime(
        minutes: Int,
        quietStart: Int,
        quietEnd: Int
    ) -> Bool {
        guard quietStart != quietEnd else { return false }
        if quietStart < quietEnd {
            return minutes >= quietStart && minutes < quietEnd
        }
        return minutes >= quietStart || minutes < quietEnd
    }
}

// MARK: - Rhythm settings tab

struct RhythmSettingsTabView: View {
    @Environment(\.kodaiTheme) private var theme

    @AppStorage(AccountabilitySettings.rhythmEnabledKey)
    private var rhythmEnabled = false

    @AppStorage(AccountabilitySettings.morningBriefMinutesKey)
    private var morningBriefMinutes = AccountabilitySettings.defaultMorningBriefMinutes

    @AppStorage(AccountabilitySettings.eveningDebriefMinutesKey)
    private var eveningDebriefMinutes = AccountabilitySettings.defaultEveningDebriefMinutes

    @AppStorage(AccountabilitySettings.nudgePolicyKey)
    private var nudgePolicyRawValue = AccountabilitySettings.defaultNudgePolicy.rawValue

    @AppStorage(AccountabilitySettings.maxNudgesPerDayKey)
    private var maxNudgesPerDay = AccountabilitySettings.defaultMaxNudgesPerDay

    @AppStorage(AccountabilitySettings.quietHoursStartMinutesKey)
    private var quietHoursStartMinutes = AccountabilitySettings.defaultQuietHoursStartMinutes

    @AppStorage(AccountabilitySettings.quietHoursEndMinutesKey)
    private var quietHoursEndMinutes = AccountabilitySettings.defaultQuietHoursEndMinutes

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingRow("Daily rhythm") {
                Toggle("Daily rhythm", isOn: $rhythmEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .accessibilityIdentifier("settings.rhythmEnabled")
            }

            rowDivider

            settingRow("Start at login") {
                Toggle("Start at login", isOn: loginItemBinding)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .accessibilityIdentifier("settings.launchAtLogin")
            }

            rowDivider

            Group {
                settingRow("Morning brief") {
                    timePicker("Morning brief", minutes: $morningBriefMinutes)
                }

                rowDivider

                settingRow("Evening debrief") {
                    timePicker("Evening debrief", minutes: $eveningDebriefMinutes)
                }

                rowDivider

                settingRow("Nudges") {
                    Picker("Nudges", selection: $nudgePolicyRawValue) {
                        ForEach(NudgePolicy.allCases) { policy in
                            Text(policy.displayName).tag(policy.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .accessibilityIdentifier("settings.nudgePolicy")
                }

                rowDivider

                settingRow("Max nudges / day") {
                    Stepper(value: $maxNudgesPerDay, in: 1...10) {
                        Text("\(maxNudgesPerDay)")
                            .font(.system(size: 13, design: .monospaced))
                    }
                    .controlSize(.small)
                }

                rowDivider

                settingRow("Quiet hours") {
                    HStack(spacing: 6) {
                        timePicker("Quiet from", minutes: $quietHoursStartMinutes)
                        Text("–")
                            .foregroundStyle(.secondary)
                        timePicker("Quiet until", minutes: $quietHoursEndMinutes)
                    }
                }
            }
            .disabled(!rhythmEnabled)
            .opacity(rhythmEnabled ? 1 : 0.45)

            Text("Kodai speaks up at the scheduled times — and, if allowed, when a commitment is about to slip. Never during quiet hours.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(theme.secondaryText.opacity(0.82))
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)
        }
        .padding(.vertical, 4)
        .onChange(of: rhythmEnabled) { RhythmScheduler.shared.syncSchedule() }
        .onChange(of: morningBriefMinutes) { RhythmScheduler.shared.syncSchedule() }
        .onChange(of: eveningDebriefMinutes) { RhythmScheduler.shared.syncSchedule() }
    }

    /// SMAppService has no observable state, so the toggle drives it
    /// imperatively and mirrors the result back into local state.
    private var loginItemBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { enable in
                do {
                    if enable {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    launchAtLogin = enable
                } catch {
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }
        )
    }

    private var rowDivider: some View {
        Divider()
            .opacity(0.10)
            .padding(.horizontal, 16)
    }

    private func settingRow(_ label: String, @ViewBuilder control: () -> some View) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, design: .rounded))
            Spacer()
            control()
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
    }

    private func timePicker(_ label: String, minutes: Binding<Int>) -> some View {
        DatePicker(
            label,
            selection: timeBinding(minutes),
            displayedComponents: .hourAndMinute
        )
        .datePickerStyle(.field)
        .labelsHidden()
        .frame(width: 78)
    }

    /// Bridges minutes-from-midnight storage to a DatePicker's Date value.
    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding<Date>(
            get: {
                let calendar = Calendar.current
                let startOfDay = calendar.startOfDay(for: .now)
                return calendar.date(
                    byAdding: .minute,
                    value: minutes.wrappedValue,
                    to: startOfDay
                ) ?? startOfDay
            },
            set: { newDate in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                minutes.wrappedValue = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        )
    }
}
