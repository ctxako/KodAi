import SwiftUI
import SwiftData
import KodaiKernel

struct FeedView: View {
    @State private var controller = AssistantController()
    @State private var showSettings = false
    @FocusState private var inputFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<ActionCard> { !$0.isArchived },
        sort: \ActionCard.timestamp,
        order: .forward
    )
    private var cards: [ActionCard]

    var body: some View {
        @Bindable var ctrl = controller

        NavigationStack {
            ZStack(alignment: .bottom) {
            CanvasBackground()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if cards.isEmpty {
                            emptyState
                                .padding(.top, 120)
                        }

                        ForEach(cards) { card in
                            switch card.kind {
                            case "prompt":
                                PromptRow(card: card)
                            case "note":
                                AgentNoteView(card: card)
                            default:
                                ActionCardView(card: card)
                            }
                        }

                        if controller.isRunning {
                            HStack(spacing: 8) {
                                ThinkingDotsView()
                                Text(phaseLabel)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .id("bottom")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 80)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: cards.count) {
                    withAnimation(.smooth(duration: 0.3)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: controller.isRunning) {
                    if controller.isRunning {
                        withAnimation(.smooth(duration: 0.3)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }

            ConsumerInputBar(
                text: $ctrl.input,
                isGenerating: controller.isRunning,
                isInputFocused: $inputFocused,
                isDisabled: !controller.isModelReady,
                onSend: {
                    HapticFeedback.send()
                    controller.start()
                },
                onStop: { controller.cancel() }
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                }
            }
        }
        }
        .animation(.smooth(duration: 0.3), value: controller.isRunning)
        .preferredColorScheme(.dark)
        .sheet(item: $ctrl.pendingConfirmation) { pending in
            ConfirmCardView(
                call: pending.call,
                confidence: pending.confidence,
                onConfirm: {
                    HapticFeedback.confirm()
                    pending.resolve(.accept(pending.call))
                },
                onCancel: {
                    HapticFeedback.cancel()
                    pending.resolve(.cancel)
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $ctrl.pendingFilePicker) { pending in
            DocumentPickerView(request: pending.request) { result in
                pending.resolve(result)
            }
        }
        .onOpenURL { url in
            guard url.scheme == "kodai",
                  url.host == "task",
                  let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "q" })?.value
            else { return }
            controller.handleDeepLink(query: query)
        }
        .task {
            if controller.store == nil {
                let store = ActionStore(context: modelContext)
                controller.store = store
                store.pruneOldSessions()
            }
            controller.prewarm()
        }
        .onAppear {
            IntentActionInbox.shared.onDeposit = { [weak controller] in
                controller?.drainPendingIntentActions()
            }
            controller.drainPendingIntentActions()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { controller.drainPendingIntentActions() }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .presentationDetents([.large])
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.4))
            Text("What would you like to do?")
                .font(.callout)
                .foregroundStyle(.secondary.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Phase label

    private var phaseLabel: String {
        switch controller.phase {
        case .loading: return controller.isModelReady ? "Working…" : "Loading model…"
        case .thinking: return "Thinking…"
        case .callingTool(let name): return name.capitalized + "…"
        case .confirming: return "Waiting for confirmation…"
        default: return "Working…"
        }
    }
}
