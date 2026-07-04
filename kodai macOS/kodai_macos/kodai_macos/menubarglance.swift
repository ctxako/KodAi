//
//  menubarglance.swift
//  kodai_macos
//
//  J1 (jarvis-plan): the menu-bar today glance — due tasks, open
//  commitments, and one-click entry into the briefing. Also what keeps the
//  app resident so the scheduled rhythm notifications actually fire.
//

import KodaiCore
import SwiftData
import SwiftUI

struct MenuBarGlanceView: View {
    @Environment(\.openWindow) private var openWindow

    @Query(filter: #Predicate<KodaiTask> { !$0.isCompleted }, sort: \KodaiTask.dueDate)
    private var openTasks: [KodaiTask]

    @Query private var commitments: [KodaiCommitment]

    private var dueTasks: [KodaiTask] {
        let endOfToday = Calendar.current.date(
            byAdding: .day, value: 1,
            to: Calendar.current.startOfDay(for: .now)
        ) ?? .now
        return openTasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            return dueDate < endOfToday
        }
    }

    private var openCommitments: [KodaiCommitment] {
        commitments
            .filter { $0.status == .open }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            glanceSection(
                title: dueTasks.isEmpty ? "Nothing due today" : "Due today (\(dueTasks.count))",
                items: dueTasks.prefix(3).map(\.title)
            )

            if !openCommitments.isEmpty {
                Divider()
                glanceSection(
                    title: "Commitments (\(openCommitments.count))",
                    items: openCommitments.prefix(3).map(\.text)
                )
            }

            Divider()

            briefingButton("Morning brief", icon: "sun.horizon.fill", kind: .morning)
            briefingButton("Evening debrief", icon: "moon.stars.fill", kind: .evening)

            Divider()

            Button {
                openMainWindow()
            } label: {
                Label("Open Kodai", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 12, design: .rounded))
        .padding(12)
        .frame(width: 260)
    }

    private func glanceSection(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            ForEach(items, id: \.self) { item in
                Text("• \(item)")
                    .lineLimit(1)
            }
        }
    }

    private func briefingButton(_ label: String, icon: String, kind: BriefingKind) -> some View {
        Button {
            RhythmScheduler.shared.pendingBriefingKind = kind
            openMainWindow()
        } label: {
            Label(label, systemImage: icon)
        }
        .buttonStyle(.plain)
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
