import SwiftUI
import SwiftData

/// Manage saved toolflows — the one-tap tasks surfaced on the Home Screen
/// widget and runnable by Siri ("Run Morning Brief in kodAI"). The list order
/// is the widget order: the top flow fills the small widget, the top three
/// fill the medium grid.
struct ToolflowsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var store: ToolflowStore?
    @State private var editingFlow: Toolflow?
    @State private var isAddingFlow = false

    @Query(sort: \Toolflow.sortOrder, order: .forward)
    private var flows: [Toolflow]

    var body: some View {
        List {
            if flows.isEmpty {
                ContentUnavailableView(
                    "No Toolflows",
                    systemImage: "bolt.slash",
                    description: Text("Save a task you run often and it appears on the widget.")
                )
            } else {
                Section {
                    ForEach(flows) { flow in
                        Button {
                            editingFlow = flow
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: flow.icon)
                                    .foregroundStyle(.teal)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(flow.name)
                                        .foregroundStyle(.primary)
                                    Text(flow.prompt)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { store?.delete(flows[index]) }
                    }
                    .onMove { source, destination in
                        store?.move(fromOffsets: source, toOffset: destination)
                    }
                } footer: {
                    Text("Drag to reorder — the top flows fill the widget. Tap a flow to edit it.")
                }
            }
        }
        .navigationTitle("Toolflows")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button { isAddingFlow = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Toolflow")
            }
        }
        .sheet(item: $editingFlow) { flow in
            ToolflowEditorView(
                name: flow.name,
                icon: flow.icon,
                prompt: flow.prompt
            ) { name, icon, prompt in
                store?.update(flow, name: name, icon: icon, prompt: prompt)
            }
        }
        .sheet(isPresented: $isAddingFlow) {
            ToolflowEditorView { name, icon, prompt in
                store?.add(name: name, icon: icon, prompt: prompt)
            }
        }
        .onAppear {
            if store == nil { store = ToolflowStore(context: modelContext) }
        }
    }
}

// MARK: - Editor

struct ToolflowEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var icon: String
    @State private var prompt: String
    private let onSave: (String, String, String) -> Void

    init(
        name: String = "",
        icon: String = "bolt.fill",
        prompt: String = "",
        onSave: @escaping (String, String, String) -> Void
    ) {
        _name = State(initialValue: name)
        _icon = State(initialValue: icon)
        _prompt = State(initialValue: prompt)
        self.onSave = onSave
    }

    private static let icons = [
        "bolt.fill", "sun.max.fill", "moon.fill", "calendar",
        "checklist", "person.crop.circle", "doc.text",
        "doc.on.clipboard.fill", "bell.badge", "globe",
        "sparkles", "flame.fill",
    ]

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Morning Brief", text: $name)
                }
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(Self.icons, id: \.self) { symbol in
                            Button {
                                icon = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .font(.title3)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        icon == symbol ? Color.teal.opacity(0.3) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section {
                    TextField(
                        "List today's calendar events, then list my reminders.",
                        text: $prompt,
                        axis: .vertical
                    )
                    .lineLimit(3...8)
                } header: {
                    Text("What should the agent do?")
                } footer: {
                    Text("Written exactly as you'd type it in the feed — the flow runs it through the same agent, confirmations included.")
                }
            }
            .navigationTitle(name.isEmpty ? "New Toolflow" : name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            name.trimmingCharacters(in: .whitespaces),
                            icon,
                            prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
