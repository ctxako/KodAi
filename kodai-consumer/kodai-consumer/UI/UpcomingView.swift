import SwiftUI
import SwiftData
import EventKit

struct UpcomingItem: Identifiable {
    let id: String
    let title: String
    let date: Date
    let domain: String
    let isAgentCreated: Bool
    let location: String?
}

private enum TimeSection: String, CaseIterable, Identifiable {
    case today = "Today"
    case tomorrow = "Tomorrow"
    case thisWeek = "This Week"
    case later = "Later"

    var id: String { rawValue }

    static func classify(_ date: Date) -> TimeSection {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return .today }
        if cal.isDateInTomorrow(date) { return .tomorrow }
        let weekEnd = cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: .now))!
        if date < weekEnd { return .thisWeek }
        return .later
    }
}

struct UpcomingView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var items: [UpcomingItem] = []
    @State private var isLoading = true

    private static let eventStore = EKEventStore()

    var body: some View {
        ZStack {
            CanvasBackground()

            if items.isEmpty && !isLoading {
                VStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary.opacity(0.4))
                    Text("Nothing coming up.")
                        .font(.callout)
                        .foregroundStyle(.secondary.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12, pinnedViews: .sectionHeaders) {
                        ForEach(groupedSections, id: \.section) { group in
                            Section {
                                ForEach(group.items) { item in
                                    UpcomingRow(item: item)
                                }
                            } header: {
                                sectionHeader(title: group.section.rawValue, count: group.items.count)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                }
                .refreshable { await loadItems() }
            }
        }
        .task { await loadItems() }
    }

    // MARK: - Grouping

    private var groupedSections: [(section: TimeSection, items: [UpcomingItem])] {
        let grouped = Dictionary(grouping: items) { TimeSection.classify($0.date) }
        return TimeSection.allCases.compactMap { section in
            guard let sectionItems = grouped[section], !sectionItems.isEmpty else { return nil }
            return (section: section, items: sectionItems)
        }
    }

    private func sectionHeader(title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.headline.bold())
                .foregroundStyle(.primary)
            Text("\(count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(.ultraThinMaterial)
    }

    // MARK: - Data loading

    private func loadItems() async {
        var result: [UpcomingItem] = []
        let now = Date()

        let agentCards = fetchAgentCards(after: now)
        var agentTitles = Set<String>()

        for card in agentCards {
            let title = card.details["title"] ?? card.summary
            agentTitles.insert(title.lowercased())
            result.append(UpcomingItem(
                id: card.id.uuidString,
                title: title,
                date: card.relatedDate!,
                domain: card.domain,
                isAgentCreated: true,
                location: card.details["location"]
            ))
        }

        let twoWeeks = Calendar.current.date(byAdding: .day, value: 14, to: now)!

        // Read only with an existing full-access grant: write-only returns no
        // events from queries, and a passive tab shouldn't spring a permission
        // prompt — the grant escalates when the user asks the agent to check
        // their calendar.
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            let predicate = Self.eventStore.predicateForEvents(withStart: now, end: twoWeeks, calendars: nil)
            for event in Self.eventStore.events(matching: predicate) {
                let title = event.title ?? "Untitled"
                guard !agentTitles.contains(title.lowercased()) else { continue }
                result.append(UpcomingItem(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: title,
                    date: event.startDate,
                    domain: "calendar",
                    isAgentCreated: false,
                    location: event.location
                ))
            }
        }

        if EKEventStore.authorizationStatus(for: .reminder) == .fullAccess {
            let predicate = Self.eventStore.predicateForReminders(in: nil)
            let reminders = await withCheckedContinuation { (cont: CheckedContinuation<[EKReminder], Never>) in
                Self.eventStore.fetchReminders(matching: predicate) { cont.resume(returning: $0 ?? []) }
            }
            for reminder in reminders where !reminder.isCompleted {
                let title = reminder.title ?? "Untitled"
                guard !agentTitles.contains(title.lowercased()),
                      let comps = reminder.dueDateComponents,
                      let due = Calendar.current.date(from: comps),
                      due > now
                else { continue }
                result.append(UpcomingItem(
                    id: reminder.calendarItemIdentifier,
                    title: title,
                    date: due,
                    domain: "reminders",
                    isAgentCreated: false,
                    location: nil
                ))
            }
        }

        result.sort { $0.date < $1.date }
        items = result
        isLoading = false
    }

    private func fetchAgentCards(after now: Date) -> [ActionCard] {
        let descriptor = FetchDescriptor<ActionCard>(
            predicate: #Predicate<ActionCard> {
                $0.kind == "action"
                && $0.relatedDate != nil
                && $0.relatedDate! > now
                && ($0.domain == "calendar" || $0.domain == "reminders")
            },
            sortBy: [SortDescriptor(\.relatedDate, order: .forward)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}

// MARK: - Row

private struct UpcomingRow: View {
    let item: UpcomingItem
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: item.domain == "calendar" ? "calendar.badge.plus" : "checklist")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(item.domain == "calendar" ? .red : .blue)
                    .frame(width: 24)

                Text(item.title)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(isExpanded ? nil : 1)

                Spacer(minLength: 4)

                Text(item.date, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if item.isAgentCreated {
                    Text("via kodai")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.15), in: Capsule())
                }
            }

            if isExpanded {
                if let location = item.location, !location.isEmpty {
                    Divider().padding(.vertical, 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Location")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(location)
                            .font(.callout)
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture {
            guard item.location != nil && !item.location!.isEmpty else { return }
            withAnimation(.spring(duration: 0.3)) { isExpanded.toggle() }
        }
    }
}
