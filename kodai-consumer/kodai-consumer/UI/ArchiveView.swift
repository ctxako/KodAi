import SwiftUI
import SwiftData

private enum ArchiveFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case events = "Events"
    case reminders = "Reminders"
    case contacts = "Contacts"
    case files = "Files"
    case other = "Other"

    var id: String { rawValue }

    var domains: Set<String> {
        switch self {
        case .all: return []
        case .events: return ["calendar"]
        case .reminders: return ["reminders"]
        case .contacts: return ["contacts"]
        case .files: return ["files"]
        case .other: return ["clipboard", "notifications", "web"]
        }
    }
}

struct ArchiveView: View {
    @Query(
        filter: #Predicate<SessionGroup> { $0.endedAt != nil },
        sort: \SessionGroup.startedAt,
        order: .reverse
    )
    private var sessions: [SessionGroup]

    @Query(sort: \ActionCard.timestamp, order: .forward)
    private var allCards: [ActionCard]

    @State private var selectedFilter: ArchiveFilter = .all
    @State private var expandedSessions: Set<UUID> = []
    @State private var hasSetInitial = false

    var body: some View {
        ZStack {
            CanvasBackground()

            if sessions.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    filterBar

                    if filteredSessions.isEmpty {
                        Spacer()
                        emptyState
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredSessions) { group in
                                    sessionGroupView(group)

                                    if group.id != filteredSessions.last?.id {
                                        Divider()
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                    }
                                }
                            }
                            .padding(.top, 8)
                            .padding(.bottom, 16)
                        }
                    }
                }
            }
        }
        .onAppear {
            guard !hasSetInitial, !sessions.isEmpty else { return }
            expandedSessions = Set(sessions.prefix(3).map(\.id))
            hasSetInitial = true
        }
    }

    // MARK: - Computed

    private var filteredSessions: [SessionArchive] {
        let cardsBySession = Dictionary(grouping: allCards, by: \.sessionID)
        return sessions.compactMap { session in
            let cards = cardsBySession[session.id] ?? []
            let visible: [ActionCard]
            if selectedFilter == .all {
                visible = cards.filter { $0.kind != "prompt" }
            } else {
                visible = cards.filter { selectedFilter.domains.contains($0.domain) }
            }
            guard !visible.isEmpty else { return nil }
            return SessionArchive(session: session, cards: visible)
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ArchiveFilter.allCases) { filter in
                    Button {
                        withAnimation(.spring(duration: 0.25)) { selectedFilter = filter }
                    } label: {
                        Text(filter.rawValue)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                selectedFilter == filter ? Color.accentColor : Color.clear,
                                in: Capsule()
                            )
                            .foregroundStyle(selectedFilter == filter ? .white : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Session group

    private func sessionGroupView(_ group: SessionArchive) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.spring(duration: 0.3)) {
                    if expandedSessions.contains(group.id) {
                        expandedSessions.remove(group.id)
                    } else {
                        expandedSessions.insert(group.id)
                    }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.session.prompt)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(group.session.startedAt, format: .dateTime.month().day().hour().minute())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expandedSessions.contains(group.id) ? 90 : 0))
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)

            if expandedSessions.contains(group.id) {
                VStack(spacing: 8) {
                    ForEach(group.cards) { card in
                        ActionCardView(card: card)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.4))
            Text("No history yet.")
                .font(.callout)
                .foregroundStyle(.secondary.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SessionArchive: Identifiable {
    let session: SessionGroup
    let cards: [ActionCard]
    var id: UUID { session.id }
}
