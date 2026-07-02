//
//  kodai_consumer_widget.swift
//  kodai-consumer-widget
//
//  Home Screen toolflow launcher. Tiles are the user's saved toolflows in
//  their in-app order (small = top flow, medium = top three + "Ask kodAI").
//  A tap deep-links into the app, which runs the flow's prompt through the
//  normal agent pipeline — the widget itself never executes tools, so every
//  confirmation gate stays intact.
//

import WidgetKit
import SwiftUI

struct ToolflowEntry: TimelineEntry {
    let date: Date
    let flows: [ToolflowSnapshot]
}

struct ToolflowProvider: TimelineProvider {
    static let sampleFlows = [
        ToolflowSnapshot(id: UUID(), name: "Morning Brief", icon: "sun.max.fill",
                         prompt: "", sortOrder: 0),
        ToolflowSnapshot(id: UUID(), name: "Clip to File", icon: "doc.on.clipboard.fill",
                         prompt: "", sortOrder: 1),
        ToolflowSnapshot(id: UUID(), name: "Check Reminders", icon: "checklist",
                         prompt: "", sortOrder: 2),
    ]

    func placeholder(in context: Context) -> ToolflowEntry {
        ToolflowEntry(date: .now, flows: Self.sampleFlows)
    }

    func getSnapshot(in context: Context, completion: @escaping (ToolflowEntry) -> Void) {
        let flows = ToolflowSnapshotStore.load()
        completion(ToolflowEntry(date: .now, flows: flows.isEmpty ? Self.sampleFlows : flows))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ToolflowEntry>) -> Void) {
        // Content only changes when the app edits toolflows, and the app
        // calls reloadTimelines(ofKind:) on every mutation — no schedule.
        let entry = ToolflowEntry(date: .now, flows: ToolflowSnapshotStore.load())
        completion(Timeline(entries: [entry], policy: .never))
    }
}

// MARK: - Views

private func toolflowURL(_ flow: ToolflowSnapshot) -> URL {
    URL(string: "kodai://toolflow?id=\(flow.id.uuidString)") ?? newTaskURL
}

private let newTaskURL = URL(string: "kodai://new")!

struct ToolflowWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: ToolflowEntry

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumGrid
            default:
                smallTile
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color(red: 0.09, green: 0.11, blue: 0.14), .black],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    // Small: the single top flow fills the widget.
    @ViewBuilder
    private var smallTile: some View {
        if let flow = entry.flows.first {
            Link(destination: toolflowURL(flow)) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: flow.icon)
                        .font(.title2)
                        .foregroundStyle(.teal)
                    Spacer(minLength: 0)
                    Text(flow.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text("Tap to run")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else {
            emptyState
        }
    }

    // Medium: 2×2 grid — top three flows plus a fixed "Ask kodAI" tile.
    private var mediumGrid: some View {
        let flows = Array(entry.flows.prefix(3))
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(flows) { flow in
                Link(destination: toolflowURL(flow)) {
                    tile(icon: flow.icon, label: flow.name, tint: .teal)
                }
            }
            Link(destination: newTaskURL) {
                tile(icon: "pawprint.fill", label: "Ask kodAI", tint: .secondary)
            }
        }
    }

    private func tile(icon: String, label: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(tint)
                .frame(width: 22)
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var emptyState: some View {
        Link(destination: newTaskURL) {
            VStack(spacing: 8) {
                Image(systemName: "bolt.slash")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("Save a toolflow in kodAI Settings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Widget

struct KodaiToolflowWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "KodaiToolflows",
            provider: ToolflowProvider()
        ) { entry in
            ToolflowWidgetView(entry: entry)
        }
        .configurationDisplayName("Toolflows")
        .description("Run your saved kodAI tasks with one tap.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemMedium) {
    KodaiToolflowWidget()
} timeline: {
    ToolflowEntry(date: .now, flows: ToolflowProvider.sampleFlows)
}
