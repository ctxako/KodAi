import SwiftUI
import SwiftData

@main
struct kodai_consumerApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var modelSetup = ModelSetupController()

    let container: ModelContainer

    init() {
        container = Self.makeContainer()
    }

    /// The action log must never take the app down. If the on-disk store was
    /// written by an incompatible earlier schema (pre-release churn), delete
    /// it and start fresh; as a last resort run with an ephemeral in-memory
    /// log rather than crashing at launch.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([ActionCard.self, SessionGroup.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        if let container = try? ModelContainer(for: schema, configurations: config) {
            return container
        }

        let fm = FileManager.default
        if let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            for name in ["default.store", "default.store-shm", "default.store-wal"] {
                try? fm.removeItem(at: support.appendingPathComponent(name))
            }
        }
        if let container = try? ModelContainer(for: schema, configurations: config) {
            return container
        }

        let memory = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: memory)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !modelSetup.isReady {
                    ModelDownloadView(setup: modelSetup)
                } else if hasCompletedOnboarding {
                    AssistantView()
                } else {
                    OnboardingView(isComplete: $hasCompletedOnboarding)
                }
            }
            .task { modelSetup.checkOnLaunch() }
        }
        .modelContainer(container)
    }
}
